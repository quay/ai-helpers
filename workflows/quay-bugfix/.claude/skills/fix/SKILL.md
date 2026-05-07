---
name: fix
description: >
  Implement a bug fix following Quay conventions. Creates a feature branch,
  applies the minimal correct fix, and runs format-and-lint.sh.
allowed-tools:
  - Bash(bash .claude/scripts/format-and-lint.sh *)
  - Bash(bash .claude/scripts/tick-state.sh *)
  - Bash(bash .claude/scripts/jira-ops.sh *)
  - Bash(git *)
  - Bash(make *)
  - Bash(pytest *)
  - Bash(python *)
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

# Implement Bug Fix

Apply the minimal correct fix based on the diagnosis.

## Process

### Step 1: Review Fix Strategy

- Read the root cause analysis (`artifacts/quay-bugfix/analysis/root-cause.md`)
- Confirm the recommended fix approach
- Consider alternative solutions and trade-offs
- Check for pattern documentation: if the project has `AGENTS.md` or
  `agent_docs/`, review relevant patterns. Verify completeness by
  cross-referencing with actual usage in the codebase.

### Step 2: Create Feature Branch

```bash
git checkout ${PRIMARY_BRANCH:-master} && git pull origin ${PRIMARY_BRANCH:-master}
git checkout -b $TICKET-short-description
```

Branch naming: `<TICKET-KEY>-<kebab-case-description>` (e.g.,
`PROJQUAY-1234-fix-tag-pagination`).

If a branch already exists with changes from a prior phase, use it.

### Step 3: Read Conventions

Read the project's `AGENTS.md` for subsystem-specific conventions. Load area
docs if available (check `agent_docs/` directory).

### Step 4: Implement

Follow Quay conventions:

- Use project-standard exception types
- Follow existing import ordering patterns
- Never hand-write Alembic migrations — use `alembic revision --autogenerate`
- No secrets in code
- Match existing code style in the file being modified

### Step 5: Verify Completeness

**CRITICAL:** Before finalizing:

- **Identify all possible states/phases**: If fixing state-dependent logic,
  search the codebase for the complete list. Don't assume — verify.
- **Understand feature interactions**: If the fix uses multiple configuration
  options or features together, research how they interact.
- **Check for complete enumeration**: If implementing switch/case logic,
  verify you've handled all possible values by searching where they're defined.

### Step 6: Review Error Handling UX

If the fix involves error handling or user-facing messages:

- Match error context to error type (CLI error vs config error vs runtime error)
- Test every error path manually
- Ensure error messages don't leak internals

### Step 7: Quality Checks

```bash
bash .claude/scripts/format-and-lint.sh
```

Fix any issues raised by pre-commit hooks or linters. Ensure the build passes.

### Step 8: Commit

```bash
git add <specific files>
git commit -m "<subsystem>: <what changed> ($TICKET)"
```

If pre-commit hooks fail: fix, re-stage, create a new commit. Never use
`--no-verify`.

### Step 9: Write Implementation Notes

Save to `artifacts/quay-bugfix/fixes/implementation-notes.md`:

```markdown
# Implementation Notes: <TICKET>

## Branch
`<branch-name>`

## Changes
| File | Change | Why |
|------|--------|-----|
| `file:line` | <what changed> | <why> |

## Conventions Followed
- Commit format: `<subsystem>: <desc> (<TICKET>)`
- Linting: passed via format-and-lint.sh
- Area docs consulted: <which ones>

## Completeness Check
- [ ] All states/conditions handled
- [ ] Similar patterns checked
- [ ] Error handling appropriate
- [ ] No regressions expected in: <list areas>
```

## Output

- Modified code files in the working tree
- `artifacts/quay-bugfix/fixes/implementation-notes.md`

## When This Phase Is Done

Report: what was changed, quality checks passed, where the notes were written.
