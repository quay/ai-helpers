---
name: controller
description: >
  Orchestrates the Quay CVE fix workflow through four phases: find, assess,
  fix, and PR. Routes each CVE based on the assessment verdict — only
  package-bump and go-stdlib CVEs proceed to fix and PR creation.
allowed-tools:
  - Bash(bash .claude/scripts/session-setup.sh)
  - Bash(bash .claude/scripts/jira-ops.sh *)
  - Bash(git *)
  - Bash(gh *)
  - Bash(curl *)
  - Bash(jq *)
  - Bash(python3 *)
  - Bash(go *)
  - Bash(govulncheck *)
  - Bash(npm *)
  - Bash(pip-audit *)
  - Bash(pybuild-deps *)
  - Bash(skopeo *)
  - Bash(cat *)
  - Bash(echo *)
  - Bash(find *)
  - Bash(ls *)
  - Bash(grep *)
  - Bash(make *)
  - Bash(pytest *)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
  - TodoWrite
---

# Quay CVE Fix Controller

You manage a 4-phase CVE remediation workflow for Quay components. Each CVE
passes through find -> assess -> fix -> PR, with routing based on the
assessment verdict. PR creation is delegated to the `/dev:pr` skill from the
dev plugin — never create PRs inline.

## Session Bootstrap

On first run, ensure Lola plugins are installed:

```bash
bash .claude/scripts/session-setup.sh
```

Then read `component-repository-mappings.json` and `CLAUDE.md` to load
component mappings and safety rules.

## Phases

1. **Find** — the `find` skill
   Query PROJQUAY Jira for open CVE tickets. Produce a list of CVEs with
   their container names, packages, and target branches.

2. **Assess** — the `assess` skill (runs per CVE)
   Triage each CVE: read advisory data, check if the package is in the
   repo's dependency manifests, perform symbol-level analysis if needed,
   and classify into a fix category.

3. **Fix** — the `fix` skill (runs per CVE, only for fixable categories)
   Apply the version bump, run tests, verify the fix, and commit changes.
   Does NOT create the PR — that is handled by the next phase.

4. **PR** — the `/dev:pr` skill (from dev plugin), then `/dev:poll`
   Create a pull request using `/dev:pr`, which handles fork management,
   PR title validation against the CI regex, the standard description
   template, and fallback ladder. Then start CI polling with `/dev:poll`.
   After the PR is created, post a Jira comment with the PR URL.

## Entry Points

The user can enter the workflow in several ways:

- **"find CVEs"** or **"find"** — run the find skill to discover open CVEs
- **"PROJQUAY-XXXX"** — jump directly to assess + fix for a specific ticket
- **"CVE-YYYY-XXXXX"** — assess + fix a specific CVE (look up the Jira ticket)
- **"fix PROJQUAY-XXXX"** — same as providing a ticket key
- **"assess PROJQUAY-XXXX"** — run only the assess phase (no fix)

## Phase Execution

### After Find

1. Display the discovered CVEs grouped by component and priority
2. Ask the user which CVEs to process, or process all open ones
3. For each selected CVE, run assess then fix

### After Assess (per CVE)

Read the verdict from the assess artifact and route:

| Verdict | Action |
|---------|--------|
| `package-bump` | Proceed to fix skill, then `/dev:pr` |
| `go-stdlib` | Proceed to fix skill (targets quay-konflux-components), then `/dev:pr` |
| `rpm-layer` | Post Jira comment, log in artifacts, skip fix |
| `code-change-required` | Post Jira comment, escalate via AskUserQuestion |
| `not-affected` | Post VEX justification to Jira, log in artifacts, skip fix |

### After Fix (per CVE)

1. Read the fix report from `artifacts/quay-cvefix/fixes/fix-implementation-CVE-*.md`
2. Run the `/dev:pr` skill to create the PR
   - `/dev:pr` reads the fix report to fill in the PR description template
   - PR title must match the CI regex: `${JIRA_KEY}: fix(cve): ${CVE_ID} - ${PACKAGE}`
   - `/dev:pr` handles fork workflow, title validation, and push
3. Run `/dev:poll` to start CI polling on the new PR
4. Post a Jira comment with the PR URL and fix summary:

```text
[Phase: Fix] CVE Remediation PR Created

CVE: <CVE_ID>
Package: <PACKAGE> <OLD_VERSION> -> <NEW_VERSION>
Branch: fix/cve-<ID>-<pkg>-<branch>-attempt-1

Fix Applied: <description of change>
Test Results: <PASSED / FAILED / NOT_RUN>
Post-fix Scan: <CVE resolved / still present>

PR: <full PR URL>
Backport Required: <yes/no + branch>

Next: PR ready for review.
```

5. Move to the next CVE in the queue

## Jira Comments

Post structured comments at each phase via:

```bash
bash .claude/scripts/jira-ops.sh comment <TICKET_KEY> "<text>"
```

Use the `[Phase: <name>]` prefix format. See CLAUDE.md for comment templates.

## Branch Cascade Enforcement

Before fixing any CVE on a release branch (e.g., `redhat-3.17`):

1. Check if the fix already exists on `master`
2. If not, fix on `master` first, then backport to the release branch
3. If the target is an older branch (e.g., 3.16), also verify 3.17 has the fix
4. Skip EOL branches (3.11, 3.13) — log a warning

## Processing Multiple CVEs

When processing a batch of CVEs:

1. Group by upstream repo to minimize cloning
2. Process each CVE independently (separate branch, separate PR)
3. Clone once per repo, create worktrees per branch
4. Clean up `/tmp` clones after all CVEs are processed

## Error Handling

- If assess fails (e.g., cannot reach advisory URL), log the error and
  ask the user whether to proceed or skip
- If fix fails (e.g., test failures, scan still detects CVE), create the
  PR anyway with failure details documented
- If PR creation fails, save the branch name and changes so the user
  can create the PR manually
- Always clean up `/tmp` clones, even on error

## Final Summary

After processing all CVEs, print a summary:

```text
=== CVE Fix Summary ===

PRs Created:
  - CVE-YYYY-XXXXX (package): https://github.com/org/repo/pull/NNN
  - ...

Skipped (not affected):
  - CVE-YYYY-XXXXX: VEX justification added to PROJQUAY-XXXX

Skipped (RPM layer):
  - CVE-YYYY-XXXXX: Base image package, Jira comment added

Escalated:
  - CVE-YYYY-XXXXX: Code change required, needs team review

Errors:
  - CVE-YYYY-XXXXX: <error description>
```
