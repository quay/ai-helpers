# konflux-build-debugger

Automated Konflux build failure debugger workflow for the
[Ambient Code Platform](https://ambient.engineering).

## What it does

Debugs a **single Konflux build failure** from diagnosis through
merge-ready PR. Spawned by the
[konflux-build-triage](../konflux-build-triage/) agent with full failure
context.

For a specific failing component, it:
1. Independently pulls PipelineRun logs from KubeArchive
2. Applies Konflux debugging skills for systematic root cause analysis
3. Implements a fix and creates a PR
4. Polls CI using poll-pr.sh — handles failures and review comments
5. Loops until CI passes and review is approved, or triage cap (3 attempts)

## Architecture

```text
┌──────────────────────────────────┐
│   konflux-build-triage           │
│   (hourly cron)                  │
│                                  │
│   Finds failed builds            │
│   Classifies & deduplicates      │
│         │                        │
│   Spawns debugger session ───────┼────┐
│   with failure context           │    │
└──────────────────────────────────┘    │
                                        ▼
                              ┌─────────────────────────────┐
                              │   konflux-build-debugger     │
                              │   (tick-loop agent)          │
                              │                              │
                              │   DIAGNOSE (KubeArchive)     │
                              │         │                    │
                              │   IMPLEMENT (write fix)      │
                              │         │                    │
                              │   COMMIT (push)              │
                              │         │                    │
                              │   PR_CREATE                  │
                              │         │                    │
                              │   DORMANT_CI ◄──┐            │
                              │         │       │            │
                              │   ADDRESS_FEEDBACK           │
                              │         │                    │
                              │   DORMANT_REVIEW             │
                              │         │                    │
                              │   COMPLETE                   │
                              └─────────────────────────────┘
```

## State Machine

| State | Description |
|-------|-------------|
| DIAGNOSE | Pull logs from KubeArchive, apply debugging skills, form root cause |
| IMPLEMENT | Create fix branch, write the fix |
| COMMIT | Stage, commit, push |
| PR_CREATE | Create PR with root cause and PipelineRun reference |
| DORMANT_CI | Yield point — poll-pr.sh blocks (0 tokens consumed) |
| ADDRESS_FEEDBACK | Fix CI failures or respond to review comments |
| DORMANT_REVIEW | Yield point — awaiting human review approval |
| COMPLETE | PR is merge-ready |

DORMANT states are yield points where `poll-pr.sh` blocks internally,
consuming zero tokens while waiting. The triage cap stops the loop
after 3 failed ADDRESS_FEEDBACK attempts.

## Compaction Resilience

The initial prompt from the triage agent will be compacted away during
long-running sessions. The DIAGNOSE state persists all critical data
(PipelineRun name, repo, branch, diagnosis) into tick-state. Every
subsequent state operates from tick-state alone.

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `KONFLUX_NAMESPACE` | `quay-eng-tenant` | K8s namespace |
| `KONFLUX_KUBECONFIG_DATA` | — | Base64-encoded kubeconfig |
| `DEFAULT_REPO` | — | GitHub owner/repo (set by triage agent) |
| `PRIMARY_BRANCH` | — | Target branch for fix PRs (set by triage agent) |

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/extract-failure-context.sh` | Extract TaskRun logs from a failed PipelineRun (with KubeArchive fallback) |
| `.claude/scripts/tick-state.sh` | Per-component state file management (from dev plugin) |
| `.claude/scripts/poll-pr.sh` | Stateful PR polling with exit codes (from dev plugin) |

## Plugin Dependencies

Defined in `.lola-req`:
- `konflux-ci/skills` — Konflux debugging skills (debugging-pipeline-failures, etc.)
- `quay/ai-helpers/plugins/dev` — Development lifecycle scripts (tick-state.sh, poll-pr.sh)
