---
name: code
description: >
  Implement changes following project conventions. Reads AGENTS.md and
  area-specific docs, then guides implementation, quality checks
  (pre-commit, tests), and commit with proper message format.
allowed-tools:
  - Bash(bash .claude/scripts/format-and-lint.sh *)
  - Bash(git *)
  - Bash(make *)
  - Bash(pytest *)
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

# Implement Changes

Implement code changes following project conventions.

## Step 1: Read Conventions

Read the project's `AGENTS.md` for universal conventions, then load area-specific
docs as identified in `/start`.

**Frontend auto-detect:** If the ticket touches `web/` files (check the branch
diff or ticket description), invoke `/frontend` to load Quay React + PatternFly
context before implementing.

## Step 2: Implement

Follow `AGENTS.md` conventions. Common rules:
- Use project-standard exception types
- Follow existing import ordering patterns
- Never hand-write migration files — use the project's migration tool first
- No secrets in code

## Step 3: Quality Checks

Pre-commit hooks run automatically on `git commit`. To run manually:

```bash
bash .claude/scripts/format-and-lint.sh            # staged files
bash .claude/scripts/format-and-lint.sh --all-files # all files
```

Run relevant tests per the project's test commands (check `AGENTS.md` for make targets).

## Step 4: Commit

Format:

```
<subsystem>: <what changed> (<TICKET-KEY>)

<why this change was made>
```

Pre-commit hooks run on commit — fix any failures and re-commit.

## Step 5: Continue — invoke /pr immediately

**Do not stop after committing.** Invoke the `/pr` skill immediately to create the pull request. The full workflow is a single uninterrupted pipeline:

```text
/code  →  /pr  →  /poll <PR#>
```

Only pause if there is a genuine blocker that requires a decision from the user.
