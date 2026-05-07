---
name: diagnose
description: >
  Root cause analysis for a Quay bug. Traces code paths through Quay
  subsystems, analyzes git history, forms and tests hypotheses, and
  enumerates complete state space.
allowed-tools:
  - Bash(git log *)
  - Bash(git blame *)
  - Bash(git show *)
  - Bash(gh pr view *)
  - Read
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
---

# Diagnose Root Cause

Determine why the bug exists. This is the most critical phase — a wrong
diagnosis leads to a wrong fix.

## Your Role

Perform thorough root cause analysis that provides clear, evidence-based
conclusions. Identify the underlying issue, not just the symptom.

## Process

### Step 1: Review Reproduction

Read the reproduction report (`artifacts/quay-bugfix/reports/reproduction.md`
if it exists):

- Understand the exact conditions that trigger the bug
- Note any patterns or edge cases discovered
- Identify the entry point for investigation

### Step 2: Trace the Code Path

Starting from the reproduction steps, trace the execution flow through
Quay's subsystems. Use the subsystem map from CLAUDE.md:

**For API bugs:**
Entry point in `endpoints/` -> business logic in `data/model/` -> database
operations in `data/database.py` -> query execution

**For worker bugs:**
Worker class in `workers/` -> queue operations -> data layer -> database

**For UI bugs:**
React component in `web/src/` -> API hook in `web/src/hooks/` -> REST
endpoint in `endpoints/`

**For auth bugs:**
Auth middleware in `auth/` -> permission checks -> data layer

**For storage bugs:**
Storage backend in `storage/` -> blob operations -> configuration

Use `file:line` notation for every code reference (e.g.,
`endpoints/api/repository.py:245`).

### Step 3: Historical Analysis

```bash
git log --oneline -20 -- <affected-files>
git blame <file> -L <start>,<end>
```

Look for: recent changes that introduced the bug, related PRs, patterns of
similar fixes.

### Step 4: Hypothesis Formation

List all potential root causes based on evidence:

- Rank hypotheses by likelihood (high/medium/low confidence)
- Consider: logic errors, race conditions, edge cases, missing validation,
  incorrect state transitions, ORM query issues
- Document reasoning for each hypothesis

### Step 5: Hypothesis Testing

- Add targeted logging or debugging to test hypotheses
- Create minimal test cases to validate or disprove each hypothesis
- Use binary search (`git bisect`) if the change was introduced gradually
- Narrow down to the definitive root cause

### Step 6: State Enumeration

**CRITICAL:** If the bug involves state-dependent logic (status fields,
phase transitions, feature flags, configuration options):

- Search the codebase for the complete list of possible values
- Don't assume you know all states — verify by searching
- Document feature interactions that affect the bug

Example: If a worker stops processing on "terminal" statuses, search for
ALL statuses used in the codebase, not just the ones in the bug report.

### Step 7: Impact Assessment

- What other code paths are affected by the same root cause?
- Could the fix cause regressions in related functionality?
- Are there similar patterns elsewhere that have the same bug?
- Does this affect database migrations or schema?

### Step 8: Solution Approach

- Recommend fix strategy based on root cause
- Consider multiple approaches and their trade-offs
- Document why the recommended approach is best

## Output

Save to `artifacts/quay-bugfix/analysis/root-cause.md`:

```markdown
# Root Cause Analysis: <TICKET>

## Root Cause
<Clear, specific explanation of why the bug exists>

## Code References
- `file:line` — <what this code does wrong>
- ...

## Evidence
- <supporting evidence from code, git history, reproduction>

## Timeline
<When the bug was introduced — commit/PR reference>

## Impact
- **Scope:** <what else is affected>
- **Risk:** <could the fix cause regressions>
- **Related patterns:** <similar code that may have the same issue>

## States/Conditions Enumerated
<Complete list of states/values found by searching, not assumed>

## Recommended Fix
<Specific approach with code locations to change>

## Alternative Approaches
<Other solutions with pros/cons>
```

## When This Phase Is Done

Report: the identified root cause, confidence level, and where the analysis
was written.
