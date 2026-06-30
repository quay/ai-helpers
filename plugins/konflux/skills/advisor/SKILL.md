---
name: konflux-advisor
description: >
  Use when user asks about Konflux concepts, resources, pipelines, builds,
  releases, integration testing, Enterprise Contract, or troubleshooting
  Konflux issues. Triggers on any Konflux-related question or problem.
allowed-tools:
  - Bash(nlm notebook query *)
  - Bash(nlm notebook list --json)
  - Bash(which nlm)
  - Bash(nlm --version)
  - mcp__obsidian__obsidian_search
  - mcp__obsidian__obsidian_read
  - Read
---

# Konflux Advisor

Consult the user's NotebookLM knowledgebase before answering Konflux questions. Do NOT rely on web search or training data alone — the nlm notebooks contain curated, authoritative Konflux documentation.

## Prerequisites

Before querying notebooks, verify `nlm` is available:

```bash
which nlm
```

If `nlm` is not found, stop and tell the user:

> The `nlm` CLI is required but not installed. Install it with:
>
> ```
> pipx install nlm
> nlm login
> ```
>
> After installing, run `nlm login` to authenticate with your Google account, then re-run this skill.

Do NOT proceed with notebook queries if `nlm` is missing — the skill cannot function without it.

### Notebook Access

After confirming `nlm` is installed, verify the required notebooks are accessible:

```bash
nlm notebook list --json
```

Check the JSON output for both notebook IDs:
- `6916b269-d239-48af-870e-01c90da5345d` — Konflux User Advisor
- `4af834bc-eeca-4ad3-95d0-aaff040085ba` — Quay Konflux Processes

If either notebook is missing from the list, tell the user which one(s) they need and how to get access:

> You're missing the following NotebookLM notebook(s):
>
> | Notebook | Link |
> |----------|------|
> | Konflux User Advisor | https://notebooklm.google.com/notebook/6916b269-d239-48af-870e-01c90da5345d |
> | Quay Konflux Processes | https://notebooklm.google.com/notebook/4af834bc-eeca-4ad3-95d0-aaff040085ba |
>
> Open the link(s) above in your browser — this adds the notebook to your Google account. Then run `nlm notebook list` to confirm it appears.

If only one notebook is missing, still proceed with the other one and note the gap in your response.

## Sources (Priority Order)

### 1. Konflux User Advisor (nlm) — Always Query First

```bash
nlm notebook query 6916b269-d239-48af-870e-01c90da5345d "<question>"
```

54 curated upstream Konflux sources: CRD specs, user guides, integration testing, Enterprise Contract, release processes, pipelines, and more.

**This is the primary source. Query it before anything else.**

### 2. Quay Konflux Processes (nlm) — Quay-Specific

```bash
nlm notebook query 4af834bc-eeca-4ad3-95d0-aaff040085ba "<question>"
```

11 sources covering Quay-specific Konflux build processes. Query this when the question involves how Quay uses Konflux (builds, components, releases, configuration).

### 3. Obsidian Notes — Fill Gaps

Use Obsidian MCP tools (`obsidian_search`, `obsidian_read`) when nlm answers have gaps about how *we* do things. Key locations:

- `2_Areas/Konflux.md` — main knowledge hub
- `3_Resource/devel/konflux/` — reference docs
- `1_Projects/` — active project notes

## Flow

1. User asks a Konflux question
2. **Check `nlm` is installed** — if missing, show install instructions and stop
3. **Check notebook access** — list notebooks, flag any missing ones with links
4. **Query Konflux User Advisor** via nlm (always, if accessible)
5. If question involves Quay process → **also query Quay Konflux Processes** via nlm
6. If gaps remain about our internal process → **search Obsidian**
7. Synthesize sources into your response

## Common Triggers

- Konflux resources: Application, Component, Snapshot, IntegrationTestScenario, ReleasePlan, ReleasePlanAdmission, EnterpriseContractPolicy
- Build system: Tekton pipelines, PipelineRuns, TaskRuns, hermetic builds, prefetching
- Processes: integration testing, releasing, component nudging, MintMaker/Renovate
- Troubleshooting: pipeline failures, build errors, EC violations
- Configuration: `.tekton/`, PaC (Pipelines as Code), build annotations
