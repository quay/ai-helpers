---
name: summary
description: >
  Scan all workflow artifacts and present a synthesized summary of findings,
  decisions, and status. Can be invoked at any point mid-workflow.
allowed-tools:
  - Bash(find artifacts/quay-bugfix/ *)
  - Bash(ls artifacts/quay-bugfix/ *)
  - Read
  - Glob
  - Grep
---

# Workflow Summary

This skill can be invoked at any point. It summarizes whatever exists so far.

## Your Role

Scan the artifact directory, read what's there, and synthesize the important
findings into a single summary. Surface things that might otherwise get
buried: related PRs, reproduction failures, review concerns, unconfirmed
assumptions.

## Process

### Step 1: Discover Artifacts

```bash
find artifacts/quay-bugfix/ -type f -name '*.md' ! -name 'summary.md' 2>/dev/null | sort
```

If `artifacts/quay-bugfix/` doesn't exist or is empty, report that no
artifacts have been generated yet and stop.

### Step 2: Read All Artifacts

Read every artifact found. Don't skip any.

### Step 3: Extract Key Findings

Pull out information in these categories:

- **Existing work discovered**: Related PRs, duplicate issues, prior attempts
- **Bug understanding**: What the bug is, whether it was reproduced
- **Root cause and fix**: Identified cause, what was changed and why
- **Testing status**: Full suite results, new regression tests
- **Review concerns**: Verdict, specific concerns, outstanding items
- **PR status**: URL, branch target, CI status
- **Backport**: Required or not

### Step 4: Present Summary

```markdown
## Quay Bugfix Workflow Summary

**Ticket:** [JIRA key and title]
**Status:** [where the workflow stopped]

### Key Findings
- [3-5 bullet points max]

### Decisions Made
- [choices made during the workflow]

### Outstanding Concerns
- [review caveats, untested edge cases — or "None"]

### Artifacts
- [list with one-line descriptions]

### PR
- [URL and status, or "Not yet created"]

### Backport
- [Required/Not required, and status]
```

Keep it tight — if it's as long as the artifacts, it's not a summary.

### Step 5: Write Summary Artifact

Save to `artifacts/quay-bugfix/summary.md`.

## Rules

- **Read, don't assume.** Base everything on what artifacts actually say.
- **Flag what's missing.** If a phase was skipped, say so.
- **Don't editorialize.** Report what artifacts say without softening.
- **Keep it short.** Under 40 lines of Markdown.

## Output

- Summary presented to the user (inline)
- Summary saved to `artifacts/quay-bugfix/summary.md`

## When This Phase Is Done

The summary is the deliverable. Present it and stop.
