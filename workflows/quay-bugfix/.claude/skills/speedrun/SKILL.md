---
name: speedrun
description: >
  Legacy alias — speedrun is now the default behavior via confidence-based
  gating in the controller. Invoking this skill delegates to the controller.
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

# Speedrun

Speedrun is now the default behavior. The controller uses confidence-based
gating to advance automatically between phases — there is no separate
speedrun mode.

**Invoke the controller skill to start the workflow.**

The controller will:
- Advance automatically when phase confidence is high (>=90%)
- Post a JIRA comment and advance when confidence is medium (70-89%)
- Stop and escalate when confidence is low (<70%)

## Phase Completion Signals (Reference)

| Phase | Skill | "Done" signal |
|-------|-------|---------------|
| assess | assess | artifacts/quay-bugfix/reports/assessment.md exists |
| reproduce | reproduce | artifacts/quay-bugfix/reports/reproduction.md exists |
| diagnose | diagnose | artifacts/quay-bugfix/analysis/root-cause.md exists |
| fix | /dev:code | artifacts/quay-bugfix/fixes/implementation-notes.md exists |
| test | test | artifacts/quay-bugfix/tests/verification.md exists |
| review | review | artifacts/quay-bugfix/review/verdict.md exists |
| document | document | artifacts/quay-bugfix/docs/pr-description.md exists |
| pr | /dev:pr + /dev:poll | artifacts/quay-bugfix/pr/url.txt exists |
| summary | summary | artifacts/quay-bugfix/summary.md exists |
