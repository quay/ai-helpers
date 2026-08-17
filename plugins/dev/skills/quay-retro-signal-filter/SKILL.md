---
name: quay-retro-signal-filter
description: >-
  Use with the retro agent when deciding whether workflow observations are
  actionable proposals. Filters process-only noise and deduplicates proposals
  by root cause while preserving concrete production, security, CI, and
  recurring contributor failures.
---

# Quay Retro Signal Filter

## What this skill controls

This skill controls only **proposal eligibility and deduplication** for the retro
agent's `proposals` array. The built-in `retro-analysis` skill owns workflow
tracing, evidence gathering, existing-issue searches, localization, and the
required JSON output shape. Do not replace those procedures.

## What this skill does not control

- The workflow reconstruction or investigation procedure.
- The required `summary` and proposal fields.
- Existing-issue searches or duplicate-issue checks required by
  `retro-analysis`.
- The target repository decision or implementation of any fix.

## Proposal eligibility

Before including a proposal, classify its primary evidence and impact.

**Do not create a GitHub issue** when the finding is exclusively about any of
these:

- CodeRabbit path instructions or missed CodeRabbit review comments after
  merge.
- Agent-documentation completeness.
- An isolated review-comment or review-process lapse.
- Stylistic, naming, or other subjective preferences.
- One-off test cleanup.
- An item already marked duplicate, not planned, or superseded.

These observations may be mentioned briefly in `summary` when useful for the
retrospective record, but they must not become proposals.

A finding from one of those categories is proposal-eligible only when the
evidence shows at least one concrete consequence:

- A production defect.
- A security exposure.
- A recurring CI failure.
- Repeated contributor failure across independent workflows or attempts.

A missed review comment is not itself a defect. Require evidence of one of the
concrete consequences above; do not infer impact merely because a comment was
unaddressed.

## Root-cause deduplication

Treat proposals as belonging to the same root cause when they would be fixed
by the same change, affect the same subsystem, or describe the same recurring
failure mechanism. Before writing the final JSON:

1. Group candidate findings by root cause or subsystem.
2. Merge evidence and uncertainty into one proposal per group.
3. Emit **at most one proposal per root cause or subsystem**.
4. Put corroborating evidence for merged or filtered candidates in `summary`,
   not in separate proposals.
5. Continue to apply `retro-analysis`'s mandatory search for overlapping open
   issues; do not file a new proposal when an existing issue covers the same
   improvement.

## Final self-check

Before writing `$FULLSEND_OUTPUT_DIR/agent-result.json`, verify:

- Every proposal has a concrete production, security, recurring-CI, or
  repeated-contributor impact, unless it is outside the excluded categories.
- No proposal is solely a CodeRabbit/path-instruction, documentation,
  isolated-process, style/naming, one-off-cleanup, duplicate, not-planned, or
  superseded finding.
- No two proposals would be fixed by the same change or belong to the same
  subsystem/root cause.
- Filtered observations and corroborating evidence are summarized rather than
  filed as issues.

If no candidate survives these checks, return an empty `proposals` array and a
concise `summary`.
