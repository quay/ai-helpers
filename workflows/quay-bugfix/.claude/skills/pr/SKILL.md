---
name: pr
description: >
  Create a pull request with Quay conventions. Validates PR title against
  CI regex, includes JIRA link, handles fork workflow with fallback ladder,
  and starts CI polling.
allowed-tools:
  - Bash(bash .claude/scripts/validate-pr-title.sh *)
  - Bash(bash .claude/scripts/poll-pr.sh *)
  - Bash(bash .claude/scripts/jira-ops.sh *)
  - Bash(git *)
  - Bash(gh *)
  - Bash(cat *)
  - Bash(echo $AGENTIC_SESSION_NAME)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# Create Pull Request

Get the changes submitted as a draft pull request. This skill handles the
full git workflow: validate, push, and PR creation with Quay conventions.

## IMPORTANT: Follow This Skill Exactly

Do not improvise. Follow the numbered steps in order. When steps fail, use
the documented fallback ladder.

## Critical Rules

- **Always use a fork.** Every push goes to a fork remote, every PR is a
  cross-fork PR. No exceptions — even if you have write access to upstream.
  This is the only supported workflow.
- **Never push directly to upstream.** Not even for "small" changes.
- **Never skip pre-flight checks.**
- **Always create a draft PR.**
- **Always work in the project repo directory**, not the workflow directory.

## Process

### Step 0: Determine Auth Context

```bash
gh auth status
```

Determine your identity:

```bash
gh api user --jq .login 2>/dev/null
```

If that fails (403), you're running as a GitHub App:

```bash
gh api /installation/repositories --jq '.repositories[0].owner.login'
```

Record `GH_USER` and `AUTH_TYPE` (user-token / github-app / none).

If `gh auth status` fails, check for a git credential helper and attempt
token recovery (see CLAUDE.md safety rules).

### Step 1: Locate the Project Repository

```bash
ls /workspace/repos/ 2>/dev/null
```

`cd` into the project repo directory. All subsequent git commands run there.

### Step 2: Pre-flight Checks

**2a. Git configuration:**

```bash
git config user.name && git config user.email
```

If missing, set from `GH_USER`.

**2b. Inventory remotes:**

```bash
git remote -v
```

**2c. Identify upstream and default branch:**

```bash
gh repo view --json nameWithOwner,defaultBranchRef --jq '{nameWithOwner, defaultBranch: .defaultBranchRef.name}'
```

Record `UPSTREAM_OWNER/REPO` and `DEFAULT_BRANCH`. Do not assume `main`.

**2d. Verify changes exist:**

```bash
git status && git diff --stat
```

### Step 3: Validate PR Title

**Before creating the PR**, validate the title against Quay's CI regex:

```bash
bash .claude/scripts/validate-pr-title.sh "$TICKET: fix(scope): description here"
```

Title format: `PROJQUAY-XXXX: type(scope): description`

### Step 4: Ensure Fork Exists

```bash
gh repo list GH_USER --fork --json nameWithOwner,parent --jq '.[] | select(.parent.owner.login == "UPSTREAM_OWNER" and .parent.name == "REPO") | .nameWithOwner'
```

If no fork exists, ask the user before creating one.

### Step 5: Configure Fork Remote

```bash
git remote -v | grep FORK_OWNER
```

If not present:

```bash
git remote add fork https://github.com/FORK_OWNER/REPO.git
```

### Step 6: Check Fork Sync Status

```bash
git fetch FORK_REMOTE && git fetch UPSTREAM_REMOTE
WORKFLOW_DIFF=$(git diff --name-only FORK_REMOTE/DEFAULT_BRANCH..UPSTREAM_REMOTE/DEFAULT_BRANCH -- .github/workflows/ 2>/dev/null)
```

If workflow differences exist, attempt automated sync:

```bash
gh api --method POST repos/FORK_OWNER/REPO/merge-upstream -f branch=DEFAULT_BRANCH
```

### Step 7: Push to Fork

```bash
gh auth setup-git
git push -u FORK_REMOTE BRANCH_NAME
```

### Step 8: Build PR Description

Read the PR description artifact if it exists:

```bash
cat artifacts/quay-bugfix/docs/pr-description.md 2>/dev/null
```

If not, compose from session context.

Check for ambient session metadata:

```bash
echo $AGENTIC_SESSION_NAME
```

### Step 9: Create Draft PR

```bash
gh pr create \
  --draft \
  --repo UPSTREAM_OWNER/REPO \
  --head FORK_OWNER:BRANCH_NAME \
  --base DEFAULT_BRANCH \
  --title "$TICKET: type(scope): description" \
  --body-file /tmp/pr-body.md
```

If `AGENTIC_SESSION_NAME` is set, add `--label "${AMBIENT_SESSION_LABEL:-ambient-session}"`.

**If `gh pr create` fails (403, "Resource not accessible"):**

This is expected for GitHub App bots. Provide the user a pre-filled compare
URL:

```
https://github.com/UPSTREAM_OWNER/REPO/compare/DEFAULT_BRANCH...FORK_OWNER:BRANCH_NAME?expand=1&title=URL_ENCODED_TITLE&body=URL_ENCODED_BODY
```

### Step 10: Start CI Polling

After PR creation, poll for CI status:

```bash
bash .claude/scripts/poll-pr.sh $PR_NUMBER --once
```

| Exit | Meaning | Action |
|------|---------|--------|
| 0 | All pass | Report success |
| 1 | CI fail | Note failures for follow-up |
| 2 | Pending | Note CI is still running |
| 3 | Comments | Note review comments |
| 4 | Awaiting review | Note awaiting human review |

### Step 11: Backport Suggestion

If the assessment noted `Backport Required: Yes`, remind the user:

> Backport is required. After merge, run `/dev:backport <PR#>`.

## Fallback Ladder

### Rung 1: Fix and Retry
Most failures have a specific cause. Diagnose and retry.

### Rung 2: Manual PR via Compare URL
If `gh pr create` fails but the branch is pushed, provide a pre-filled
GitHub compare URL with title and body query parameters.

### Rung 3: User Creates Fork
If no fork exists and automated forking fails, give the user the fork URL
and wait.

### Rung 4: Patch File (absolute last resort)
Only if ALL above fail:

```bash
git diff > artifacts/quay-bugfix/changes.patch
```

## Output

- PR URL printed to the user
- `artifacts/quay-bugfix/docs/pr-description.md` (if not already written)

## When This Phase Is Done

Report: PR URL, what was included, branch target, follow-up actions.
