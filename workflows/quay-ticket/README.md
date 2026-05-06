# quay-ticket

Ralph Loop tick-loop workflow for single-ticket Quay development on the
[Ambient Code Platform](https://ambient.engineering).

## What it does

Takes a JIRA ticket from assignment to merge-ready PR in one continuous
state machine — no separate skills, no chaining.

**States:** ASSIGN → BRANCH → IMPLEMENT → TEST → COMMIT → PR_CREATE →
DORMANT_CI → ADDRESS_FEEDBACK → DORMANT_REVIEW → COMPLETE

## Usage

```
/work PROJQUAY-XXXX          # full autonomous loop
/work PROJQUAY-XXXX --manual # step through each state
```

## Architecture

This workflow follows the [centralized workflow architecture](../../enhancements/001-workflow-architecture.md).
Scripts are not bundled — they are installed at session start from shared
plugins via [Lola](https://github.com/redhat-ai-tools/lola):

```
.lola-req              # declares plugin dependencies
.ambient/ambient.json  # workflow metadata + envVars
.claude/
  scripts/
    session-setup.sh   # bootstrap: installs plugins via lola
  settings.json        # SessionStart hook for bootstrap
  skills/
    work/SKILL.md      # the /work skill definition
```

### Plugin dependencies

Declared in `.lola-req`:

- **plugins/dev** — tick-state.sh, format-and-lint.sh, poll-pr.sh,
  validate-pr-title.sh, and other dev tooling
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
