# konflux-build-triage

Automated Konflux build failure triage workflow for the
[Ambient Code Platform](https://ambient.engineering).

## What it does

Checks the build health of all Konflux components by querying the
**latest on-push PipelineRun** for each component via KubeArchive.

For each failing component, it:
1. Consults Konflux skills and a NotebookLM knowledge notebook for diagnosis context
2. Extracts diagnostic context (TaskRun logs, error messages, task results)
3. Classifies the failure (fixable, needs retry, needs human)
4. Spawns a dedicated ACP fix session with full context
5. Deduplicates via ACP session naming to prevent duplicate sessions

Designed to run as a **single-pass pipeline** on an hourly cron schedule.
Each run is a fresh ACP session — no persistent loop.

## Architecture

```text
┌──────────────────────────────────┐
│   konflux-build-triage           │
│   (pipeline agent)               │
│                                  │
│   List existing fix sessions     │
│   (ACP deduplication)            │
│         │                        │
│   check-build-health.sh          │
│   (KubeArchive REST API)         │
│         │                        │
│   Consult knowledge sources      │
│   ├─ Konflux skills (local)      │
│   └─ NotebookLM (MCP)           │
│         │                        │
│   Classify & extract context     │
│         │                        │         ┌─────────────────────────┐
│   Spawn fix session ─────────────┼────────►│  Fix Session            │
│         │                        │         │  (dev plugin)           │
│   Report summary & exit          │         │  diagnose → fix → PR   │
│                                  │         │  → poll CI → retry     │
└──────────────────────────────────┘         └─────────────────────────┘
```

## Data Sources

| Source | Purpose |
|--------|---------|
| KubeArchive REST API | Primary source for build status (`check-build-health.sh`) |
| Live K8s cluster + KubeArchive | TaskRun logs and diagnostics (`extract-failure-context.sh`) |

PipelineRuns and pods are garbage collected from the live cluster within
hours. KubeArchive preserves them and exposes a REST API. The build
health script queries KubeArchive directly via `curl` for the latest
on-push PipelineRun per component.

## Knowledge Sources

The triage agent always consults two sources **before** classifying any failure:

1. **Konflux Skills** (`konflux-ci/skills`) — Claude Code skills providing
   systematic debugging methodology, common failure patterns, and Konflux
   CRD references. Installed via Lola at session start.

2. **NotebookLM** (`notebooklm-mcp-cli`) — MCP server querying a curated
   Konflux knowledge notebook for known issues, runbooks, and historical
   patterns. Auth via `NOTEBOOKLM_COOKIES` env var (degrades gracefully
   if unavailable).

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
| `NOTEBOOKLM_COOKIES` | — | Google auth cookies for NotebookLM (optional) |
| `NOTEBOOKLM_NOTEBOOK_ID` | — | ID of the Konflux knowledge notebook |
| `MAX_TRIAGE_PER_COMPONENT` | `3` | Cap sessions per component |
| `EXCLUDE_APP_REGEX` | — | Regex to exclude applications (e.g. `-dev$`) |

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

### NotebookLM setup

Pre-authenticate on a machine with a browser:
```bash
uv tool install notebooklm-mcp-cli
nlm login
```

Extract the cookie string and set `NOTEBOOKLM_COOKIES` in the session's
environment variables.

> **Note:** Cookies expire every 2-4 weeks. When they expire, the triage
> agent degrades to skills-only mode. Re-run `nlm login` and update the
> env var. A more permanent auth solution is planned.

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/check-build-health.sh` | Check latest on-push build status for all components (via KubeArchive REST API) |
| `scripts/extract-failure-context.sh` | Extract TaskRun logs from a failed PipelineRun (with KubeArchive fallback) |

## Plugin Dependencies

Defined in `.lola-req`:
- `konflux-ci/skills` — Konflux debugging skills
- `quay/ai-helpers/plugins/dev` — Development lifecycle skills (for fix sessions)
