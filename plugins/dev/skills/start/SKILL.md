---
name: start
description: >
  Begin work on a JIRA ticket. Assigns the ticket, creates a feature branch,
  checks if backporting is needed, and loads the relevant agent_docs/ for the
  ticket's area.
argument-hint: PROJQUAY-XXXX
allowed-tools:
  - Bash(bash .claude/scripts/session-setup.sh)
  - Bash(bash .claude/scripts/jira-ops.sh *)
  - Bash(git checkout *)
  - Bash(git pull *)
  - Read
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
---

# Start Work on JIRA Ticket

Begin work on JIRA ticket `$ARGUMENTS`.

## Step 0: Session Bootstrap

```bash
bash .claude/scripts/session-setup.sh
```

Handles acli install+auth, recommended hooks, pre-commit, and gh auth check. Runs once per session (skips on subsequent calls).

## Step 1: View and Assign

```bash
bash .claude/scripts/jira-ops.sh view $ARGUMENTS
```

Review the ticket summary, status, and description. Then assign and transition:

```bash
bash .claude/scripts/jira-ops.sh assign $ARGUMENTS
bash .claude/scripts/jira-ops.sh transition $ARGUMENTS "ASSIGNED"
```

## Step 2: Check Backport Requirement

```bash
bash .claude/scripts/jira-ops.sh check-version $ARGUMENTS
```

If Target Version is set, note that **backporting will be required** after merge.

## Step 3: Create Branch

```bash
DEFAULT_BRANCH="${PRIMARY_BRANCH:-$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|origin/||')}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-master}"
git checkout "$DEFAULT_BRANCH" && git pull origin "$DEFAULT_BRANCH"
git checkout -b $ARGUMENTS-short-description
```

Branch naming: `<TICKET-KEY>-<kebab-case-description>`. Derive the description from the ticket summary. Ask the user if it's ambiguous.

## Step 4: Load Context

Based on the ticket's area, read the relevant docs. The doc mapping is project-specific — check the project's `AGENTS.md` for the area-to-doc table.

Common patterns:
| Area | Doc |
|------|-----|
| API endpoints, auth | `agent_docs/api.md` |
| Database, migrations | `agent_docs/database.md` |
| Testing | `agent_docs/testing.md` |
| Architecture | `agent_docs/architecture.md` |
| Frontend | `web/AGENTS.md` or equivalent |

## Step 5: Report

Summarize:
- Ticket: key, summary, status, assignee
- Backport: required or not
- Branch: name created
- Docs loaded
- Next step: `/code`
