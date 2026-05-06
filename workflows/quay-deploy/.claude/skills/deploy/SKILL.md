---
name: deploy
description: >
  State-machine workflow for Quay RC deployment on ephemeral OpenShift clusters.
  Provisions cluster, configures Konflux image mirroring, installs storage,
  deploys quay-operator from FBC catalog, validates the UI with Playwright,
  and optionally black-box tests a specific feature.
argument-hint: <FBC_IMAGE> [--channel stable-3.XX] [--ocp-version 4.XX] [--feature <path|PROJQUAY-XXXX>] [--manual]
allowed-tools:
  - Bash(bash .claude/scripts/deploy-state.sh *)
  - Bash(bash .claude/scripts/cluster-provision.sh *)
  - Bash(bash .claude/scripts/configure-cluster.sh *)
  - Bash(bash .claude/scripts/remote-playwright.sh *)
  - Bash(npx @playwright/cli*)
  - Bash(oc *)
  - Bash(jq *)
  - Bash(curl *)
  - Bash(acli *)
  - Read
  - Glob
  - Grep
  - AskUserQuestion
---

# /deploy — Quay RC Deployment Pipeline

Deploy a Quay release candidate from a Konflux FBC build onto an ephemeral
OpenShift cluster. One state machine from cluster claim to verified, frontend-
tested Quay instance.

---

## Execution Model

Parse `$ARGUMENTS`: the first token is the FBC image reference (required).
Remaining tokens are parsed for flags.

```
FBC_IMAGE  = first token of $ARGUMENTS (required)
CHANNEL    = --channel value or auto-detected from image ref
OCP_VERSION = --ocp-version value or "4.18"
KUBECONFIG_PATH = --kubeconfig value or "/tmp/k"
FEATURE    = --feature value or empty (file path or JIRA ticket)
MODE       = "manual" if --manual present, else "auto"
```

Derive a `DEPLOY_ID` from the image digest: take the first 12 chars after
`@sha256:`. Example: `deploy-f7f0740742d6`.

### Initialize or Resume

```bash
bash .claude/scripts/deploy-state.sh init $DEPLOY_ID \
  --fbc-image "$FBC_IMAGE" \
  --channel "$CHANNEL" \
  --ocp-version "$OCP_VERSION" \
  --kubeconfig "$KUBECONFIG_PATH" \
  --feature "$FEATURE" \
  --mode "$MODE"
```

If state already exists, this prints the current state and resumes from there.

### Resuming After Context Compaction

If context was compacted and you no longer know the DEPLOY_ID, discover it:

```bash
bash .claude/scripts/deploy-state.sh list
```

This lists all active deployments with their ID, state, and FBC image. Pick
the active (non-COMPLETE) deployment and read its full state:

```bash
bash .claude/scripts/deploy-state.sh read <DEPLOY_ID>
```

The state file contains ALL variables needed to resume: `fbc_image`, `channel`,
`ocp_version`, `kubeconfig_path`, `feature_path`, `mode`, and all recorded
cluster/operator/route details. Parse these from the state JSON and continue
the loop from the current state.

### The State Loop

```
while state != COMPLETE:
    1. READ   — bash .claude/scripts/deploy-state.sh read $DEPLOY_ID
    2. ACT    — execute the handler for the current state (below)
    3. WRITE  — bash .claude/scripts/deploy-state.sh advance $DEPLOY_ID <NEXT_STATE>
    4. PAUSE  — if manual mode: ask user [c]ontinue / [s]kip / [i]nspect / [a]bort
    5. LOOP   — go back to step 1
```

**CRITICAL**: Do NOT stop between ticks. The loop is continuous. The only valid
exit points are:
- State reaches `COMPLETE`
- Manual mode and user chooses `[a]bort`
- `retry_count >= 3` (ask user for guidance)

---

## State Handlers

### PROVISION

Provision an ephemeral OpenShift cluster via Gangway.

```bash
bash .claude/scripts/cluster-provision.sh up "$KUBECONFIG_PATH" "$OCP_VERSION"
```

This blocks until the cluster is ready (up to 40 minutes). Wait for
`=== Cluster Ready ===` output.

