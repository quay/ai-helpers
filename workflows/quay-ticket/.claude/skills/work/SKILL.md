---
name: work
description: >
  Ralph Loop tick-loop for single-ticket Quay development. Replaces the
  /start → /code → /pr → /poll skill chain with one continuous state machine.
  Each tick: read state, do one thing, write state, continue.
argument-hint: PROJQUAY-XXXX [--manual]
allowed-tools:
  - Bash(bash .claude/scripts/tick-state.sh *)
  - Bash(bash .claude/scripts/jira-ops.sh *)
  - Bash(bash .claude/scripts/format-and-lint.sh *)
  - Bash(bash .claude/scripts/validate-pr-title.sh *)
  - Bash(bash .claude/scripts/poll-pr.sh *)
  - Bash(bash .claude/scripts/session-setup.sh)
  - Bash(git *)
  - Bash(gh *)
  - Bash(make *)
  - Bash(pytest *)
  - Bash(pre-commit *)
  - Bash(alembic *)
  - Bash(npm *)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
---

# /work — Ralph Loop Tick-Loop

Implement JIRA ticket `$ARGUMENTS` from assignment to merge-ready PR in one
continuous loop. No separate skills, no chaining — one state machine that
advances mechanically.

---

## Execution Model

Parse `$ARGUMENTS`: the first token is the ticket key, `--manual` (if present)
sets manual stepping mode.

```
TICKET = first token of $ARGUMENTS
MODE = "manual" if --manual present, else "auto"
```

### Initialize or Resume

```bash
bash .claude/scripts/session-setup.sh
bash .claude/scripts/tick-state.sh init $TICKET --mode $MODE
```

If state already exists, this prints the current state and resumes from there.

### The Tick Loop

```
while state != COMPLETE:
    1. READ   — bash .claude/scripts/tick-state.sh read $TICKET
    2. ACT    — execute the handler for the current state (below)
    3. WRITE  — bash .claude/scripts/tick-state.sh advance $TICKET <NEXT_STATE>
    4. SLEEP  — if DORMANT: the poll script blocks (0 tokens consumed)
    5. PAUSE  — if manual mode: ask user [c]ontinue / [s]kip / [i]nspect / [a]bort
    6. LOOP   — go back to step 1
```

**CRITICAL**: Do NOT stop between ticks. The loop is continuous. The only valid
exit points are:
- State reaches `COMPLETE`
- Manual mode and user chooses `[a]bort`
- `triage_attempts >= 3` (ask user for guidance)

---

## State Handlers

### ASSIGN

View the JIRA ticket, assign it to yourself, and transition to ASSIGNED.

```bash
bash .claude/scripts/jira-ops.sh view $TICKET
bash .claude/scripts/jira-ops.sh assign $TICKET
bash .claude/scripts/jira-ops.sh transition $TICKET "ASSIGNED"
```

Review the ticket summary and description to understand the scope.

→ advance to **BRANCH**

---

### BRANCH

Check if backporting is needed, create a feature branch, and load area docs.

```bash
bash .claude/scripts/jira-ops.sh check-version $TICKET
```

If Target Version is set, record it:
```bash
bash .claude/scripts/tick-state.sh set $TICKET backport_required true
```

Create the branch:
```bash
git checkout master && git pull origin master
git checkout -b $TICKET-short-description
```

Derive the branch name from the ticket summary (kebab-case). Record it:
```bash
bash .claude/scripts/tick-state.sh set $TICKET branch "<branch-name>"
```

Based on the ticket's area, read the relevant docs:

| Area | Doc |
|------|-----|
| API endpoints, auth | `agent_docs/api.md` |
| Database, migrations | `agent_docs/database.md` |
| Testing | `agent_docs/testing.md` |
| Architecture | `agent_docs/architecture.md` |
| React frontend | `web/AGENTS.md` |

Record which docs were loaded:
```bash
bash .claude/scripts/tick-state.sh set $TICKET area_docs '["agent_docs/api.md"]'
```

→ advance to **IMPLEMENT**

---

### IMPLEMENT

Read `AGENTS.md` for universal conventions, plus the area docs loaded in BRANCH.

Implement the changes following Quay conventions:
- Exception types from `endpoints/exception.py`
- Existing import ordering patterns
- Never hand-write migration files — use `alembic revision -m "description"`
- No secrets in code

This is the main implementation state. Write code, create tests, handle edge cases.

→ advance to **TEST**

---

### TEST

Run quality checks:

```bash
bash .claude/scripts/format-and-lint.sh            # pre-commit on staged files
```

Run relevant tests:

```bash
TEST=true PYTHONPATH="." pytest path/to/test.py -v  # specific tests
make unit-test                                       # all unit tests
make types-test                                      # mypy
```

**If tests fail**: fix the code and re-run. Stay in TEST until all checks pass.
Do NOT go back to IMPLEMENT — fix in-place.

