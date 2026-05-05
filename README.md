# quay-ai-helpers

Shared agent toolkit for the Quay organization. Provides reusable Claude Code
plugins for JIRA workflow automation, development lifecycle management, and
testing infrastructure.

## Plugins

### dev

The Ralph Loop: a continuous state machine that takes a JIRA ticket from
assignment to merge-ready PR. Includes the full skill chain (`start`, `code`,
`pr`, `poll`, `ci`, `backport`) plus the unified `/work` orchestrator.

### jira-planning

JIRA operations (view, assign, transition, check/set Target Version) and
planning commands for decomposing features into epics, stories, and estimates.
Includes safety hooks for embargoed tickets.

### openshift-testing

Ephemeral OpenShift cluster provisioning via Gangway API and remote Playwright
browser server deployment for E2E testing.

## Installation

```bash
claude plugin add quay/ai-helpers
```

## Configuration

All project-specific values are set via environment variables with Quay defaults.
See each plugin's README for the full variable list.

### Core Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `JIRA_DOMAIN` | `redhat.atlassian.net` | JIRA instance |
| `PRIMARY_BRANCH` | `master` | Main branch name |
| `DEFAULT_REPO` | `quay/quay` | GitHub org/repo |
| `PR_TITLE_PATTERN` | PROJQUAY/QUAYIO regex | CI-enforced PR title regex |
| `JIRA_TARGET_VERSION_FIELD` | `customfield_10855` | Target Version field ID |

### Hook Setup

Copy `plugins/dev/templates/settings.json.template` to your project's
`.claude/settings.json` and adjust script paths to reference the plugin install
location.

## Project Structure

```
ai-helpers/
├── plugins/
│   ├── dev/           # Ralph Loop + dev lifecycle
│   │   ├── skills/             # start, code, pr, poll, ci, backport, work
│   │   ├── scripts/            # Shell scripts for hooks and automation
│   │   ├── templates/          # PR description, settings.json template
│   │   └── hooks/              # Event hooks
│   ├── jira-planning/          # JIRA ops + planning commands
│   │   ├── skills/             # jira
│   │   ├── scripts/            # jira-ops, embargo checks, etc.
│   │   └── commands/           # 8 planning commands
│   └── openshift-testing/      # Cluster + browser testing
│       ├── skills/             # cluster-provision, remote-playwright
│       └── scripts/            # Provisioning scripts
├── templates/                  # Starter files for adopting repos
│   ├── AGENTS.md.template
│   └── CLAUDE.md.template
├── docs/                       # Marketplace documentation site
├── scripts/                    # Build tooling
└── Makefile
```

## Adoption Guide

1. Install the plugin: `claude plugin add quay/ai-helpers`
2. Set project-specific env vars in your `.claude/settings.json` or shell profile
3. Copy `templates/AGENTS.md.template` to create your project's `AGENTS.md`
4. Copy `plugins/dev/templates/settings.json.template` for hook configuration
5. Use `/dev:work PROJQUAY-XXXX` to run the full development lifecycle

## Development

```bash
make lint          # Validate plugin structure
make update        # Regenerate docs
make new-plugin NAME=foo  # Create a new plugin
```

## License

MIT
