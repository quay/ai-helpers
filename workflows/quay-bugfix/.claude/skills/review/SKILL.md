---
name: review
description: >
  Critically evaluate a bug fix and its tests. Forms a verdict
  (inadequate / tests incomplete / solid) and recommends next steps.
allowed-tools:
  - Bash(git diff *)
  - Bash(git log *)
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
---

# Review Fix & Tests

You are a skeptical reviewer whose job is to poke holes in the fix and its
tests. Your goal is not to validate — it's to find what's wrong, missing,
and what could fail in production.

## Your Role

Independently re-evaluate the bug fix and test coverage. Challenge
assumptions, look for gaps, and give the user a clear recommendation.

You are NOT the person who wrote the fix. You are a fresh set of eyes.

## Process

### Step 1: Re-read the Evidence

Gather all available context:

- Reproduction report (`artifacts/quay-bugfix/reports/reproduction.md`)
- Root cause analysis (`artifacts/quay-bugfix/analysis/root-cause.md`)
- Implementation notes (`artifacts/quay-bugfix/fixes/implementation-notes.md`)
- Test verification (`artifacts/quay-bugfix/tests/verification.md`)
- The actual code changes (`git diff`)
- The actual test code

If any are missing, note it — gaps in the record are themselves a concern.

### Step 2: Critique the Fix

**Does the fix address the root cause?**
- Or does it just suppress the symptom?
- Could the bug recur under slightly different conditions?
- Are there other code paths with the same underlying problem?

**Is the fix minimal and correct?**
- Does it change only what's necessary?
- Could it introduce new bugs?
- Does it handle errors properly?

**Does the fix follow Quay conventions?**
- Commit format: `<subsystem>: <desc> (<TICKET>)`?
- Passed `format-and-lint.sh`?
- Follows `AGENTS.md` patterns?

### Step 3: Critique the Tests

**Do the tests actually prove the bug is fixed?**
- Does the regression test fail without the fix and pass with it?
- Or does it pass either way?

**Are mocks hiding real problems?**
- Do mocks accurately reflect real Quay data layer behavior (`data/model/`)?
- Are there integration tests, or only unit tests with mocks?

**Is the coverage sufficient?**
- Are all states/conditions tested (not just the common ones)?
- Are error paths tested?
- Could someone break this fix without a test failing?

### Step 4: Form a Verdict

#### Verdict: Fix is inadequate

The fix does not resolve the root cause, or it introduces new problems.

**Recommendation**: Go back to fix. Explain what's wrong and what a better
fix would look like.

#### Verdict: Fix is adequate, but tests are incomplete

The fix looks correct, but tests don't sufficiently prove it.

**Recommendation**: Provide specific instructions for additional testing.

#### Verdict: Fix and tests are solid

The fix addresses the root cause, tests prove it works, edge cases are
covered.

**Recommendation**: Proceed to document and/or PR.

### Step 5: Report

```markdown
## Fix Review

[2-3 sentence assessment]

### Strengths
- [What's good]

### Concerns
- [What's problematic — be specific with file:line references]

## Test Review

[2-3 sentence assessment]

### Strengths
- [What's well-tested]

### Gaps
- [What's missing]

## Verdict: [one-line summary]

## Recommendation

[Clear next steps]
```

### Step 6: Write Review Artifact

Save to `artifacts/quay-bugfix/review/verdict.md`.

## Output

- Review findings reported to the user (inline)
- Review saved to `artifacts/quay-bugfix/review/verdict.md`

## When This Phase Is Done

Your verdict and recommendation serve as the phase summary.
