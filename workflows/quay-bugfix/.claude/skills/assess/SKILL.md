---
name: assess
description: >
  Understand a Quay bug report from JIRA or GitHub. Fetches ticket details,
  checks for existing work, classifies as UI vs backend, and proposes an
  investigation plan. No code changes.
allowed-tools:
  - Bash(bash .claude/scripts/jira-ops.sh *)
  - Bash(gh issue view *)
  - Bash(gh pr list *)
  - Bash(gh search prs *)
  - Bash(git log *)
  - Read
  - Glob
  - Grep
  - AskUserQuestion
---

# Assess Bug Report

Understand the bug before taking any action. This phase produces an assessment
report — no code execution, no file modifications.

## Your Role

Read the bug report, present your understanding back to the user, identify
gaps, and propose a plan. Let the user correct you before you invest effort
in the wrong direction.

## Critical Rules

- **Do not start reproducing, diagnosing, or fixing.** Analysis and planning only.
- **Do not run the project's code or tests.** You may read code, but do not
  execute it yet.
- **Be honest about uncertainty.** If the report is vague, say so.

## Process

### Step 1: Gather the Bug Report

Accept either a JIRA ticket key, a GitHub issue URL, or a free-text
description from the user.

**For JIRA tickets:**

```bash
bash .claude/scripts/jira-ops.sh view $TICKET
```

Extract: summary, description, type, component, priority, labels, comments,
reporter, attachments.

**For GitHub issues:**

```bash
gh issue view NUMBER --repo ${DEFAULT_REPO:-quay/quay} --json title,body,labels,comments,state
```

**For free-text descriptions:** Use the conversation context directly.

### Step 2: Ensure the Repository Is Available

```bash
ls /workspace/repos/ 2>/dev/null
```

If the project repo is present (e.g., `/workspace/repos/quay/`), note its
path. If not, clone it:

```bash
gh repo clone ${DEFAULT_REPO:-quay/quay} /workspace/repos/quay
```

Read referenced files or code paths to inform the assessment. This is
read-only exploration.

### Step 3: Check for Existing Work

Search for PRs or related issues that may already address this bug:

```bash
gh pr list --search "$TICKET" --state all --repo ${DEFAULT_REPO:-quay/quay} --json number,title,headRefName --jq '.[] | "\(.number)\t\(.title)"'
gh search prs "$TICKET" --repo ${DEFAULT_REPO:-quay/quay}
```

If an open PR appears to directly address this bug, **stop and use
`AskUserQuestion`** before continuing. Present options:

- "PR #N appears to address this bug — review it instead of starting fresh"
- "PR #N is related but doesn't fully cover it — continue with assessment"
- "Not sure if PR #N is relevant — continue with assessment"

This gate applies in both normal and speedrun mode. Do not continue until the
user responds.

### Step 4: Check Backport Requirement

```bash
bash .claude/scripts/jira-ops.sh check-version $TICKET
```

If Target Version is set, note that backporting will be required after merge.

### Step 5: Classify the Bug

Determine whether this is a **UI bug** or **Backend bug**:

**UI indicators:** component is `ui` or `web`; keywords like rendering,
display, button, form, modal, PatternFly, React; screenshot attachments.

**Backend indicators:** component is `api`, `data`, `auth`, `workers`,
`storage`, `buildman`; keywords like endpoint, database, migration, worker,
ORM; log file or stack trace attachments.

### Step 6: Summarize Understanding

Present to the user:

- **What the bug is:** One or two sentences describing the problem
- **Where it occurs:** Which Quay subsystem is affected (use the subsystem
  map from CLAUDE.md)
- **Severity/impact:** Based on JIRA priority and your assessment
- **Available information:** What the report provides
- **Gaps:** What's missing or unclear
- **Assumptions:** Any assumptions you're making

### Step 7: Propose Investigation Plan

Based on your understanding, outline:

- What environment or setup is needed for reproduction
- What specific steps you would follow
- What you would look for to confirm the bug exists
- Which Quay subsystems to investigate during diagnosis

### Step 8: Write Assessment Artifact

Save to `artifacts/quay-bugfix/reports/assessment.md`:

```markdown
# Bug Assessment: <TICKET>

## Summary
<One-paragraph understanding of the bug>

## Classification
- **Type:** UI / Backend
- **Subsystem:** <from CLAUDE.md subsystem map>
- **Severity:** <from JIRA priority>
- **Component:** <JIRA component>

## Existing Work
<Any related PRs, issues, or prior fixes found — or "None found">

## Available Information
- <what the report provides>

## Gaps
- <what's missing or unclear>

## Assumptions
- <any assumptions being made>

## Proposed Investigation Plan
1. Reproduce: <specific steps>
2. Diagnose: <subsystems and code areas to investigate>
3. Fix approach: <initial hypothesis, if any>

## Backport Required
<Yes/No — based on Target Version field>
```

## Output

- Assessment presented directly to the user (inline)
- Assessment saved to `artifacts/quay-bugfix/reports/assessment.md`
- No code is executed, no files in the project are modified

## When This Phase Is Done

Report your assessment: understanding, gaps, plan, and backport status.
