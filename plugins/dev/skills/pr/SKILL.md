---
name: pr
description: >
  Create a pull request with the correct title format, filled-in description
  template, and JIRA reference. Handles fork workflow with fallback ladder.
  Validates the PR title against the CI-enforced regex before creating.
allowed-tools:
  - Bash(bash .claude/scripts/enforce-pr-skill.sh *)
  - Bash(bash .claude/scripts/validate-pr-title.sh *)
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

Create a PR with the correct title format, description, and JIRA reference.
This skill handles the full git workflow: validate, push, and PR creation.

## IMPORTANT: Follow This Skill Exactly

Do not improvise. Follow the numbered steps in order. When steps fail, use
the documented fallback ladder.

## Critical Rules

- **Always use a fork.** Every push goes to a fork remote, every PR is a
  cross-fork PR. No exceptions — even if you have write access to upstream.
- **Never push directly to upstream.** Not even for "small" changes.
- **Never skip pre-flight checks.**

## Step 0: Determine Auth Context

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

## Step 1: Pre-flight Checks

**1a. Git configuration:**

```bash
git config user.name && git config user.email
```

If missing, set from `GH_USER`.

**1b. Inventory remotes:**

```bash
git remote -v
```

**1c. Identify upstream and default branch:**

```bash
gh repo view --json nameWithOwner,defaultBranchRef --jq '{nameWithOwner, defaultBranch: .defaultBranchRef.name}'
```

Record `UPSTREAM_OWNER/REPO` and `DEFAULT_BRANCH`. Do not assume `main`.

**1d. Verify changes exist:**

```bash
git status && git diff --stat
```

## Step 2: Validate PR Title

Title **must** match the CI-enforced regex (set via `$PR_TITLE_PATTERN` env var):

```text
${PR_TITLE_PATTERN:-^(?:\[redhat-[0-9]+\.[0-9]+\] )?(?:PROJQUAY-[0-9]+|QUAYIO-[0-9]+|NO-ISSUE): [a-z]+(?:\([^)]+\))?: .+$}
```

```bash
bash .claude/scripts/validate-pr-title.sh "PROJQUAY-1234: fix(api): description here"
```

## Step 3: Build Description

Read the template at `.claude/templates/pr-description.md`. Fill in:
- **Summary**: What this PR does
- **Root Cause / Rationale**: Why
- **Changes**: What changed
- **Test Plan**: How to verify
- **JIRA Link**: `${JIRA_BROWSE_URL:-https://redhat.atlassian.net/browse}/<TICKET-KEY>`
- **Backport**: Required or not

Check for ambient session metadata:

```bash
echo $AGENTIC_SESSION_NAME
```

- **If `AGENTIC_SESSION_NAME` is set**: populate the `## Automation` section.
- **If empty/unset**: remove the `## Automation` section entirely.

Write the filled template to `/tmp/pr-body.md`.

## Step 4: Ensure Fork Exists

```bash
gh repo list GH_USER --fork --json nameWithOwner,parent --jq '.[] | select(.parent.owner.login == "UPSTREAM_OWNER" and .parent.name == "REPO") | .nameWithOwner'
```

If no fork exists, ask the user before creating one.

## Step 5: Configure Fork Remote

```bash
git remote -v | grep FORK_OWNER
```

If not present:

```bash
git remote add fork https://github.com/FORK_OWNER/REPO.git
```

## Step 6: Sync Fork and Push

```bash
git fetch FORK_REMOTE && git fetch UPSTREAM_REMOTE
```

If workflow file differences exist, attempt automated sync:

```bash
gh api --method POST repos/FORK_OWNER/REPO/merge-upstream -f branch=DEFAULT_BRANCH
```

Push:

```bash
gh auth setup-git
git push -u FORK_REMOTE BRANCH_NAME
```

## Step 7: Create PR

If `AGENTIC_SESSION_NAME` was set, include `--label`:

```bash
gh pr create \
  --repo UPSTREAM_OWNER/REPO \
  --head FORK_OWNER:BRANCH_NAME \
  --base DEFAULT_BRANCH \
  --title "<TICKET>: type(scope): description" \
  --body "$(cat /tmp/pr-body.md)" \
  --label "${AMBIENT_SESSION_LABEL:-ambient-session}"
```

For manual PRs (no ambient session), omit the `--label` flag.

**If `gh pr create` fails (403, "Resource not accessible"):**

Provide the user a pre-filled compare URL:

```text
https://github.com/UPSTREAM_OWNER/REPO/compare/DEFAULT_BRANCH...FORK_OWNER:BRANCH_NAME?expand=1&title=URL_ENCODED_TITLE&body=URL_ENCODED_BODY
```

## Step 8: Post-PR

**Always** run `/poll <PR#>` immediately after PR creation — do not ask the user.

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
git diff > /tmp/changes.patch
```
