---
name: backport
description: >
  Backport a merged PR to release branches. Detects prior bot failures,
  performs manual cherry-picks from a fork matching bot conventions,
  and handles JIRA clone tickets. Derives target branches from fixVersions.
argument-hint: PR_NUMBER [BRANCH]
allowed-tools:
  - Bash(bash .claude/scripts/jira-ops.sh *)
  - Bash(gh pr *)
  - Bash(gh api user *)
  - Bash(git cherry-pick *)
  - Bash(git checkout *)
  - Bash(git fetch *)
  - Bash(git remote *)
  - Bash(git diff *)
  - Bash(git add *)
  - Bash(git ls-remote *)
  - Read
  - Grep
  - AskUserQuestion
---

# Backport PR

Backport merged PR #$ARGUMENTS[0] to release branches.

- **PR number**: `$ARGUMENTS[0]`
- **Branch** (optional): `$ARGUMENTS[1]` — if omitted, derive from JIRA fixVersions

## Phase 1: Discovery

### Step 1: Verify PR is merged

```bash
gh pr view "$ARGUMENTS[0]" --json state,mergedAt,mergeCommit,title,baseRefName
```

The PR must be merged. If not, inform the user and stop. Extract:
- `mergeCommit.oid` — the merge commit SHA
- `title` — extract the JIRA key (pattern: `PROJQUAY-\d+` or similar prefix)
- `baseRefName` — should be `master`

### Step 2: Determine backport branches

If `$ARGUMENTS[1]` is provided, use it as the sole target branch. Skip to Phase 2.

Otherwise, fetch JIRA fields to compute branches:

```bash
bash .claude/scripts/jira-ops.sh get-fix-versions <TICKET-KEY>
bash .claude/scripts/jira-ops.sh check-version <TICKET-KEY>
```

**Version → Branch mapping:** Strip `quay-v` prefix, extract `major.minor`, prepend
`redhat-`. Examples: `quay-v3.17.z` → `redhat-3.17`, `quay-v3.16.2` → `redhat-3.16`.

**Backport branches** = branches from Fix Versions, minus the branch matching
Target Version (that's the branch the original ticket already covers).

Validate each branch exists:

```bash
git ls-remote --heads upstream redhat-X.Y
```

If no backport branches remain, report "no backports needed" and stop.

## Phase 2: Per-Branch State Detection

For each backport branch, determine its current state before acting:

### Check 1: Existing backport PR

```bash
gh pr list --repo quay/quay --base <BRANCH> --state all \
  --search "cherry-pick-$ARGUMENTS[0]-to-<BRANCH>" \
  --json number,title,state,headRefName
```

- If a **merged** backport PR exists → skip this branch, report "already backported"
- If an **open** backport PR exists → skip this branch, report the PR URL

### Check 2: Prior bot failure

Search the original PR's comments for the cherry-pick robot's failure message:

```bash
gh pr view "$ARGUMENTS[0]" --repo quay/quay --json comments \
  --jq '[.comments[] | select(.author.login == "openshift-cherrypick-robot") | select(.body | test("failed to apply on top of branch"))] | length'
```

Then check if the failure is for THIS specific branch by examining the comment body
for `failed to apply on top of branch "<BRANCH>"`.

### Decision

- Bot already **failed** for this branch → proceed to **Phase 3** (manual fallback)
- **No prior attempt** → trigger the bot and report:
  ```bash
  gh pr comment "$ARGUMENTS[0]" --repo quay/quay --body "/cherrypick <BRANCH>"
  ```

## Phase 3: Manual Fallback

For each branch where the bot failed:

### Step 1: Find or create the JIRA clone ticket

The bot usually creates clone tickets during `/jira backport` (stored as
`jlp-<branch>:<clone-key>` labels on the original JIRA issue). Look it up:

```bash
bash .claude/scripts/jira-ops.sh get-clone-key <TICKET-KEY> <BRANCH>
```

If the result is `none`, create a clone. First determine the fixVersion for this
branch (the fixVersion whose `major.minor` matches the branch), then:

```bash
bash .claude/scripts/jira-ops.sh clone <TICKET-KEY> <FIX_VERSION>
```

### Step 2: Cherry-pick from fork

```bash
git remote get-url upstream 2>/dev/null || git remote add upstream https://github.com/quay/quay.git
git fetch upstream <BRANCH>
git checkout -b cherry-pick-$ARGUMENTS[0]-to-<BRANCH> upstream/<BRANCH>
git cherry-pick -m 1 <MERGE_COMMIT_SHA>
```

### Step 3: Resolve conflicts

If `git cherry-pick` exits non-zero:

1. Show conflicting files: `git diff --name-only --diff-filter=U`
2. For each conflicted file, read the file and help resolve the conflict markers
3. After resolution: `git add <resolved-files>` then `git cherry-pick --continue`

Ask the user to confirm each conflict resolution before proceeding.

### Step 4: Push and create PR

The PR must match the cherry-pick bot's conventions:

- **Title format:** `[<BRANCH>] <CLONE_KEY>: <original-title-suffix>`
  - `<original-title-suffix>` is everything after the JIRA key in the original PR title
  - Example: original `PROJQUAY-11576: feat(ldap): add pool` with clone `PROJQUAY-11600`
    → `[redhat-3.17] PROJQUAY-11600: feat(ldap): add pool`
- **Body:** `This is an automated cherry-pick of #<PR_NUMBER>`
- **Branch name:** `cherry-pick-<PR_NUMBER>-to-<BRANCH>`

```bash
git push -u origin cherry-pick-$ARGUMENTS[0]-to-<BRANCH>

gh pr create --repo quay/quay \
  --base <BRANCH> \
  --head <FORK_OWNER>:cherry-pick-$ARGUMENTS[0]-to-<BRANCH> \
  --title "[<BRANCH>] <CLONE_KEY>: <TITLE_SUFFIX>" \
  --body "This is an automated cherry-pick of #$ARGUMENTS[0]"
```

Determine `<FORK_OWNER>` from: `gh api user --jq '.login'`

### Step 5: Report

For each branch processed, report:
- Clone ticket key (found or created)
- Backport PR URL
- Whether conflicts were resolved or the branch was skipped
