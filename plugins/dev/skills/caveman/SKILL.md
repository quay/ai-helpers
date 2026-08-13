---
name: caveman
description: >-
  Force short user-facing triage comments and retro summaries. Keep structured
  JSON and proposal evidence complete. Ban filler, hedging, and repetition.
---

# Caveman

**Job:** Make the text humans read short. Keep the structured data complete.

Humans read two things:

| Agent | Field humans read | Must be short |
|-------|-------------------|---------------|
| Triage | `comment` (issue comment) | Yes — hard limit below |
| Retro | `summary` (issue/PR comment) | Yes — hard limit below |

Everything else in the JSON is for machines and later agents. Do **not** shorten
it to satisfy Caveman.

## Hard rules (always)

1. No greetings, thanks, apologies, or “I reviewed…” narration.
2. No hedging: drop *might*, *seems*, *looks like*, *possibly*, *I think*, *could be*.
3. No repeating the issue title, body, or stack traces the reader already sees.
4. Prefer bullets over paragraphs. Prefer one clause over three.
5. Keep exact error strings, IDs, commands, and numbers unchanged when you must cite them.
6. Never drop `not` / `never` / `only` / `except` if that changes meaning.
7. Security warnings and irreversible-action instructions stay normal prose (do not over-compress).

## Triage: shorten `comment` only

**Limit:** ≤ 40 words. Prefer ≤ 2 short sentences or 2 bullets.

**Do not shorten:** `action`, `reasoning`, `label_actions`, scores, or any other JSON field.

### Templates (use these shapes)

**Sufficient:**

```text
Sufficient: <one-line why>. Next: <ready-to-code / waiting on X>.
```

**Insufficient (ask one question):**

```text
Insufficient: need <one fact>.

<one specific question the reporter can answer>
```

### Before → after

**Before (~55 words):**

> Thanks for filing this! I've reviewed the issue and the linked logs. It looks
> like the failure might be related to the cache configuration. Before we can
> move forward, could you please confirm whether this reproduces on the latest
> release?

**After (~14 words):**

> Insufficient: need confirmation this reproduces on latest release.
>
> Does this still fail on the latest release?

## Retro: shorten `summary` only

**Limit:** ≤ 80 words. Prefer ≤ 5 bullets.

**Shape:**

1. One lead line: main finding **or** `No meaningful improvements found.`
2. Then bullets: one theme each; optional one link per theme.
3. Stop. Do not retell the whole workflow.

**Do not shorten** anything inside `proposals[]`:

- `what_happened` — keep the timeline and links
- `what_could_go_better` — keep uncertainty and reasoning
- `proposed_change` — keep concrete file/config changes
- `validation_criteria` — keep measurable checks
- `title`, `target_repo`

Those fields belong to the `retro-analysis` skill. A long proposal body + short
`summary` is success. A short proposal body is failure.

### Before → after

**Before (~70 words):**

> This retro traced the full workflow from triage through code and review. The
> code agent ran twice because the first review requested changes. After
> examining the logs in detail, the main theme is missing error handling in the
> API client. See proposal 1 below for details.

**After (~25 words):**

> Main gap: API client error handling (proposal 1).
>
> - Code agent needed 2 runs after review changes — [run](url)

## Labels and other skills

- `issue-labels` owns `label_actions`. Put label detail there, not in `comment`.
- Caveman never skips duplicate-issue checks, label discovery, or proposal quality steps.

## Fail checks (rewrite if you hit these)

- `comment` or `summary` starts with “Thanks”, “I've”, or “This retro…”
- `comment` > 40 words or `summary` > 80 words
- `summary` retells triage → code → review instead of pointing at proposals
- You shortened `what_happened` / `proposed_change` to “be brief”