Record cluster details:
```bash
CLUSTER_API=$(oc --kubeconfig="$KUBECONFIG_PATH" whoami --show-server)
bash .claude/scripts/deploy-state.sh set $DEPLOY_ID cluster_api_url "$CLUSTER_API"

CONSOLE=$(oc --kubeconfig="$KUBECONFIG_PATH" get route console -n openshift-console -o jsonpath='{.spec.host}' 2>/dev/null || true)
bash .claude/scripts/deploy-state.sh set $DEPLOY_ID cluster_console_url "https://$CONSOLE"
```

→ advance to **CONFIGURE_PULL_SECRETS**

---

### CONFIGURE_PULL_SECRETS

Merge Konflux registry credentials into the cluster's global pull secret.

```bash
bash .claude/scripts/configure-cluster.sh patch-pull-secret "$KUBECONFIG_PATH"
```

This reads `$KONFLUX_IMAGE_PULL_TOKEN` env var and generates a dockerconfigjson
for `image-rbac-proxy.apps.stone-prd-rh01.pg1f.p1.openshiftapps.com`, then
merges it into the cluster's global pull secret.

Record:
```bash
bash .claude/scripts/deploy-state.sh set $DEPLOY_ID pull_secret_configured true
```

→ advance to **APPLY_MIRRORS**

---

### APPLY_MIRRORS

Detect OCP version and apply IDMS (4.14+) or ICSP (older) for Konflux mirrors.

```bash
OCP_VER=$(bash .claude/scripts/configure-cluster.sh detect-ocp-version "$KUBECONFIG_PATH")
bash .claude/scripts/deploy-state.sh set $DEPLOY_ID ocp_detected_version "$OCP_VER"
```

Extract Quay version number from channel (e.g. `stable-3.18` → `18`):
```bash
QUAY_VER=$(echo "$CHANNEL" | sed 's/stable-3\.//')
```

Apply mirrors:
```bash
MIRROR_TYPE=$(bash .claude/scripts/configure-cluster.sh apply-mirrors "$KUBECONFIG_PATH" "$QUAY_VER")
bash .claude/scripts/deploy-state.sh set $DEPLOY_ID mirror_type "$MIRROR_TYPE"
```

→ advance to **WAIT_MCP**

---

### WAIT_MCP

After applying ICSP/IDMS, MachineConfigPools restart. Wait for them to stabilize.

```bash
bash .claude/scripts/configure-cluster.sh wait-mcp "$KUBECONFIG_PATH" 1200
```

This blocks up to 20 minutes. If it exits non-zero (timeout), increment
`retry_count`. If `retry_count >= 3`, stop and ask the user.

→ advance to **INSTALL_STORAGE**

---

### INSTALL_STORAGE

Deploy NooBaa via ODF for S3-compatible object storage.

```bash
bash .claude/scripts/configure-cluster.sh install-storage "$KUBECONFIG_PATH"
```

Blocks until NooBaa is Ready.

Record:
```bash
bash .claude/scripts/deploy-state.sh set $DEPLOY_ID storage_ready true
```

→ advance to **INSTALL_CATALOG**

---

### INSTALL_CATALOG

Create the CatalogSource pointing to the Konflux FBC image.

```bash
bash .claude/scripts/configure-cluster.sh install-catalog "$KUBECONFIG_PATH" "$FBC_IMAGE"
```

Record:
```bash
bash .claude/scripts/deploy-state.sh set $DEPLOY_ID catalog_name "konflux-quay-catalog"
```

→ advance to **SUBSCRIBE**

---

### SUBSCRIBE

Create the OLM Subscription for quay-operator from the FBC catalog.

```bash
bash .claude/scripts/configure-cluster.sh subscribe "$KUBECONFIG_PATH" "$CHANNEL" "quay"
```

→ advance to **WAIT_OPERATOR**

---

### WAIT_OPERATOR

Poll until the quay-operator CSV reaches `Succeeded` phase.

```bash
CSV_NAME=$(bash .claude/scripts/configure-cluster.sh wait-operator "$KUBECONFIG_PATH" "quay" 600)
```

On success, record CSV details:
```bash
bash .claude/scripts/deploy-state.sh set $DEPLOY_ID operator_csv "$CSV_NAME"
CSV_VERSION=$(oc --kubeconfig="$KUBECONFIG_PATH" get csv "$CSV_NAME" -n quay \
  -o jsonpath='{.spec.version}' 2>/dev/null || true)
bash .claude/scripts/deploy-state.sh set $DEPLOY_ID operator_version "$CSV_VERSION"
```

