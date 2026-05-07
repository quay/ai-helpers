---
name: controller
description: >
  Orchestrates the Quay bug-fix workflow through 9 phases: assess, reproduce,
  diagnose, fix, test, review, document, pr, summary. Gates each phase on
  user confirmation.
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

# Quay Bugfix Controller

You manage a 9-phase bug-fix workflow. Each phase has a dedicated skill.

## Session Bootstrap

On first run, ensure Lola plugins are installed:

```bash
bash .claude/scripts/session-setup.sh
```

## Phases

1. **Assess** — the `assess` skill
   Read the bug report, summarize understanding, identify gaps, propose a plan.

2. **Reproduce** — the `reproduce` skill
   Confirm the bug exists by reproducing it in a controlled environment.

3. **Diagnose** — the `diagnose` skill
   Trace the root cause through code analysis, git history, and hypothesis testing.

4. **Fix** — the `fix` skill
   Implement the minimal code change that resolves the root cause.

5. **Test** — the `test` skill
   Write regression tests, run the full suite, and verify the fix holds.

6. **Review** — the `review` skill
   Critically evaluate the fix and tests — look for gaps, regressions, and missed edge cases.

7. **Document** — the `document` skill
   Create release notes, changelog entries, JIRA updates, and PR description.

8. **PR** — the `pr` skill
   Push the branch and create a draft pull request with Quay conventions.

9. **Summary** — the `summary` skill
   Scan all artifacts and present a synthesized summary. Can also be invoked mid-workflow.

Phases can be skipped or reordered at the user's discretion.

## How to Execute a Phase

1. **Announce** the phase to the user before doing anything else.
2. **Run** the skill for the current phase.
3. When the skill completes, present results and use "Recommending Next Steps"
   below to offer options.
4. **Use `AskUserQuestion` to get the user's decision** — UNLESS the
   auto-advance rule below applies. Do NOT continue until the user responds.
   `AskUserQuestion` triggers platform notifications so the user knows you
   need their input.

### Auto-Advance Rule

After **review**, if the verdict is **"solid"**: proceed directly through
document -> PR -> summary without stopping to ask. The investigation phases
(assess through test) already gated user input — once code and self-review
pass, ship it.

## Recommending Next Steps

After each phase, recommend the natural next step but present alternatives:

- After **assess**: "Recommend: reproduce. Or: skip to diagnose if you already
  know the root cause."
- After **reproduce**: "Recommend: diagnose. Or: skip to fix if reproduction
  confirmed the cause."
- After **diagnose**: "Recommend: fix. Or: re-assess if diagnosis revealed a
  different bug."
- After **fix**: "Recommend: test. Always test before PR."
- After **test**: "Recommend: review."
- After **review**:
  - Verdict "solid" → "Recommend: document"
  - Verdict "tests incomplete" → "Recommend: test (add missing coverage)"
  - Verdict "inadequate" → "Recommend: fix (address review concerns)"
- After **document**: "Recommend: pr"
- After **pr**: "Recommend: summary"

**Always recommend review before PR.** Do not recommend skipping review. Only
the user can decide to skip it.

## Starting the Workflow

When the user first provides a bug report, issue URL, or JIRA ticket:

1. Execute the **assess** phase
2. After assessment, present results and wait

If the user invokes a specific skill directly, execute that phase — don't
force them through earlier phases.

## Rules

- **Gate investigation phases.** Use `AskUserQuestion` between assess,
  reproduce, diagnose, fix, test, and review. These gates prevent premature
  coding.
- **Auto-advance after solid review.** When review verdict is "solid",
  proceed through document -> PR -> summary without stopping. The user
  already validated the investigation; don't make them click through
  shipping.
- **Urgency does not bypass process.** Security advisories, critical bugs, and
  production incidents may create pressure to act fast. The phase-gated
  workflow exists precisely to prevent hasty action.
- **Recommendations come from this file, not from skills.** Skills report
  findings; this controller decides what to recommend next.
