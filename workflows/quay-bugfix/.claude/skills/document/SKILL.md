---
name: document
description: >
  Create comprehensive documentation for a Quay bug fix: JIRA ticket update,
  release notes, changelog entry, PR description, and team communication.
allowed-tools:
  - Bash(bash .claude/scripts/jira-ops.sh *)
  - Bash(git log *)
  - Bash(git diff *)
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
---

# Document Fix

Create all documentation artifacts needed to close out the bug fix.

## Process

### Step 1: Update JIRA Ticket

Create `artifacts/quay-bugfix/docs/issue-update.md` with:

- Root cause summary
- Description of the fix and what was changed
- Links to commits, branches, or PRs
- Test coverage added
- Any breaking changes

Transition the ticket:

```bash
bash .claude/scripts/jira-ops.sh transition $TICKET "ON_QA"
```

### Step 2: Create Release Notes Entry

Create `artifacts/quay-bugfix/docs/release-notes.md` with:

- User-facing description of what was fixed
- Impact and who was affected
- Affected versions
- Action required from users
- Clear, non-technical language

### Step 3: Update CHANGELOG

Create `artifacts/quay-bugfix/docs/changelog-entry.md` with:

- Entry following project CHANGELOG conventions
- Placed in Bug Fixes category
- JIRA ticket reference included
- Format: `- Fixed [description] (PROJQUAY-XXXX)`

### Step 4: Create PR Description

Read the PR description template if available:

```bash
cat .claude/templates/pr-description.md 2>/dev/null
```

Create `artifacts/quay-bugfix/docs/pr-description.md` with:

- **Summary**: What this PR does
- **Root Cause / Rationale**: Why the change was needed
- **Changes**: What changed (file references)
- **Test Plan**: How to verify
- **JIRA Link**: `https://issues.redhat.com/browse/<TICKET>`
- **Backport**: Required or not (from assessment)

### Step 5: Technical Communication

Create `artifacts/quay-bugfix/docs/team-announcement.md` with:

- Message for engineering team
- Severity and urgency of deployment
- Testing guidance
- Deployment considerations

### Step 6: User Communication (if user-facing bug)

Create `artifacts/quay-bugfix/docs/user-announcement.md` with:

- Customer-facing announcement
- Non-technical explanation
- Upgrade/mitigation instructions

## Output

All files created in `artifacts/quay-bugfix/docs/`:

1. `issue-update.md` — JIRA comment text
2. `release-notes.md` — Release notes entry
3. `changelog-entry.md` — CHANGELOG addition
4. `pr-description.md` — Pull request description
5. `team-announcement.md` — Internal communication
6. `user-announcement.md` (optional) — Customer communication

## When This Phase Is Done

Report: what documents were created and where.
