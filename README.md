# quay-ai-helpers

Shared agent toolkit for the Quay organization. Provides reusable coding agent
plugins and skills for JIRA workflow automation, development lifecycle
management, and testing infrastructure.

## Plugins

### dev

The Ralph Loop: a continuous state machine that takes a JIRA ticket from
assignment to merge-ready PR. Includes the full skill chain (`start`, `code`,
`pr`, `poll`, `ci`, `backport`) plus the unified `/work` orchestrator.

### jira

JIRA operations (view, assign, transition, check/set Target Version) and
planning commands for decomposing features into epics, stories, and estimates.
Includes safety hooks for embargoed tickets.

### openshift-testing

Ephemeral OpenShift cluster provisioning via Gangway API and remote Playwright
browser server deployment for E2E testing.

## Installation

### Via Codex Plugin

Codex uses `.codex-plugin/plugin.json` manifests and discovers repo/team
marketplaces from `.agents/plugins/marketplace.json`.

From this repository root:

```bash
codex plugin marketplace add .
```

Then restart Codex, open `/plugins`, select **Quay AI Helpers**, and install
the `dev`, `jira`, or `openshift-testing` plugins.

Codex can also import Claude setup from the Codex app via **Settings -> General
-> Import other agent setup**, but the native Codex marketplace above is the
preferred path for this repo.

#### Codex status

| Asset type | Codex support |
|-----------|---------------|
| Skills (SKILL.md) | Packaged through each plugin's `.codex-plugin/plugin.json` |
| Plugin marketplace | `.agents/plugins/marketplace.json` |
| Scripts (*.sh) | Bundled in plugin directories; several skills still reference `.claude/scripts/` and need path migration |
| Commands (*.md) | Claude-only today; convert important commands to skills for Codex |
| Hooks/settings | Claude `.claude/settings.json` today; convert to Codex `config.toml`/hooks if needed |

### Via Lola (Claude Code)

[Lola](https://github.com/RedHatProductSecurity/lola) is a package manager that
distributes skills across AI assistants. Each plugin in this repo is a
Lola-compatible module; the current Lola hook writes Claude Code project files.

#### One-time setup

```bash
# Install individual plugins
uvx --python 3.13 --from lola-ai lola mod add https://github.com/quay/ai-helpers.git --module-content=plugins/dev
uvx --python 3.13 --from lola-ai lola mod add https://github.com/quay/ai-helpers.git --module-content=plugins/jira
uvx --python 3.13 --from lola-ai lola mod add https://github.com/quay/ai-helpers.git --module-content=plugins/openshift-testing

# Install to your Claude Code project
lola install dev -a claude-code ./my-project
lola install jira -a claude-code ./my-project
```

#### Declarative dependencies

Add a `.lola-req` file to your project root:

```
# .lola-req — AI context modules for this project
https://github.com/quay/ai-helpers.git@main --module-content=plugins/dev
https://github.com/quay/ai-helpers.git@main --module-content=plugins/jira
https://github.com/quay/ai-helpers.git@main --module-content=plugins/openshift-testing
```

Then sync all modules:

```bash
uvx --python 3.13 --from lola-ai lola sync
```

#### What Lola installs for Claude Code

| Asset type | Destination |
|-----------|-------------|
| Skills (SKILL.md) | `.claude/skills/{name}/SKILL.md` |
| Scripts (*.sh) | `.claude/scripts/` (via post-install hook) |
| Templates | `.claude/templates/` (via post-install hook) |
| Commands (*.md) | `.claude/commands/` (via post-install hook) |

#### Updating

```bash
lola mod update dev           # Pull latest from source
lola install dev -a claude-code --force  # Reinstall
```

### Via Claude Plugin

```bash
claude plugin marketplace add quay/ai-helpers
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
├── .agents/
│   └── plugins/marketplace.json # Codex marketplace
├── plugins/
│   ├── dev/                    # Ralph Loop + dev lifecycle
│   │   ├── .codex-plugin/      # Codex plugin metadata
│   │   ├── .claude-plugin/     # Claude plugin metadata
│   │   ├── skills/             # start, code, pr, poll, ci, backport, work
│   │   ├── scripts/            # Shell scripts for hooks and automation
│   │   ├── templates/          # PR description, settings.json template
│   │   └── lola.yaml           # Lola module metadata
│   ├── jira/                   # JIRA ops + planning commands
│   │   ├── skills/             # jira
│   │   ├── scripts/            # jira-ops, embargo checks, etc.
│   │   ├── commands/           # 8 planning commands
│   │   └── lola.yaml           # Lola module metadata
│   └── openshift-testing/      # Cluster + browser testing
│       ├── skills/             # cluster-provision, remote-playwright
│       ├── scripts/            # Provisioning scripts
│       └── lola.yaml           # Lola module metadata
├── scripts/
│   └── lola-post-install.sh    # Shared post-install hook (symlinked by plugins)
├── templates/                  # Starter files for adopting repos
│   ├── AGENTS.md.template
│   └── CLAUDE.md.template
├── docs/                       # Marketplace documentation site
└── Makefile
```

## Adoption Guide

### Codex

1. Add the marketplace: `codex plugin marketplace add .`
2. Restart Codex and install plugins from `/plugins`
3. Use `$work`, `$ticket`, or another installed skill name to invoke workflows
4. For workflows that call helper scripts, migrate `.claude/scripts/...` paths
   to a Codex-compatible script location before relying on them end to end

### Claude Code

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
