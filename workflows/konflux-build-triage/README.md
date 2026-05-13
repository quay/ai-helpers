# konflux-build-triage

Automated Konflux build failure triage dispatcher for the
[Ambient Code Platform](https://ambient.engineering).

## What it does

Checks the build health of Konflux components for **currently supported
Quay versions** by querying the **latest on-push PipelineRun** for each
component via KubeArchive.

Supported versions are determined at runtime by querying the
[Red Hat Quay lifecycle API](https://access.redhat.com/support/policy/updates/rhquay).
Versions marked as "End of life" are automatically excluded.

For each failing component, it:
1. Filters to supported Quay versions only
2. Deduplicates against existing ACP fix sessions
3. Checks the per-component triage cap
4. Presents failures and **waits for user confirmation**
5. Spawns a dedicated [konflux-build-debugger](../konflux-build-debugger/)
   session only for user-approved failures

Designed to run as a **single-pass dispatcher** on an hourly cron.
Each run is a fresh ACP session — no persistent loop.

## Architecture

```text
┌───────────────────────────────────┐
│   konflux-build-triage            │
│   (ephemeral dispatcher)          │
│                                   │
│   List existing fix sessions      │
│   (ACP deduplication)             │
│         │                         │
│   get-supported-versions.sh       │
│   (Red Hat lifecycle API)         │
│         │                         │
│   check-build-health.sh           │
│   --supported-only --failed-only  │
│   (KubeArchive REST API)          │
│         │                         │
│   For each new failure:           │
│   dedup → cap check → present     │
│         │                         │
│   Wait for user confirmation      │
│         │                         │
│   Spawn approved failures     ────┼───►  konflux-build-debugger
│         │                         │      (tick-loop agent)
│   Report summary & stop           │      diagnose → fix → PR
│                                   │      → poll CI → retry
└───────────────────────────────────┘
```

## Deduplication

Cross-run deduplication uses the **ACP platform as the source of truth**.
Fix session names are deterministic (`fix-<component>-<8-char-hash>`),
so checking `acp_list_sessions` reveals whether a failure was already
triaged in a previous run. No external state file is needed.

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `KONFLUX_NAMESPACE` | `quay-eng-tenant` | K8s namespace |
| `KONFLUX_KUBECONFIG_DATA` | — | Base64-encoded kubeconfig |
| `MAX_TRIAGE_PER_COMPONENT` | `3` | Cap sessions per component |
| `EXCLUDE_APP_REGEX` | `-dev$` | Regex to exclude applications (e.g. `-dev$`) |

## Usage

### Create an ACP session (one-off or cron)

```python
acp_create_session(
  session_name="build-triage-20260506",
  display_name="Konflux Build Triage",
  workflow_git_url="https://github.com/quay/ai-helpers.git",
  workflow_branch="main",
  workflow_path="workflows/konflux-build-triage"
)
```

For recurring triage, schedule this as an hourly cron on the ACP platform.

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/check-build-health.sh` | Check latest on-push build status for all components (via KubeArchive REST API) |
| `scripts/get-supported-versions.sh` | Query Red Hat product lifecycle API for currently supported Quay versions |

## Plugin Dependencies

Defined in `.lola-req`:
- `konflux-ci/skills` — Konflux debugging skills (used by spawned debugger sessions)