On timeout, increment `retry_count`. If >= 3, stop and ask user.

→ advance to **DEPLOY_QUAY**

---

### DEPLOY_QUAY

Create the QuayRegistry CR.

```bash
bash .claude/scripts/configure-cluster.sh deploy-quay "$KUBECONFIG_PATH" "quay" "example-registry"
```

→ advance to **WAIT_QUAY**

---

### WAIT_QUAY

Poll until the QuayRegistry reports `Available`.

```bash
bash .claude/scripts/configure-cluster.sh wait-quay "$KUBECONFIG_PATH" "quay" "example-registry" 900
```

On success, record the route:
```bash
QUAY_ROUTE=$(oc --kubeconfig="$KUBECONFIG_PATH" get route -n quay \
  -l quay-operator/quayregistry=example-registry \
  -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)
bash .claude/scripts/deploy-state.sh set $DEPLOY_ID quay_route "https://$QUAY_ROUTE"
```

On timeout, increment `retry_count`. If >= 3, stop and ask user.

→ advance to **VERIFY**

---

### VERIFY

Run health checks on the deployed Quay instance.

```bash
bash .claude/scripts/configure-cluster.sh verify "$KUBECONFIG_PATH" "quay" "example-registry"
```

→ advance to **VALIDATE_UI**

---

### VALIDATE_UI

Deploy a remote Playwright browser on the cluster and validate the Quay
frontend through interactive browser testing.

**Step 1: Deploy Playwright**

```bash
bash .claude/scripts/remote-playwright.sh up "$KUBECONFIG_PATH" playwright
```

Wait for `=== Ready ===`. Record:
```bash
bash .claude/scripts/deploy-state.sh set $DEPLOY_ID playwright_deployed true
```

**Step 2: Navigate to Quay**

```bash
npx @playwright/cli goto "https://$QUAY_ROUTE"
```

**Step 3: Validate login page**

Take a snapshot to identify form elements:
```bash
npx @playwright/cli snapshot
npx @playwright/cli screenshot /tmp/quay-validate/login-page.png
```

Verify the accessibility tree contains username/password fields and a login
button.

**Step 4: Login as admin**

Extract the initial admin credentials:
```bash
ADMIN_PASS=$(oc --kubeconfig="$KUBECONFIG_PATH" get secret -n quay \
  example-registry-quay-config-editor-credentials \
  -o jsonpath='{.data.password}' | base64 -d)
```

Use the refs from the snapshot to fill and submit the login form:
```bash
npx @playwright/cli fill "<username-ref>" "quayadmin"
npx @playwright/cli fill "<password-ref>" "$ADMIN_PASS"
npx @playwright/cli click "<login-button-ref>"
```

(The actual ref values come from the snapshot — read them dynamically.)

**Step 5: Verify post-login**

Snapshot the dashboard. Verify it shows the repositories page or organization
list. Screenshot for evidence.

**Step 6: Smoke tests with video**

Start video recording for the smoke test session:
```bash
npx @playwright/cli video-start /tmp/quay-validate/smoke-test.webm
```

Walk through key pages:
- Navigate to repository list — snapshot + screenshot
- Navigate to organization settings — snapshot + screenshot
- Navigate to superuser panel — snapshot + screenshot

If any page shows an error or unexpected behavior:
- **Keep the video recording running** — the recording captures the full repro
- Take a screenshot at the failure point
- Take a snapshot for accessibility tree context

```bash
npx @playwright/cli video-stop
```

Record results:
```bash
bash .claude/scripts/deploy-state.sh set $DEPLOY_ID frontend_validated true
```

If bugs were found, record them:
```bash
bash .claude/scripts/deploy-state.sh set $DEPLOY_ID ui_bugs '["description + /tmp/quay-validate/smoke-test.webm"]'
```

If `feature_path` is set → advance to **VALIDATE_FEATURE**.
If `feature_path` is null → teardown Playwright and advance to **COMPLETE**.

---

### VALIDATE_FEATURE

Black-box test a specific feature through the browser. **Only entered if
`--feature` was provided.**

**Step 1: Load the feature description**

- If `feature_path` is a file path: `Read` the file
- If `feature_path` looks like a JIRA ticket (e.g. `PROJQUAY-1234`):
  ```bash
  acli jira workitem view $FEATURE_PATH
  ```

