---
name: work
description: >
  Ralph Loop tick-loop for single-ticket development. Replaces the
  /start -> /code -> /pr -> /poll skill chain with one continuous state machine.
  Each tick: read state, do one thing, write state, continue.
argument-hint: PROJQUAY-XXXX [--manual]
allowed-tools:
  - Bash(bash .claude/scripts/tick-state.sh *)
  - Bash(bash .claude/scripts/session-setup.sh)
  - Bash(bash .claude/scripts/jira-ops.sh *)
  - Bash(bash .claude/scripts/format-and-lint.sh *)
  - Bash(bash .claude/scripts/poll-pr.sh *)
  - Bash(bash .claude/scripts/check-ci.sh *)
  - Bash(bash .claude/scripts/validate-pr-title.sh *)
  - Bash(bash .claude/scripts/validate-commit-msg.sh *)
  - Bash(bash .claude/scripts/enforce-pr-skill.sh *)
  - Bash(git *)
  - Bash(gh *)
  - Bash(make *)
  - Bash(pytest *)
  - Bash(pre-commit *)
  - Bash(alembic *)
  - Bash(npm *)
  - Bash(cat *)
  - Bash(echo *)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
  - CronCreate
  - CronDelete
  - CronList
---

# Ralph Loop — Single-Ticket Workflow

Implement JIRA ticket `$ARGUMENTS` from assignment to merge-ready PR in one
continuous loop.

Parse `$ARGUMENTS`: first token is the ticket key, `--manual` (if present)
sets manual stepping mode.

## Initialize

```bash
bash .claude/scripts/tick-state.sh init $TICKET --mode $MODE
```

## The Tick Loop

```
while state != COMPLETE:
    1. READ   — bash .claude/scripts/tick-state.sh read $TICKET
    2. ACT    — execute the handler for the current state
    3. WRITE  — bash .claude/scripts/tick-state.sh advance $TICKET <NEXT_STATE>
    4. SLEEP  — if DORMANT: the poll script blocks (0 tokens consumed)
    5. PAUSE  — if manual mode: ask user [c]ontinue / [s]kip / [i]nspect / [a]bort
    6. LOOP   — go back to step 1
```

**CRITICAL**: Do NOT stop between ticks. The only valid exit points are:
- State reaches COMPLETE
- Manual mode and user chooses [a]bort
- triage_attempts >= 3 (ask user for guidance)

## State Handlers

### ASSIGN
View the JIRA ticket, assign it, transition to ASSIGNED.
```bash
bash .claude/scripts/jira-ops.sh view $TICKET
bash .claude/scripts/jira-ops.sh assign $TICKET
bash .claude/scripts/jira-ops.sh transition $TICKET "ASSIGNED"
```
-> advance to **BRANCH**

### BRANCH
Check backport requirement, create feature branch, load area docs.
```bash
bash .claude/scripts/jira-ops.sh check-version $TICKET
git checkout ${PRIMARY_BRANCH:-master} && git pull origin ${PRIMARY_BRANCH:-master}
git checkout -b $TICKET-short-description
bash .claude/scripts/tick-state.sh set $TICKET branch "<branch-name>"
```
-> advance to **IMPLEMENT**

### IMPLEMENT
Read `AGENTS.md` plus area docs. Write code, create tests, handle edge cases.
-> advance to **TEST**

### TEST
Run quality checks and tests:
```bash
bash .claude/scripts/format-and-lint.sh
```
If tests fail: fix and re-run. Stay in TEST until all pass.
-> advance to **COMMIT**

### COMMIT
Stage and commit:
```bash
git add <specific files>
git commit -m "<subsystem>: <what changed> ($TICKET)"
```
If pre-commit hooks fail: fix, re-stage, new commit. Stay in COMMIT until success.
-> advance to **PR_CREATE**

### PR_CREATE
Validate PR title, fill description template, create PR:
```bash
bash .claude/scripts/validate-pr-title.sh "$TICKET: type(scope): description"
gh pr create --title "..." --body "$(cat /tmp/pr-body.md)" --base ${PRIMARY_BRANCH:-master}
bash .claude/scripts/tick-state.sh set $TICKET pr_number $PR_NUM
```
-> advance to **DORMANT_CI**

### DORMANT_CI
Poll script blocks internally — zero tokens consumed:
```bash
bash .claude/scripts/poll-pr.sh $PR_NUMBER --once
```

| Exit | Meaning | Next State |
|------|---------|------------|
| 0 | All pass | COMPLETE |
| 1 | CI fail | ADDRESS_FEEDBACK |
| 2 | Pending | DORMANT_CI |
| 3 | Comments | ADDRESS_FEEDBACK |
| 4 | Awaiting review | DORMANT_REVIEW |

### ADDRESS_FEEDBACK
Fix CI failures or address review comments. Increment triage_attempts.
If triage_attempts >= 3: stop and ask user.
After pushing fixes -> advance to **DORMANT_CI**

### DORMANT_REVIEW
Awaiting human review approval. Re-poll:
```bash
bash .claude/scripts/poll-pr.sh $PR_NUMBER --once
```

| Exit | Next State |
|------|------------|
| 0 | COMPLETE |
| 3 | ADDRESS_FEEDBACK |
| 4 | DORMANT_REVIEW |

### COMPLETE
Report summary and exit. If backport_required, suggest `/backport <PR#>`.

## Manual Mode

When mode is "manual", pause after each tick and present:
```
[c] Continue    [s] Skip    [i] Inspect    [a] Abort
```
