---
name: caveman
description: >-
  Ultra-compressed communication mode for user-facing prose only. Applies to
  triage issue comments and retro summaries while preserving full structured
  output, evidence, and stock skill requirements.
---

# Caveman

Use concise, direct prose. Remove filler, pleasantries, repetition, and hedging.
Prefer short sentences and bullets. State each fact once.

Caveman is a **communication overlay**, not a replacement for stock skills. It
compresses designated user-facing fields only. Everything else stays governed by
the agent definition and bundled skills (`retro-analysis`, `issue-labels`, etc.).

## Preserve correctness

- Keep all required JSON keys and schema-valid structure.
- Keep decisions, evidence, labels, reasons, and actionable details.
- Keep code, commands, identifiers, numbers, units, and exact error strings unchanged.
- Never omit or weaken `not`, `never`, `no`, `only`, or `except`.
- Do not compress prose when doing so could make sequence, ownership, risk, or meaning ambiguous.

No greetings. No decorative prose. No tool-call narration. Use normal prose for
security warnings, irreversible actions, and ambiguity-sensitive instructions.

## Field ownership (what Caveman may compress)

| Agent | Compress | Do not compress |
|-------|----------|-----------------|
| **Triage** | `comment` (GitHub issue comment the reporter reads) | `action`, `reasoning`, `label_actions`, clarity scores, all other JSON fields |
| **Retro** | `summary` (markdown posted on the originating issue/PR) | Every field inside each `proposals[]` object: `what_happened`, `what_could_go_better`, `proposed_change`, `validation_criteria`, `target_repo`, `title` |

If a stock skill or agent definition requires detail in a field Caveman does not
own, follow that skill. Caveman never overrides mandatory steps (duplicate-issue
checks, label discovery, timeline evidence in proposals).

## Works with stock skills

### `retro-analysis`

That skill owns investigation depth and proposal quality. It requires:

- Chronological `what_happened` with markdown links to runs, logs, and comments.
- Honest uncertainty in `what_could_go_better`.
- Specific, implementable `proposed_change` and measurable `validation_criteria`.
- A `summary` that may include filtered duplicates and high-level takeaways.

**Precedence:** `retro-analysis` wins on all proposal fields. Caveman wins **only**
on `summary` length and tone. Do not shorten proposals to make the retro feel
brief — a long retro with a short summary is the intended outcome.

### `issue-labels`

That skill owns `label_actions` discovery and recommendations. Caveman does not
change label logic or skip labeling steps. If the triage `comment` mentions
labels, keep it to one line; put the full recommendation in `label_actions`.

## Triage output

Keep the structured result complete. Compress **only** the user-facing `comment`:

- State decision (`sufficient` / `insufficient`), the single most important reason, and the next action.
- One clarifying question when `action` is `insufficient` — no preamble.
- Do not repeat the issue title, stack traces, or analysis already visible in `reasoning`.

**Before (verbose comment):**

> Thanks for filing this! I've reviewed the issue and the linked logs. It looks
> like the failure might be related to the cache configuration. Before we can
> move forward, could you please confirm whether this reproduces on the latest
> release?

**After (Caveman comment):**

> Insufficient: need confirmation this reproduces on the latest release before triage can proceed.

## Retro output

Keep evidence and improvement proposals complete per `retro-analysis`. Compress
**only** `summary`:

- Lead with the main finding or "no meaningful improvements found."
- One bullet per theme; link to key runs or issues.
- Do not restate workflow history that lives in `what_happened` or that the reader
  can inspect in Actions.

**Before (verbose summary):**

> This retro traced the full workflow from triage through code and review. The
> code agent ran twice because the first review requested changes. After
> examining the logs in detail, the main theme is missing error handling in the
> API client. See proposal 1 below for details.

**After (Caveman summary):**

> Main gap: API client error handling (see proposal 1). Code agent needed two
> runs after review requested changes — [run link].

## Rollout and validation

When adopting Caveman org-wide:

1. **Enable on triage first** — comments are the highest-signal, lowest-risk surface.
2. **Add retro second** — validate that `summary` shrinks while proposal word count
   and link count stay stable or grow.
3. **Measure, don't guess:** compare word counts and link counts before/after on
   the same repo; a retro that loads Caveman but grows only in `summary` length
   means the overlay is not applied to the right field.

## Anti-patterns

- Compressing `what_happened` to satisfy a "be brief" instinct — breaks retro value.
- Duplicating proposal text in `summary` because Caveman was not applied to proposals.
- Replacing links with vague references ("see the failed run") — keep links in
  proposals; `summary` may use one anchor link per theme.
