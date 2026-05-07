---
name: speedrun
description: >
  Run remaining bugfix phases without stopping between them. Detects
  existing artifacts to resume mid-workflow. Honors escalation rules.
allowed-tools:
  - Bash(bash .claude/scripts/session-setup.sh)
  - Bash(bash .claude/scripts/jira-ops.sh *)
  - Bash(bash .claude/scripts/tick-state.sh *)
  - Bash(bash .claude/scripts/format-and-lint.sh *)
  - Bash(bash .claude/scripts/poll-pr.sh *)
  - Bash(bash .claude/scripts/validate-pr-title.sh *)
  - Bash(bash .claude/scripts/validate-commit-msg.sh *)
  - Bash(bash .claude/scripts/check-ci.sh *)
  - Bash(git *)
  - Bash(gh *)
  - Bash(make *)
  - Bash(pytest *)
  - Bash(python *)
  - Bash(pre-commit *)
  - Bash(alembic *)
  - Bash(npm *)
  - Bash(npx *)
  - Bash(docker *)
  - Bash(podman *)
  - Bash(curl *)
  - Bash(cat *)
  - Bash(echo *)
  - Bash(find *)
  - Bash(ls *)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
  - TodoWrite
  - CronCreate
  - CronDelete
  - CronList
---

# Speedrun — Run Remaining Workflow

You are in **speedrun mode**. Run the next incomplete phase, then continue to
the next one. Do not use the controller skill.

## User Input

```text
$ARGUMENTS
```

Consider the user input before proceeding. It may contain a bug report, issue
URL, context about where they are in the workflow, or instructions about which
phases to include or skip.

## How Speedrun Works

1. Determine which phase to run next (see "Determine Next Phase" below)
2. If all phases are done (including summary), stop
3. Otherwise, run the skill for that phase
4. When the skill completes, continue to the next phase

## Determine Next Phase

Check which phases are already done by looking for artifacts, then pick the
first phase that is NOT done.

### Phase Order and Completion Signals

| Phase | Skill | "Done" signal |
|-------|-------|---------------|
| assess | `assess` | `artifacts/quay-bugfix/reports/assessment.md` exists |
| reproduce | `reproduce` | `artifacts/quay-bugfix/reports/reproduction.md` exists |
| diagnose | `diagnose` | `artifacts/quay-bugfix/analysis/root-cause.md` exists |
| fix | `fix` | `artifacts/quay-bugfix/fixes/implementation-notes.md` exists |
| test | `test` | `artifacts/quay-bugfix/tests/verification.md` exists |
| review | `review` | `artifacts/quay-bugfix/review/verdict.md` exists |
| document | `document` | `artifacts/quay-bugfix/docs/pr-description.md` exists |
| pr | `pr` | A PR URL has been shared in conversation |
| summary | `summary` | `artifacts/quay-bugfix/summary.md` exists |

### Rules

- Check artifacts in order. The first phase whose signal is NOT satisfied is next.
- If no artifacts exist, start at **assess**.
- If the user specifies a starting point in `$ARGUMENTS`, respect that.
- If conversation context clearly establishes a phase was completed (even
  without an artifact), skip it.

## Execute a Phase

1. **Announce** the phase (e.g., "Starting the fix phase — speedrun mode.")
2. **Run** the skill for the current phase
3. When the skill completes, continue to the next phase

## Speedrun Rules

- **Do not stop and wait between phases.** After each phase completes,
  continue to the next one.
- **Do not use the controller skill.** This skill replaces the controller.
- **DO still follow CLAUDE.md escalation rules.** If a phase hits an
  escalation condition (confidence below 80%, unclear root cause, multiple
  valid solutions with unclear trade-offs, security concern), stop and ask
  the user. After the user responds, continue.

## Phase-Specific Notes

### assess

- If no bug report or issue URL exists, ask the user once, then proceed.
- Present the assessment inline but do not wait for confirmation.

### reproduce

- If reproduction fails, note the failure and continue to diagnose anyway.

### diagnose

- If multiple root causes are plausible and you cannot determine which is
  correct, this is an escalation point — stop and ask.

### fix

- Create a feature branch if one doesn't exist yet.
- Transition JIRA ticket to POST after committing.

### test

- Run the full test suite. If tests fail, attempt to fix before continuing.

### review

- **Verdict "solid"** — continue to document.
- **Verdict "tests incomplete"** — attempt to add missing tests, then continue.
- **Verdict "inadequate"** — perform **one** revision cycle: go back to fix ->
  test -> review. If the second review still says "inadequate," stop and
  report to the user.

### pr

- Follow the PR skill's full process.
- If PR creation fails after exhausting fallbacks, report and stop.

### summary

- Always run as the final phase.
- Speedrun still MUST honor any `AskUserQuestion` hard gates from earlier
  phases (e.g., the existing-PR decision in assess).

## Completion Report (Early Stop Only)

If you stop early due to escalation:

```markdown
## Speedrun Complete

### Phases Run
- [each phase and key outcome]

### Artifacts Created
- [all artifacts with paths]

### Result
- [PR URL, or reason for stopping early]

### Notes
- [escalations, skipped phases, or items needing follow-up]
```
