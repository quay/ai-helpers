# quay-bugfix

Systematic bug resolution workflow for Quay on the
[Ambient Code Platform](https://ambient.engineering).

## What it does

Guides you through structured bug investigation and resolution: assess the
JIRA ticket, reproduce the issue, diagnose root cause, implement the fix,
verify with tests, self-review, document, and ship a merge-ready PR.

**Phases:** Assess → Reproduce → Diagnose → Fix → Test → Review → Document →
PR → Summary

## When to use

| Scenario | Workflow |
|----------|----------|
| Bug needs investigation before coding | **quay-bugfix** (this workflow) |
| Well-understood bug, clear fix needed | quay-ticket (Ralph Loop) |
| Feature implementation | quay-ticket (Ralph Loop) |
| Production incident, careful analysis | **quay-bugfix** (this workflow) |

## Usage

Start by providing a JIRA ticket key or describing the bug. The controller
skill guides you through each phase with decision points between them.

The workflow uses **confidence-based gating**: each phase writes a confidence
assessment to its artifact, and the controller advances automatically (high),
posts a JIRA comment then advances (medium), or stops and escalates (low).

## Architecture

This workflow follows the [centralized workflow architecture](../../enhancements/001-workflow-architecture.md).
Scripts are not bundled — they are installed at session start from shared
plugins via [Lola](https://github.com/redhat-ai-tools/lola):

```text
.lola-req              # declares plugin dependencies
.ambient/ambient.json  # workflow metadata + envVars + rubric
.claude/
  scripts/
    session-setup.sh   # bootstrap: installs plugins via lola
  settings.json        # SessionStart hook for bootstrap
  skills/
    controller/        # confidence-gated phase orchestrator
    assess/            # JIRA ticket analysis
    reproduce/         # bug reproduction
    diagnose/          # root cause analysis
    test/              # verification
    review/            # self-review gate
    document/          # release documentation
    summary/           # artifact synthesis
```

Implementation (`/dev:code`), PR creation (`/dev:pr`), and CI polling
(`/dev:poll`) are provided by the dev plugin — not duplicated here.

### Plugin dependencies

Declared in `.lola-req`:

- **plugins/dev** — `/dev:code`, `/dev:pr`, `/dev:poll`, `/dev:ci`,
  `/dev:backport` skills; format-and-lint.sh, poll-pr.sh,
  validate-pr-title.sh, and other dev tooling scripts
- **plugins/jira-planning** — jira-ops.sh and JIRA integration scripts

### Bootstrap

`session-setup.sh` runs as a `SessionStart` hook. It uses `lola mod add`
and `lola install` to install each plugin declared in `.lola-req`. The
plugins' post-install hooks copy scripts and templates into `.claude/scripts/`
and `.claude/templates/`. This is the only script committed directly —
everything else comes from plugins.

## Environment variables

Set in `ambient.json` for Quay-specific configuration:

| Variable | Value |
|----------|-------|
| `JIRA_DOMAIN` | redhat.atlassian.net |
| `JIRA_PROJECTS` | PROJQUAY,QUAYIO |
| `DEFAULT_REPO` | quay/quay |
| `PRIMARY_BRANCH` | master |
| `REVIEW_TEAM` | @quay/downstream |
| `JIRA_TARGET_VERSION_FIELD` | customfield_10855 |
| `PR_TITLE_PATTERN` | CI-enforced regex |
| `COMMIT_MESSAGE_PATTERN` | `^[[:alnum:]_/.-]+: .+` |

## Related

- [Enhancement 002: Quay Bug Fix Workflow](../../enhancements/002-quay-bugfix-workflow.md) — design proposal
- [quay-ticket](../quay-ticket/) — Ralph Loop workflow for general ticket development
