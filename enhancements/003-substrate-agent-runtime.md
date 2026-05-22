# Enhancement 003: Agent Substrate as AI SDLC Runtime

| Field | Value |
|-------|-------|
| **Status** | Draft |
| **Author** | bpratt |
| **Created** | 2026-05-22 |
| **Dependencies** | [agent-substrate/substrate](https://github.com/agent-substrate/substrate), Enhancement 001 (Centralized Workflow Architecture) |

## Summary

Use [Agent Substrate](https://github.com/agent-substrate/substrate) as the
compute runtime for AI development agents on OpenShift. Each unit of SDLC
work becomes a Substrate **actor** — a stateful process that is suspended
to object storage when idle and restored in under a second when a relevant
event occurs. A shared pool of worker pods serves all actors across all Quay
org projects, achieving 3-5x compute efficiency over
dedicated-session-per-task models.

The model is **one actor per JIRA ticket** for its full lifecycle. The actor
implements, watches CI, responds to review feedback, and handles backports —
switching modes based on whichever event wakes it up. Substrate's
checkpoint/restore means there's no cost to an actor being idle between
events regardless of what "mode" it's in.

The initial POC is a **PR Watcher** — the monitoring and response slice of
the full ticket lifecycle. It's an event-driven Go service that receives
GitHub webhook events, reacts to CI results and review activity, optionally
invokes Claude for analysis, and suspends between events. The POC proves
three things: (1) state preservation across suspend/resume, (2) event-driven
activation via webhooks, and (3) multiplexing N actors on M workers.

## Motivation

### The Idle Agent Problem

The Ralph Loop (`/dev:work`) drives a JIRA ticket from ASSIGN to COMPLETE
in one continuous session. The state machine has 9 states, but agents spend
the vast majority of their time in two:

| State | What Happens | Time Spent |
|-------|-------------|------------|
| `DORMANT_CI` | `poll-pr.sh` sleeps 120-600s between polls | ~70% |
| `DORMANT_REVIEW` | Waiting for human reviewer, polls every 300s | ~20% |
| Active states | ASSIGN, BRANCH, IMPLEMENT, TEST, COMMIT, PR_CREATE, ADDRESS_FEEDBACK | ~10% |

An agent working a ticket consumes compute resources for the full duration,
but only uses those resources ~10% of the time. Running 20 concurrent
tickets means 20 sessions, 18 of which are sleeping at any given moment.

### The State Reconstruction Problem

When a session disconnects or times out during a dormant state, the agent
must reconstruct its context from `tick-state.json`:

```json
{
  "ticket": "PROJQUAY-1234",
  "state": "DORMANT_CI",
  "pr_number": 567,
  "branch": "PROJQUAY-1234-fix-auth",
  "tick_count": 8
}
```

This is lossy. The agent re-reads the JIRA ticket, re-reads the PR, re-loads
AGENTS.md, and rebuilds its understanding of the codebase changes it made.
Context reconstruction costs tokens and time, and the rebuilt context is
never as rich as the original.

### The Polling Problem

`poll-pr.sh` implements adaptive backoff polling: 120s base, doubling up to
600s when nothing changes. This means:

- Events are noticed 2-10 minutes after they happen, not instantly
- Sleeping processes still consume their full resource allocation
- 20 agents polling 20 PRs = 20 processes waking up periodically to check
  for changes, finding nothing, and going back to sleep

### What Agent Substrate Solves

Agent Substrate multiplexes stateful "actors" onto a smaller pool of
"worker" pods using gVisor process checkpoint/restore:

1. **Suspend idle agents**: When an agent is idle, its entire process —
   memory, file descriptors, filesystem, CPU registers — is checkpointed
   to object storage. The worker pod is freed.

2. **Resume in <1 second**: When an event arrives, the snapshot is
   downloaded, decompressed, and the process resumes from the exact
   instruction where it was suspended. No context reconstruction.

3. **Multiplex N actors on M workers (M << N)**: 20 tickets = 20 actors,
   served by 4-5 worker pods. Only the active agents consume compute.

4. **Event-driven activation**: HTTP requests to an actor's DNS name
   automatically trigger resume via Envoy's External Processing filter.
   GitHub webhooks become actor HTTP requests — instant event response
   instead of polling.

## Design

### Architecture

```
                                  +--------------------------------------+
                                  |          OpenShift Cluster           |
                                  |                                      |
GitHub ---webhook--> +---------+  |  +---------+    +----------------+   |
                     | Webhook |--+->| atenet  |--->| WorkerPool     |   |
                     | Bridge  |  |  | router  |    | (M worker pods)|   |
                     +---------+  |  | (envoy) |    |                |   |
   (OpenShift Route)     |       |  +---------+    | +------------+ |   |
                         |       |       |         | | Actor A    | |   |
                  suspend after  |       | resume  | | (RUNNING)  | |   |
                  processing     |       v         | +------------+ |   |
                         |       |  +---------+    |                |   |
                         +-------+->| ate-api |    | +------------+ |   |
                                 |  | server  |    | | Actor B    | |   |
                                 |  +---------+    | | (RUNNING)  | |   |
                                 |                 | +------------+ |   |
                                 |  Object Storage +----------------+   |
                                 |  +-------------+                     |
                                 |  | Snapshots   | Actors C..N         |
                                 |  | (SUSPENDED) | (zero compute cost) |
                                 |  +-------------+                     |
                                 +--------------------------------------+
```

### Core Concepts

**Actor = one JIRA ticket.** Each ticket gets a single actor that handles
its full lifecycle — implementation, PR monitoring, review response,
backport. The actor has a unique ID (e.g., `projquay-1234`) and runs inside
a gVisor sandbox on a worker pod. Between events, it's suspended to object
storage at zero cost. When an event wakes it, it checks what happened and
does the right thing — whether that's "check CI status" or "fix a failing
test" depends on the event, not on the actor type.

**ActorTemplate = workload definition.** Specifies the container image,
environment variables, and worker pool reference. For the POC, one template
(`pr-watcher`) handles PR monitoring. The full lifecycle template comes
later.

**WorkerPool = shared compute.** A set of pre-started pods waiting for
actor assignments. All actors across all projects share the same pool.

**Webhook Bridge = event router.** Receives GitHub/JIRA webhooks via
OpenShift Route, maps events to actor IDs, triggers actor resume via HTTP,
and manages actor lifecycle (create on PR open, suspend/delete on close).

### Traffic-Driven Activation (Built Into Substrate)

This mechanism is already implemented and is central to the design:

1. HTTP request arrives for `pr-quay-quay-1234.actors.resources.substrate.ate.dev`
2. CoreDNS resolves all `*.actors.resources.substrate.ate.dev` to the
   atenet router's ClusterIP
3. Envoy's ExtProc filter extracts the actor ID from the `Host` header
4. ExtProc calls `ResumeActor()` RPC via the ate-api-server control plane
5. Control plane assigns a free worker pod, atelet downloads the snapshot,
   gVisor restores the process from checkpoint
6. The original HTTP request is forwarded to the now-running actor on port 80

The request blocks during restore (~500ms-1s) and is then forwarded
transparently. No polling, no queuing infrastructure needed. Concurrent
requests to the same actor are deduplicated via `singleflight.Group`.

### One Actor Per Ticket

A key design question is how to handle work that crosses SDLC stages — e.g.,
when CI fails and the actor needs to switch from "monitoring" to
"implementing a fix."

**The answer is: don't decompose.** One actor handles the full ticket
lifecycle. Substrate's checkpoint/restore means there is no cost difference
between an actor that's "waiting for CI" and one that's "waiting for JIRA
assignment." Both are suspended snapshots in object storage at zero compute
cost. The actor simply wakes up, checks what event arrived, and does
whatever is appropriate:

```
Actor per ticket (e.g., projquay-1234)
  |
  |-- webhook: JIRA ticket assigned
  |     → create branch, implement fix, run tests, create PR
  |     → suspended
  |
  |-- webhook: check_run completed (failure)
  |     → analyze failure, fix code, push
  |     → suspended
  |
  |-- webhook: pull_request_review (changes_requested)
  |     → read feedback, update code, push
  |     → suspended
  |
  |-- webhook: check_run completed (success) + approved
  |     → post "ready to merge" comment
  |     → suspended
  |
  +-- webhook: pull_request closed/merged
        → handle backport if needed, clean up, done
```

**Why not separate actor types per stage** (watcher, implementer, etc.):

- Adds coordination complexity — actors must communicate, manage each
  other's lifecycles, and handle failure of the other
- No efficiency gain — Substrate suspends idle actors regardless of what
  "stage" they represent. A 500MB implementation actor and a 10MB watcher
  actor cost the same when suspended: the price of object storage.
- The actor already has all the context (JIRA ticket, codebase
  understanding, PR state). Splitting it means reconstructing or
  transferring that context between actors.

**For the POC**, the actor handles only the PR watching slice (CI, reviews,
threads). The full lifecycle (JIRA triage, implementation, backport) is a
natural extension of the same actor — adding event handlers, not adding
actor types.

### PR Watcher Actor (POC Workload)

The PR Watcher is designed from scratch as an **event-driven** system, not a
port of the polling-based `poll-pr.sh`. The fundamental difference: the
actor doesn't ask "what changed since I last checked?" — it receives the
event payload and reacts to *what just happened*.

#### Data Model

Minimal in-memory state — decision-making signals, not cached API responses:

```go
type PRState struct {
    Repo   string
    Number int
    HeadSHA string

    CIStatus    string // pending | passing | failing
    HasApproval bool
    ThreadsOpen int    // unresolved review threads (human + bot)
    Conclusion  string // pending | actionable | ready | merged | closed

    Actions []ActionRecord // audit trail of what actor did
}

type ActionRecord struct {
    Timestamp time.Time
    Event     string // what triggered this (e.g., "check_suite.completed")
    Decision  string // what we decided (e.g., "invoke_claude_ci_analysis")
    Result    string // what happened (e.g., "posted comment #42")
}
```

No poll count. No adaptive backoff. No previous-check-state maps for delta
computation. The webhook *is* the delta.

#### HTTP API

```
POST /event          Receive GitHub webhook payload (X-GitHub-Event header)
                     Returns: {keepAlive: bool, message: string}

GET  /health         Readiness probe (200 OK)

POST /claude-callback   Receive async Claude analysis result
                        Returns: 202 Accepted
```

Single `/event` endpoint. The `X-GitHub-Event` header tells the handler
which event type it is. This simplifies webhook bridge routing — it
forwards all events to the same actor endpoint.

#### Event Processing

| GitHub Event | Actor Response |
|-------------|---------------|
| `pull_request` (opened) | Initialize PRState, return |
| `pull_request` (synchronize) | Update HeadSHA, reset CIStatus to pending |
| `check_run` (completed, failed) | Set CIStatus=failing, invoke Claude to analyze logs, return `keepAlive: true` |
| `check_run` (completed, success) | Update CIStatus, check if all passing → set Conclusion=ready |
| `pull_request_review` (approved) | Set HasApproval=true, recalculate Conclusion |
| `pull_request_review` (changes_requested) | Set Conclusion=actionable (full lifecycle: fix code and push) |
| `pull_request_review_thread` (resolved) | Decrement ThreadsOpen, recalculate Conclusion |
| `issue_comment` (created, by human) | Invoke Claude to draft response if needed |
| `pull_request` (closed/merged) | Set Conclusion=merged/closed, return |

**When Claude is invoked** (only two triggers for the POC):

1. CI failure with logs available → analyze root cause, post comment
2. New unresolved review thread from a human → draft a response

Everything else is mechanical state updates and GitHub API calls.

#### Response Protocol

```go
type EventResponse struct {
    KeepAlive bool   `json:"keepAlive"`
    Message   string `json:"message"`
}
```

- `keepAlive: false` → webhook bridge suspends the actor after receiving
  this response (the common case)
- `keepAlive: true` → actor has kicked off async work (Claude analysis)
  and should not be suspended yet. The Claude callback will eventually
  return `keepAlive: false`

#### Error Handling

- **GitHub API failure** (post comment fails): Log, don't crash. Next event
  will retry based on current state.
- **Claude API failure**: Post fallback comment with log URL, return
  `keepAlive: false`.
- **Suspension mid-processing**: Won't happen if `keepAlive: true` is
  respected. If actor crashes before responding, webhook bridge retries
  (GitHub webhooks are delivered at-least-once).
- **Startup**: Load `/state/pr-monitor.json` from filesystem, or initialize
  empty state. Filesystem persists across checkpoint/restore.

### Webhook Bridge

A Go HTTP server deployed as a standard OpenShift Deployment, exposed via
Route to receive GitHub webhooks.

| GitHub Event | Bridge Action |
|-------------|--------------|
| `pull_request.opened` | `CreateActor` gRPC, then HTTP POST to actor |
| `pull_request.closed` | `SuspendActor` gRPC, then `DeleteActor` gRPC |
| `pull_request.synchronize` | HTTP POST to actor |
| `check_suite.completed` | HTTP POST to actor |
| `check_run.completed` | HTTP POST to actor |
| `pull_request_review.submitted` | HTTP POST to actor |
| `pull_request_review_thread.*` | HTTP POST to actor |
| `issue_comment.created` | HTTP POST to actor |

**Actor ID convention**: `pr-{owner}-{repo}-{number}` (e.g.,
`pr-quay-quay-1234`).

**Lifecycle flow for each event POST**:

1. Verify GitHub webhook signature (HMAC-SHA256)
2. Extract PR number and repo from payload
3. Compute actor ID
4. HTTP POST webhook payload to
   `{actor-id}.actors.resources.substrate.ate.dev`
   (Substrate's ExtProc automatically resumes the actor if suspended)
5. Wait for response
6. If `keepAlive: false` → call `SuspendActor` gRPC to checkpoint and free
   the worker pod
7. If `keepAlive: true` → leave actor running (Claude analysis in progress)

### OpenShift Deployment Considerations

Substrate was designed for GKE. Running on OpenShift requires addressing
several platform differences:

#### Security Context Constraints

gVisor (`runsc`) requires elevated privileges: it creates sandboxes,
manipulates network namespaces, and manages cgroups. Worker pods and the
atelet DaemonSet need `privileged` SCC:

```bash
oc adm policy add-scc-to-user privileged -z atelet -n ate-system
oc adm policy add-scc-to-user privileged -z default -n ate-system
```

For the POC, `privileged` SCC is acceptable. For production, a custom SCC
scoped to the minimum required capabilities (SYS_ADMIN, SYS_PTRACE,
NET_ADMIN) should be investigated.

#### SELinux

RHCOS enforces SELinux. gVisor's sandbox operations (filesystem mounts,
namespace manipulation, checkpoint I/O) may trigger AVC denials. For the
POC, worker pod containers should use `seLinuxOptions.type: spc_t`
(super-privileged container). This is a known risk area that needs early
validation — if gVisor cannot function under RHCOS's SELinux policy, it is
a hard blocker.

#### DNS Integration

Substrate deploys its own CoreDNS instance for actor DNS resolution.
OpenShift manages DNS via the `dns.operator`. These must not conflict.

**Approach**: Run Substrate's CoreDNS as a secondary service. Configure
the OpenShift DNS operator to forward the `actors.resources.substrate.ate.dev`
zone to Substrate's CoreDNS service, rather than modifying `kube-system`
ConfigMaps directly. Alternatively, configure actor pods with
`dnsPolicy: None` and explicit `dnsConfig` pointing to Substrate's DNS.

#### Ingress

The webhook bridge needs an OpenShift Route to receive GitHub webhooks:

```bash
oc expose svc/webhook-bridge --port=8080 -n ate-sdlc
```

The atenet-router (Envoy) is cluster-internal only and does not need a
Route.

#### Image Registry

Use quay.io for workload images. `ko` pushes directly:

```bash
export KO_DOCKER_REPO=quay.io/quay-devel/substrate-demos
```

#### Object Storage

For snapshots, use S3-compatible storage (Noobaa/MCG on OpenShift, or
external S3/GCS). Substrate already supports S3 via the `ategcs` package's
`ObjectStorage` interface.

#### Key Risk: gVisor on RHCOS

gVisor (`runsc`) must function on RHCOS (Red Hat CoreOS) nodes. This is
unvalidated. RHCOS uses a specific kernel version and SELinux policy.
**This must be tested early** — if `runsc create` or `runsc checkpoint`
fail on RHCOS, the entire approach is blocked.

Mitigation: Test `runsc` on a bare RHCOS node before investing in the
full Substrate deployment. If RHCOS is incompatible, evaluate Kata
Containers (microVMs) as an alternative sandbox runtime — Substrate's
architecture supports pluggable sandbox runtimes, and Kata supports
checkpoint/restore via CRIU.

## Implementation Plan

### Phase 1: Validate gVisor on OpenShift

Before building anything, confirm that gVisor functions on RHCOS:

1. Provision an OpenShift cluster (or use an existing one)
2. Deploy a privileged pod with `runsc` binary
3. Test: `runsc create`, `runsc start`, `runsc checkpoint`, `runsc restore`
4. Identify and resolve any SELinux or kernel compatibility issues

**Exit criteria**: `runsc checkpoint` + `runsc restore` works on RHCOS.
If it doesn't, evaluate Kata Containers or propose kernel/SELinux changes.

### Phase 2: Deploy Substrate on OpenShift

Install the Substrate control plane and worker infrastructure:

1. Install CRDs (ActorTemplate, WorkerPool)
2. Deploy ate-api-server, atenet-router, atenet-dns, valkey-cluster
3. Configure DNS forwarding for `actors.resources.substrate.ate.dev`
4. Grant privileged SCC to ate-system service accounts
5. Validate with the existing counter demo

**Exit criteria**: `kubectl ate create/resume/suspend/delete actor` works
on OpenShift with the counter demo.

### Phase 3: PR Watcher Workload + Webhook Bridge

Build and deploy the PR Watcher actor and webhook bridge:

**Deliverables:**

```
substrate/demos/pr-watcher/
  workload/
    main.go              # HTTP server: /event, /health, /claude-callback
    handlers.go          # Event processing logic per GitHub event type
    state.go             # PRState management, filesystem persistence
    claude.go            # Claude API client for async analysis
    Dockerfile
    go.mod
  webhook-bridge/
    main.go              # HTTP server: /github-webhook
    lifecycle.go         # Actor create/suspend/delete via ate-api gRPC
    Dockerfile
    go.mod

substrate/manifests/pr-watcher/
  pr-watcher.yaml.tmpl       # Namespace, WorkerPool, ActorTemplate
  webhook-bridge.yaml.tmpl   # Deployment, Service, Route
```

**Demo: Manual lifecycle (no webhooks)**

```bash
# Deploy
./hack/install-ate.sh --deploy-demo-pr-watcher

# Create actor for a real PR
kubectl ate create actor pr-quay-quay-1234 \
  --template ate-demo-pr-watcher/pr-watcher

# Send a simulated check_suite event via HTTP
curl -X POST \
  -H "Host: pr-quay-quay-1234.actors.resources.substrate.ate.dev" \
  -H "X-GitHub-Event: check_suite" \
  -d '{"action":"completed","check_suite":{"conclusion":"failure",...}}' \
  http://<atenet-router-clusterip>:8080/event

# Actor resumes from golden snapshot, processes event, responds
# Suspend it
kubectl ate suspend actor pr-quay-quay-1234

# Send another event — actor resumes, state preserved from previous event
curl -X POST ...
# → Actor remembers previous CI state, computes what changed
```

**Demo: Webhook-driven (with bridge)**

```bash
# Port-forward or expose webhook bridge
oc expose svc/webhook-bridge -n ate-demo-pr-watcher

# Configure GitHub webhook on a test repo pointing to the Route URL
# Open a PR → bridge creates actor
# Push a commit → bridge wakes actor
# CI completes → bridge wakes actor
# Actor processes, gets suspended between events

# Watch the fleet
kubectl ate get actors -n ate-demo-pr-watcher
# NAME                  STATUS     WORKER
# pr-quay-quay-1234    SUSPENDED  -
# pr-quay-quay-5678    RUNNING    worker-1
# pr-quay-clair-42     SUSPENDED  -
```

**Demo: Multiplexing**

Create more actors than workers to show suspend/resume multiplexing:

```bash
# WorkerPool has 2 replicas, create 4 actors
for pr in 101 202 303 404; do
  kubectl ate create actor pr-quay-quay-$pr \
    --template ate-demo-pr-watcher/pr-watcher
done

# Send events to different actors — watch Substrate swap them on/off workers
```

**Exit criteria**: An actor receives a GitHub event, processes it, gets
suspended, receives another event, resumes with full state from the
previous event intact. Multiple actors share a smaller WorkerPool.

### Phase 4: Claude Integration

Add Claude-powered analysis for CI failures and review comments:

- CI failure → Claude analyzes logs, posts root cause comment on PR
- Review thread → Claude drafts response

Claude called via HTTP API from Go (not CLI) for lower overhead inside
gVisor. Use Vertex AI with Workload Identity on OpenShift (preferred) or
direct Anthropic API key.

## Future Direction

This enhancement intentionally scopes to the PR Watcher POC — the
monitoring and response slice of the full ticket lifecycle. The following
are natural next steps, deferred to separate enhancements:

- **Full ticket lifecycle actor**: Extend the PR Watcher workload to handle
  the complete JIRA ticket flow — triage, branch creation, implementation,
  testing, PR creation, backport. This is additive: new event handlers in
  the same actor, not new actor types. The JIRA webhook bridge maps ticket
  events to actor lifecycle operations the same way the GitHub webhook
  bridge does for PR events.

- **ai-helpers plugin integration**: Determining how the existing plugin
  infrastructure (skills, scripts, Lola) maps onto Substrate actor
  workloads — whether to embed scripts in images, run Lola at golden
  snapshot time, or rewrite core logic in Go.

- **Fleet-wide observability**: Dashboard, metrics, cost reporting across
  all active actors and projects.

## Alternatives Considered

### Keep Current Session Model, Add Substrate Under It

Use existing session infrastructure for workflow management, with
Substrate providing only the suspend/resume layer underneath.

**Rejected because:** The current session model assumes one long-running
process per workflow. Substrate's value comes from decomposing the workflow
into independent actors with distinct lifecycles. Layering Substrate under
existing sessions would add complexity without enabling the
actor-per-stage decomposition.

### Kubernetes Jobs Per Event

Use Kubernetes Jobs instead of Substrate actors: each GitHub event triggers
a Job that processes the event and exits.

**Rejected because:** Jobs don't preserve state between invocations. Each
Job would need to reconstruct context from external storage. Substrate's
checkpoint/restore gives free state continuity — the process continues from
where it left off, including in-memory state and filesystem contents.

Additionally, Job startup latency (image pull + container start + process
init) is 5-30 seconds. Substrate restore is <1 second.

### Separate Actor Types Per SDLC Stage

Decompose the lifecycle into distinct actor types: a Triage Actor, an
Implementation Actor, a PR Watcher Actor, a Backport Actor. Each stage
is a different workload image and actor type.

**Rejected because:** Substrate suspends idle actors to object storage
regardless of what "stage" they represent — there's no efficiency gain
from decomposition. Meanwhile, decomposition adds coordination complexity:
actors must communicate, manage each other's lifecycles, and handle
failure of peer actors. The single-actor model keeps all ticket context
in one place and lets checkpoint/restore handle the state transitions
between stages for free.

## Open Questions

1. **gVisor on RHCOS.** Unvalidated. gVisor's `runsc` must function under
   RHCOS's kernel and SELinux policy. If it doesn't, the entire approach
   is blocked. This is the highest-risk item and must be validated first.

2. **Secret management.** Substrate does not support
   `valueFrom.secretKeyRef` in ActorTemplate env (substrate issue #197).
   For the POC, tokens are plain env var values. For production, this gap
   needs resolution — either upstream contribution or Kubernetes Secret
   mounting on worker pods.

3. **Actor-initiated suspend.** The current design requires the webhook
   bridge to call `SuspendActor` after the actor finishes processing. It
   would be cleaner if the workload could signal "suspend me" from inside
   the gVisor sandbox. This likely requires a new Substrate API.

4. **Auto-suspend / idle timeout.** Substrate has no automatic idle
   detection. If the webhook bridge fails to suspend an actor, it stays
   running indefinitely. An idle timeout would provide a safety net.

5. **Snapshot garbage collection.** Substrate does not yet implement
   snapshot GC. Frequent suspend/resume will accumulate snapshots in
   object storage. Need to understand the GC roadmap or implement
   external cleanup.

6. **Observability across suspends.** Actor logs are tied to the worker
   pod. When an actor resumes on a different worker, logs are split.
   `kubectl ate logs` handles this, but integration with OpenShift's
   logging stack needs investigation.

## Benefits

- **3-5x compute efficiency** — idle agents cost zero (suspended to storage)
- **<1 second resume** — gVisor checkpoint/restore, no context reconstruction
- **Event-driven** — GitHub webhooks trigger instant actor resume, no polling
- **True state preservation** — entire process state survives suspend/resume
- **Simple model** — one actor per ticket, no inter-actor coordination
- **Cross-project sharing** — one WorkerPool serves all Quay org projects
- **Fleet visibility** — `kubectl ate get actors` across projects and stages
- **OpenShift native** — deployed via Routes, SCCs, and standard OpenShift
  tooling
