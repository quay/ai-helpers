---
name: jira
description: >
  View or update a JIRA ticket. Supports view, assign, transition,
  check-version, and set-version operations via REST API or acli.
argument-hint: PROJQUAY-XXXX [action]
allowed-tools:
  - Bash(bash .claude/scripts/jira-ops.sh *)
  - Read
  - Grep
  - AskUserQuestion
---

# JIRA Ticket Operations

Manage JIRA ticket `$ARGUMENTS[0]`.

- **Issue key**: `$ARGUMENTS[0]`
- **Action** (optional): `$ARGUMENTS[1]` — defaults to `view`

## Operations

### View (default)

```bash
bash .claude/scripts/jira-ops.sh view "$ARGUMENTS[0]"
```

### Assign

```bash
bash .claude/scripts/jira-ops.sh assign "$ARGUMENTS[0]"
```

Assigns to current user (requires `acli` or accountId).

### Transition

```bash
bash .claude/scripts/jira-ops.sh transition "$ARGUMENTS[0]" "$ARGUMENTS[2]"
```

Valid statuses: `New`, `ASSIGNED`, `POST`, `ON_QA`, `Verified`, `Release Pending`, `Closed`, `MODIFIED`

### Check Target Version

```bash
bash .claude/scripts/jira-ops.sh check-version "$ARGUMENTS[0]"
```

Reports whether backporting is required.

### Set Target Version

```bash
bash .claude/scripts/jira-ops.sh set-version "$ARGUMENTS[0]" "$ARGUMENTS[2]"
```

## Configuration

Set via environment variables:
- `JIRA_DOMAIN` — JIRA instance (default: redhat.atlassian.net)
- `JIRA_DEFAULT_EMAIL` — fallback email for auth
- `JIRA_TARGET_VERSION_FIELD` — custom field ID for Target Version
