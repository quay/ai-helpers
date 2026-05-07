# konflux-build-triage

Automated Konflux build failure triage workflow for the
[Ambient Code Platform](https://ambient.engineering).

## What it does

Continuously monitors the Konflux cluster for:
- Failed post-merge (push) build PipelineRuns
- Failed Enterprise Contract (EC) integration test PipelineRuns

For each new failure, it:
1. Consults Konflux skills and a NotebookLM knowledge notebook for diagnosis context
2. Extracts diagnostic context (TaskRun logs, error messages, task results)
3. Classifies the failure (fixable, needs retry, needs human)
4. Spawns a dedicated ACP fix session with full context
5. Tracks triaged failures to prevent duplicate sessions

## Architecture

```
┌──────────────────────────────────┐
│   konflux-build-triage           │
│   (supervisor agent)             │
│                                  │
│   Query K8s API                  │
│         │                        │
│   Deduplicate (state file)       │
│         │                        │
│   Consult knowledge sources      │
│   ├─ Konflux skills (local)      │
│   └─ NotebookLM (MCP)           │
│         │                        │
│   Classify & extract context     │
│         │                        │         ┌─────────────────────────┐
│   Spawn fix session ─────────────┼────────►│  Fix Session            │
│         │                        │         │  (dev plugin)           │
│   Record & sleep 20 min          │         │  diagnose → fix → PR   │
│         │                        │         │  → poll CI → retry     │
│   Loop ◄─┘                       │         └─────────────────────────┘
└──────────────────────────────────┘
```

## Knowledge Sources

The triage agent always consults two sources **before** classifying any failure:

1. **Konflux Skills** (`konflux-ci/skills`) — Claude Code skills providing
   systematic debugging methodology, common failure patterns, and Konflux
   CRD references. Installed via Lola at session start.

2. **NotebookLM** (`notebooklm-mcp-cli`) — MCP server querying a curated
   Konflux knowledge notebook for known issues, runbooks, and historical
   patterns. Auth via `NOTEBOOKLM_COOKIES` env var (degrades gracefully
   if unavailable).

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `KONFLUX_NAMESPACE` | `quay-eng-tenant` | K8s namespace |
| `KONFLUX_KUBECONFIG_DATA` | — | Base64-encoded kubeconfig |
| `NOTEBOOKLM_COOKIES` | — | Google auth cookies for NotebookLM (optional) |
| `NOTEBOOKLM_NOTEBOOK_ID` | — | ID of the Konflux knowledge notebook |
| `POLL_INTERVAL_SECONDS` | `1200` | Check interval (seconds) |
| `FAILURE_LOOKBACK_HOURS` | `24` | Query window (hours) |
| `MAX_TRIAGE_PER_COMPONENT` | `3` | Cap sessions per component |

## Usage

### Create an ACP session

```python
acp_create_session(
  session_name="build-triage-20260506",
  display_name="Konflux Build Triage",
  workflow_git_url="https://github.com/quay/ai-helpers.git",
  workflow_branch="main",
  workflow_path="workflows/konflux-build-triage"
)
```

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
| `scripts/query-failed-pipelines.sh` | Query K8s for failed push builds + EC tests |
| `scripts/extract-failure-context.sh` | Extract TaskRun logs from a failed PipelineRun |
| `scripts/discover-components.sh` | Auto-discover component → repo mapping from CRD |
| `scripts/triage-state.sh` | Deduplication state management |

## Plugin Dependencies

Defined in `.lola-req`:
- `konflux-ci/skills` — Konflux debugging skills
- `quay/ai-helpers/plugins/dev` — Development lifecycle skills (for fix sessions)