→ advance to **COMMIT** when all pass

---

### COMMIT

Stage and commit with the proper message format:

```bash
git add <specific files>
git commit -m "<subsystem>: <what changed> ($TICKET)

<why this change was made>"
```

Pre-commit hooks run automatically on commit. If they fail: fix, re-stage, create
a new commit. Stay in COMMIT until the commit succeeds.

→ advance to **PR_CREATE**

---

### PR_CREATE

Validate the PR title against the CI-enforced regex:

```bash
bash .claude/scripts/validate-pr-title.sh "$TICKET: type(scope): description"
```

Title format: `PROJQUAY-XXXX: type(scope): description` (type is lowercase).

Read the description template at `.claude/templates/pr-description.md` and fill it in.
Write the filled template to `/tmp/pr-body.md`.

Check for ambient session:
```bash
echo $AGENTIC_SESSION_NAME
```

Create the PR:
```bash
gh pr create \
  --title "$TICKET: type(scope): description" \
  --body "$(cat /tmp/pr-body.md)" \
  --base master
```

Add `--label "ambient-session"` if `AGENTIC_SESSION_NAME` is set.

Record the PR number:
```bash
PR_NUM=$(gh pr view --json number --jq '.number')
bash .claude/scripts/tick-state.sh set $TICKET pr_number $PR_NUM
```

→ advance to **DORMANT_CI**

---

### DORMANT_CI

**This is a yield point.** The poll script blocks internally — zero tokens consumed.

```bash
PR_NUMBER=$(bash .claude/scripts/tick-state.sh read $TICKET | jq -r '.pr_number')
bash .claude/scripts/poll-pr.sh $PR_NUMBER --once
```

Read the exit code and route:

| Exit Code | Meaning | Next State |
|-----------|---------|------------|
| 0 | All checks pass | **COMPLETE** |
| 1 | CI failures | **ADDRESS_FEEDBACK** |
| 2 | Checks pending | **DORMANT_CI** (re-poll) |
| 3 | Review comments | **ADDRESS_FEEDBACK** |
| 4 | Awaiting human review | **DORMANT_REVIEW** |

Record the exit code:
```bash
bash .claude/scripts/tick-state.sh set $TICKET last_poll_exit $EXIT_CODE
```

→ advance based on exit code

---

### ADDRESS_FEEDBACK

Read the last poll exit code to determine what kind of feedback to address.

Restore the PR number from state:
```bash
PR_NUMBER=$(bash .claude/scripts/tick-state.sh read $TICKET | jq -r '.pr_number')
```

**Exit 1 — CI failures:**
- Run `bash .claude/scripts/poll-pr.sh $PR_NUMBER --once --full` to see which jobs failed
- Fix the failing code
- Run tests locally to verify
- Commit and push

**Exit 3 — Review comments:**
- Run `bash .claude/scripts/poll-pr.sh $PR_NUMBER --once --full` to see inline comments
  with reply and resolve commands
- For each comment, evaluate critically:
  - **Valid**: fix the code, reply explaining what you changed, resolve the thread
  - **Invalid**: reply with your reasoning, resolve the thread
  - **Unclear**: reply asking for clarification (do NOT resolve)
- Commit fixes and push

**Triage guard:**
```bash
# Increment triage_attempts
ATTEMPTS=$(bash .claude/scripts/tick-state.sh read $TICKET | jq '.triage_attempts')
bash .claude/scripts/tick-state.sh set $TICKET triage_attempts $((ATTEMPTS + 1))
```

If `triage_attempts >= 3`: stop the loop and ask the user for guidance. The same
class of failure keeps recurring — a human needs to look.

After pushing fixes:
→ advance to **DORMANT_CI** (re-poll to verify the fix)

---

### DORMANT_REVIEW

**This is a yield point.** The PR is awaiting human review approval.

```bash
PR_NUMBER=$(bash .claude/scripts/tick-state.sh read $TICKET | jq -r '.pr_number')
bash .claude/scripts/poll-pr.sh $PR_NUMBER --once
```

| Exit Code | Next State |
|-----------|------------|
| 0 | **COMPLETE** |
| 3 | **ADDRESS_FEEDBACK** (new comments) |
| 4 | **DORMANT_REVIEW** (still waiting — re-poll) |

→ advance based on exit code

---

### COMPLETE

The PR is merge-ready. Report the summary:

```
═══════════════════════════════════════════════════════════
  COMPLETE — $TICKET
═══════════════════════════════════════════════════════════
  Branch:    <branch>
  PR:        #<number>
  CI:        all passing
  Review:    approved
  Ticks:     <tick_count>
  Duration:  <created_at → now>
═══════════════════════════════════════════════════════════
```

If `backport_required` is true, suggest running `/backport <PR#>`.

Exit the loop. The task is done.

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

Manual mode is the Ralph Loop's "watch the loop" principle — start manual to
understand behavior, then switch to auto for full autonomy.