Understand the feature: what it does, acceptance criteria, expected UI flows.

**Step 2: Design test plan**

Based on the feature description, design black-box test steps:
- What UI flows exercise this feature
- What inputs to provide
- What expected outcomes to verify
- Edge cases (empty inputs, special characters, permissions)

**Step 3: Execute tests with video recording**

For each test step, start video recording:
```bash
npx @playwright/cli video-start /tmp/quay-validate/feature-test-N.webm
```

Use `npx @playwright/cli` commands (goto, snapshot, click, fill, screenshot)
to walk through each test step. After each action, take a snapshot to verify
the result matches expectations.

```bash
npx @playwright/cli video-stop
```

**Step 4: Bug detection and recording**

If unexpected behavior is observed (error page, missing element, wrong content,
crash):
- **Keep the video recording running** — it captures the full reproduction
- Take a screenshot: `npx @playwright/cli screenshot /tmp/quay-validate/bug-N.png`
- Take a snapshot for accessibility tree context
- Attempt to reproduce one more time to confirm consistency
- Stop the video: `npx @playwright/cli video-stop`
- The `.webm` video file is the primary artifact for human review

**Step 5: Record results**

```bash
bash .claude/scripts/deploy-state.sh set $DEPLOY_ID feature_tested true
bash .claude/scripts/deploy-state.sh set $DEPLOY_ID feature_summary "<pass/fail summary>"
bash .claude/scripts/deploy-state.sh set $DEPLOY_ID artifacts '["<list of video/screenshot paths>"]'
```

**Step 6: Teardown Playwright**

```bash
bash .claude/scripts/remote-playwright.sh down "$KUBECONFIG_PATH" playwright
```

→ advance to **COMPLETE**

---

### COMPLETE

Terminal state. Print the final deployment summary:

```
═══════════════════════════════════════════════════════════
  COMPLETE — Quay RC Deployment + Validation
═══════════════════════════════════════════════════════════
  Cluster API:     <cluster_api_url>
  Console:         <cluster_console_url>
  Kubeconfig:      <kubeconfig_path>
  OCP Version:     <ocp_detected_version>
  Mirror Type:     <mirror_type> (IDMS or ICSP)
  Operator CSV:    <operator_csv> (v<operator_version>)
  Quay Route:      <quay_route>
  FBC Image:       <fbc_image>
  Channel:         <channel>
  Frontend:        VALIDATED (login, dashboard, smoke tests)
  Feature Test:    <feature_summary or "not requested">
  Bugs Found:      <count or "none">
  Artifacts:       /tmp/quay-validate/ (videos + screenshots)
  Ticks:           <tick_count>
═══════════════════════════════════════════════════════════
  NOTE: Cluster auto-expires in ~4 hours.
  Run: export KUBECONFIG=<kubeconfig_path>
═══════════════════════════════════════════════════════════
```

Exit the loop. The deployment is done.

---

## Error Handling

If any script subcommand exits non-zero:

1. Do NOT advance to the next state
2. Inspect the error output
3. Increment `retry_count`:
   ```bash
   RETRIES=$(bash .claude/scripts/deploy-state.sh read $DEPLOY_ID | jq '.retry_count')
   bash .claude/scripts/deploy-state.sh set $DEPLOY_ID retry_count $((RETRIES + 1))
   ```
4. If `retry_count < 3`: retry the current state
5. If `retry_count >= 3`: stop and use `AskUserQuestion` to present the error

---

## Manual Mode

When `mode` is `"manual"` in the state file, pause after each tick and ask:

```
───────────────────────────────────────
  Tick #N: CURRENT_STATE → NEXT_STATE
  Completed: <brief summary of what was done>
  Next: <what the next state will do>
───────────────────────────────────────
  [c] Continue    [s] Skip to next state
  [i] Inspect     [a] Abort
```

Use `AskUserQuestion` to present this prompt. On `[a]bort`, stop the loop
immediately. On `[s]kip`, advance without executing. On `[i]nspect`, show the
full state file and re-prompt.

## Artifact Directory

All screenshots and video recordings are saved to `/tmp/quay-validate/`.
Create this directory at the start of VALIDATE_UI:

```bash
mkdir -p /tmp/quay-validate
```

Videos of bugs are the primary deliverable for human review.
