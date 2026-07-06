---
name: rebase
description: >
  Systematically rebase a branch onto its upstream target. Use when a feature
  branch has fallen behind, needs conflict resolution, requires commit cleanup
  before merge, or when a PR review requests a rebase. Handles complex
  multi-commit branches with many conflicts via incremental strategies.
argument-hint: "[TARGET_BRANCH | PR_NUMBER]"
allowed-tools:
  - Bash(git status *)
  - Bash(git fetch *)
  - Bash(git rev-parse *)
  - Bash(git rev-list *)
  - Bash(git merge-base *)
  - Bash(git log *)
  - Bash(git diff *)
  - Bash(git branch *)
  - Bash(git config *)
  - Bash(git rebase *)
  - Bash(git checkout *)
  - Bash(git cherry-pick *)
  - Bash(git add *)
  - Bash(git push --force-with-lease *)
  - Bash(git reset *)
  - Bash(git reflog *)
  - Bash(gh pr view *)
  - Bash(gh pr checkout *)
  - Bash(comm *)
  - Bash(diff *)
  - Bash(rm -f /tmp/pre-rebase.diff /tmp/post-rebase.diff)
  - Bash(make test *)
  - Bash(pytest *)
  - Bash(npm test *)
  - Read
  - Edit
  - Grep
  - AskUserQuestion
---

# Rebase Branch

Rebase a branch onto its upstream target.

- `$ARGUMENTS` is a **PR number** (all digits) → check out the PR branch and rebase
  onto the PR's base branch.
- `$ARGUMENTS` is a **branch name** → rebase current branch onto that target.
- `$ARGUMENTS` is **empty** → rebase current branch onto the upstream default branch.

## Critical Rules

- **Never rebase without a backup.** Always create a backup ref before starting.
- **Never use `--force`.** Always use `--force-with-lease` when pushing.
- **Never rebase shared branches** without explicit user confirmation.
- **Don't rewrite history unless asked.** The goal is to replay commits onto a new
  base — not to squash, fixup, or reword. Only offer commit cleanup if the user
  explicitly requests it.
- **Verify the result.** Always diff the tree before and after.
- **Conflict sides are swapped from merge.** During rebase: `ours` = upstream,
  `theirs` = your branch. The opposite of what you expect.

## Phase 1: Assess

### Step 1: Determine target and current state

If `$ARGUMENTS` is all digits, treat it as a PR number:

```bash
# Fetch PR metadata
gh pr view "$ARGUMENTS" --json headRefName,baseRefName,headRepository,headRepositoryOwner \
  --jq '{head: .headRefName, base: .baseRefName, repo: .headRepository.name, owner: .headRepositoryOwner.login}'
```

Check out the PR branch locally:

```bash
gh pr checkout "$ARGUMENTS"
CURRENT=$(git rev-parse --abbrev-ref HEAD)
TARGET="<baseRefName from above>"
```

Otherwise, determine target from the argument or defaults:

```bash
TARGET="${ARGUMENTS:-$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|origin/||')}"
DEFAULT_BRANCH="${PRIMARY_BRANCH:-master}"
TARGET="${TARGET:-$DEFAULT_BRANCH}"
CURRENT=$(git rev-parse --abbrev-ref HEAD)
```

```bash
echo "Rebasing $CURRENT onto $TARGET"
git status --porcelain
```

If there are uncommitted changes, **stop**. Ask the user: stash, commit, or abort.

### Step 2: Measure complexity

```bash
git fetch origin "$TARGET"

# Commits to rebase
git rev-list --count "origin/$TARGET..HEAD"

# Files changed on our branch
git diff --stat "origin/$TARGET...HEAD" | tail -1

# How far behind upstream
git rev-list --count "HEAD..origin/$TARGET"

# Check for merge commits (affects strategy)
git log --merges --oneline "origin/$TARGET..HEAD"

# Count files changed on BOTH sides (conflict indicators)
comm -12 \
  <(git diff --name-only "$(git merge-base HEAD origin/$TARGET)..HEAD" | sort) \
  <(git diff --name-only "$(git merge-base HEAD origin/$TARGET)..origin/$TARGET" | sort)
```

If **merge commits** exist on the branch, warn the user: a plain rebase linearizes
them. Use `--rebase-merges` to preserve topology, or confirm linearizing is OK.

Report complexity class:

| Commits | Upstream divergence | Class | Strategy |
|---------|-------------------|-------|----------|
| 1–5 | <50 | Simple | Direct rebase |
| 6–20 | <200 | Moderate | Direct rebase |
| >20 or many overlapping files | any | Complex | Incremental rebase |

**Override to Complex** if >5 files changed on both sides, even with few commits.

Only use interactive rebase (`-i`) if the user explicitly asks for commit cleanup.

## Phase 2: Prepare

### Step 3: Safety net

```bash
git branch -f "backup/$CURRENT" HEAD

# Record pre-rebase tree diff for verification (two-dot: exact diff against target)
git diff "origin/$TARGET..HEAD" > /tmp/pre-rebase.diff
```

### Step 4: Enable rerere

```bash
git config rerere.enabled true
```

Rerere records conflict resolutions and auto-applies them if the same conflicts
recur. Essential for repeated rebases or incremental strategies.

## Phase 3: Execute

Choose strategy based on complexity class. Default is a straight replay — no
history rewriting.

### Direct rebase (simple / moderate)

```bash
git rebase "origin/$TARGET"
# If merge commits exist and user wants to preserve them:
# git rebase --rebase-merges "origin/$TARGET"
```

If conflicts occur, go to Phase 4.

### Interactive rebase (only if user requests commit cleanup)

Only use this when the user explicitly asks to squash, fixup, reword, or
reorder commits. Preview the commit list first:

```bash
git log --oneline --reverse "origin/$TARGET..HEAD"
```

Ask the user which commits to change. Apply via `GIT_SEQUENCE_EDITOR` to
avoid requiring an interactive terminal:

```bash
# Example: squash commits 2-3 into 1, fixup commit 5
GIT_SEQUENCE_EDITOR="sed -i -e '2s/^pick/squash/' -e '3s/^pick/squash/' -e '5s/^pick/fixup/'" \
  git rebase -i "origin/$TARGET"
```

Adapt the sed expression to match the user's choices.

### Incremental rebase (complex)

When the branch is far behind or conflicts are expected across many commits,
rebase in stages to keep conflict sets small and let rerere learn resolutions:

```bash
# Find the merge base (where we branched off)
MERGE_BASE=$(git merge-base HEAD "origin/$TARGET")

# Count upstream commits to choose milestone spacing
BEHIND=$(git rev-list --count HEAD.."origin/$TARGET")

# Pick 2-3 milestones evenly spaced between merge base and tip
# For 90 commits behind: pick ~30 and ~60
git log --oneline --reverse "$MERGE_BASE..origin/$TARGET" | head -n 30 | tail -1
git log --oneline --reverse "$MERGE_BASE..origin/$TARGET" | head -n 60 | tail -1
```

Good milestones are commits that DON'T touch the same files as your branch.

```bash
# Rebase to oldest milestone first
git rebase <milestone-1>
# Resolve conflicts — rerere records them

# Advance to next milestone
git rebase <milestone-2>
# Rerere auto-resolves previously seen conflicts

# Final rebase to tip
git rebase "origin/$TARGET"
```

**Alternative for very complex cases — cherry-pick one at a time:**

```bash
COMMITS=$(git rev-list --reverse "origin/$TARGET..HEAD")
git checkout -b "rebase-wip/$CURRENT" "origin/$TARGET"

for SHA in $COMMITS; do
    git cherry-pick "$SHA" || break
done
```

After all commits applied, point the original branch at the result (safe — the
backup ref preserves the original state):

```bash
git checkout "$CURRENT"
git reset --hard "rebase-wip/$CURRENT"
git branch -D "rebase-wip/$CURRENT"
```

## Phase 4: Resolve Conflicts

When a conflict occurs:

### Step 1: Identify

```bash
git diff --name-only --diff-filter=U
```

### Step 2: Resolve each file

1. Read the conflicted file
2. Understand both sides:
   - **Ours** (upstream): what changed on the target branch
   - **Theirs** (our commit): what we intended to change
3. Resolve by preserving our intent on top of upstream changes
4. For files where one side clearly wins:
   ```bash
   git checkout --theirs <file>   # keep our version
   git checkout --ours <file>     # keep upstream version
   ```
5. Stage:
   ```bash
   git add <resolved-file>
   ```

### Step 3: Continue

```bash
git rebase --continue
```

If a conflict is ambiguous, ask the user before resolving.

### Abort if needed

```bash
git rebase --abort
# or restore from backup:
git reset --hard "backup/$CURRENT"
```

## Phase 5: Verify

### Step 1: Compare diffs

The rebase replays commits onto a new base — the net diff against the target
should be the same. Verify:

```bash
git diff "origin/$TARGET..HEAD" > /tmp/post-rebase.diff
diff /tmp/pre-rebase.diff /tmp/post-rebase.diff
```

If the diffs differ, investigate. Legitimate reasons:
- Conflict resolutions that accepted upstream changes over ours
- Code refactored on both sides

If unexpected differences exist, **stop** and show the user.

### Step 2: Check for lost commits

```bash
# Commits in backup not in current branch
git log --oneline HEAD.."backup/$CURRENT"
```

Should be empty unless commits were intentionally squashed or dropped.

### Step 3: Run tests if configured

```bash
make test 2>/dev/null || pytest 2>/dev/null || npm test 2>/dev/null
```

If tests fail, **stop** and report the failures to the user before pushing.

## Phase 6: Push

### Step 1: Confirm

Summarize for the user:
- Commits rebased (count)
- Conflicts resolved (count, files)
- Verification result
- Target branch

Ask the user to confirm before pushing.

### Step 2: Force-push with lease

```bash
git push --force-with-lease origin "$CURRENT"
```

If rejected (remote ref moved since last fetch), run `git fetch origin "$CURRENT"`
and assess whether someone else pushed to the branch. Ask the user before retrying.

### Cleanup

```bash
git branch -D "backup/$CURRENT"
rm -f /tmp/pre-rebase.diff /tmp/post-rebase.diff
```

## Recovery

If something went wrong after the rebase:

```bash
# Option 1: Backup branch
git reset --hard "backup/$CURRENT"

# Option 2: Reflog (backup already deleted)
git reflog
git reset --hard HEAD@{N}   # N = pre-rebase entry
```
