# Enhancement 001: Centralized Workflow Architecture

| Field | Value |
|-------|-------|
| **Status** | Draft |
| **Author** | quay-devel |
| **Created** | 2026-05-06 |
| **Dependencies** | [#3](https://github.com/quay/ai-helpers/pull/3) (Konflux plugin), [microsoft/apm](https://github.com/microsoft/apm) |

## Summary

Move Ambient Code Platform (ACP) workflow definitions into `quay/ai-helpers`
alongside the existing plugins. Use [APM](https://github.com/microsoft/apm)
(Agent Package Manager) to compose reusable plugins into per-project workflows.
Project-specific documentation (AGENTS.md, agent_docs/) stays in each source repo.

## Motivation

The quay/quay repo carries a `.claude/` directory with 11 skills, 17 scripts,
8 commands, and project-specific hooks. An audit shows:

| Category | From ai-helpers | Quay-specific | Customized copies |
|----------|----------------|---------------|-------------------|
| Skills | 8 | 2 | 6 of the 8 |
| Scripts | 13 | 3 | 6 of the 13 |
| Commands | 8 | 0 | 0 |

Most "customizations" are just hardcoded values where ai-helpers uses env vars
(JIRA domain, project keys, PR title regex, default repo). The actual logic is
identical.

**Problems this creates:**

1. **No update path.** Bug fixes and improvements to ai-helpers plugins don't
   reach quay. Manual re-copy is error-prone and nobody does it.

2. **Drift.** The quay copies diverge from ai-helpers over time. Six of eight
   shared skills have drifted — mostly by hardcoding values that should be
   env vars.

3. **Coupling.** Agent infrastructure (`.claude/`) is mixed into the
   application repo. It's not part of the product and creates noise in PRs,
   reviews, and CI.

4. **Onboarding friction.** Adding workflows for clair, quay-operator, or
   quay-builder means duplicating the entire `.claude/` setup.

## Why APM

We evaluated two AI package managers:
[Lola](https://github.com/RedHatProductSecurity/lola) (Red Hat) and
[APM](https://github.com/microsoft/apm) (Microsoft). APM was selected for
three reasons:

1. **Lock file.** `apm.lock.yaml` pins every dependency to exact commit SHAs
   with content hashes. Reproducible installs are table stakes for CI-adjacent
   tooling. Lola has no lock file.

2. **Native Claude Code integration.** APM deploys skills, hooks, commands,
   and scripts to `.claude/` natively via its target profile system. Lola only
   manages SKILL.md files — scripts, templates, and commands require custom
   post-install hooks to bridge the gap.

3. **Local path dependencies.** APM supports relative paths
   (`../../plugins/dev`) in `apm.yml` and copies them to `apm_modules/_local/`.
   This is exactly our monorepo layout. Lola's relative path support is
   unverified.

Additional factors: APM ships as a standalone binary (no Python 3.13
requirement), supports 7 primitive types vs Lola's 1, and has broader
community adoption (~2,250 stars vs ~71).

## Design

### Repository Layout

```
quay/ai-helpers/
├── plugins/                            # Reusable APM packages
│   ├── dev/                            # 7 skills, 10 scripts, 2 templates
│   │   ├── apm.yml
│   │   ├── skills/{start,code,pr,poll,ci,backport,work}/
│   │   ├── scripts/
│   │   └── templates/
│   ├── jira-planning/                  # 1 skill, 5 scripts, 8 commands
│   │   ├── apm.yml
│   │   ├── skills/jira/
│   │   ├── scripts/
│   │   └── commands/
│   ├── openshift-testing/              # 2 skills, 2 scripts
│   │   ├── apm.yml
│   │   ├── skills/{cluster-provision,remote-playwright}/
│   │   └── scripts/
│   └── konflux/                        # 1 skill, 1 script
│       ├── apm.yml
│       ├── skills/konflux/
│       └── scripts/
│
├── workflows/                          # Per-project workflow definitions
│   └── quay/                           # ← ACP activeWorkflow.path
│       ├── .claude/
│       │   ├── settings.json           # Hook wiring
│       │   ├── skills/                 # ← populated by apm install
│       │   ├── scripts/               # ← populated by apm install
│       │   ├── commands/              # ← populated by apm install
│       │   └── templates/             # ← populated by apm install
│       ├── apm.yml                     # Plugin dependencies + metadata
│       ├── apm.lock.yaml               # Pinned dependency versions
│       ├── .ambient/
│       │   ├── ambient.json            # ACP metadata + env vars
│       │   └── rubric.md               # Quality rubric
│       ├── CLAUDE.md                   # → @/workspace/repos/quay/AGENTS.md
│       ├── skills/                     # Quay-only skills
│       │   └── pilot-update/SKILL.md
│       └── scripts/                    # Quay-only scripts
│           └── resolve-github-user.sh
│
├── enhancements/                       # This directory
└── README.md
```

### Plugin Manifest (apm.yml)

Each plugin declares its primitives in an `apm.yml`:

```yaml
# plugins/dev/apm.yml
name: quay-dev
version: 0.1.0
description: Ralph Loop development lifecycle for Quay projects
```

APM discovers skills from `skills/*/SKILL.md`, scripts from `scripts/*.sh`,
templates from `templates/*`, and commands from `commands/*.md` within each
package directory. No explicit listing needed.

### Workflow Manifest

`workflows/quay/apm.yml` declares dependencies on the plugins:

```yaml
# workflows/quay/apm.yml
name: quay-workflow
version: 0.1.0
description: ACP workflow for quay/quay

dependencies:
  apm:
    - ../../plugins/dev
    - ../../plugins/jira-planning
    - ../../plugins/openshift-testing
    - ../../plugins/konflux
```

Running `apm install` resolves these local paths, copies plugin content to
`apm_modules/_local/`, and deploys primitives to `.claude/skills/`,
`.claude/commands/`, etc. The `apm.lock.yaml` is generated automatically and
committed to the repo.

### ACP Session Wiring

```yaml
activeWorkflow:
  gitUrl: https://github.com/quay/ai-helpers.git
  branch: main
  path: workflows/quay

repos:
  - url: https://github.com/quay/quay.git
    branch: master
```

At session start:

1. `hydrate.sh` clones ai-helpers, extracts `workflows/quay/` subpath →
   `/workspace/workflows/quay/` (CWD)
2. `hydrate.sh` clones quay/quay → `/workspace/repos/quay/`
3. Claude reads `.claude/settings.json` → discovers hooks
4. `SessionStart` hook runs `session-setup.sh`:
   - Runs `apm install` → installs plugins from `apm.yml`
   - Standard bootstrap (pre-commit, gh auth, etc.)
5. Claude discovers skills, reads `CLAUDE.md` → follows reference to
   `/workspace/repos/quay/AGENTS.md`

### Customization via Environment Variables

Instead of forking skills with hardcoded values, set env vars in
`.ambient/ambient.json`:

| Variable | Value | Used by |
|----------|-------|---------|
| `JIRA_DOMAIN` | `redhat.atlassian.net` | jira-ops.sh, jira skill |
| `JIRA_PROJECTS` | `PROJQUAY,QUAYIO` | detect-jira-ticket.sh |
| `PR_TITLE_PATTERN` | `^(?:PROJQUAY\|QUAYIO\|NO-ISSUE):...` | enforce-pr-skill.sh |
| `DEFAULT_REPO` | `quay/quay` | check-ci.sh, poll-pr.sh |
| `JIRA_TARGET_VERSION_FIELD` | `customfield_10855` | jira-ops.sh |
| `PRIMARY_BRANCH` | `master` | start, pr skills |
| `REVIEW_TEAM` | `@quay/downstream` | poll-pr.sh |

The plugins already support most of these. The remaining hardcoded values
need to be converted to env vars as part of the migration.

### What Stays in quay/quay

| Asset | Reason |
|-------|--------|
| `AGENTS.md` | Documents the codebase — changes with the code |
| `agent_docs/*.md` | Area-specific docs (api, database, testing, etc.) |
| `web/AGENTS.md` | Frontend docs |

These are **code documentation**, not agent infrastructure.

### What Moves to ai-helpers

| Asset | Destination |
|-------|-------------|
| `.claude/settings.json` | `workflows/quay/.claude/settings.json` |
| `.claude/skills/pilot-update/` | `workflows/quay/skills/pilot-update/` |
| `.claude/scripts/resolve-github-user.sh` | `workflows/quay/scripts/` |
| `.claude/user-map.yaml` | `workflows/quay/.claude/user-map.yaml` |
| `.ambient/ambient.json` | `workflows/quay/.ambient/ambient.json` |
| `.ambient/rubric.md` | `workflows/quay/.ambient/rubric.md` |

All shared skills/scripts/commands are **removed** from quay/quay — they're
installed from plugins via APM at session start.

## Migration Plan

### Phase 1: APM manifests for plugins

Add `apm.yml` to each plugin (`dev`, `jira-planning`, `openshift-testing`,
`konflux`). Ensure every project-specific value is externalized via env var
with a sensible default. The six customized skills and six customized scripts
need their hardcoded values replaced.

### Phase 2: Create `workflows/quay/`

1. Create the directory structure shown above
2. Move quay-specific files from quay/quay
3. Create `apm.yml` with local path dependencies to all four plugins
4. Run `apm install` and commit the generated `apm.lock.yaml`
5. Create `CLAUDE.md` with `@/workspace/repos/quay/AGENTS.md` reference
6. Add `apm_modules/` to `.gitignore`

### Phase 3: Validate with ACP session

1. Spin up a test session with `activeWorkflow.path = workflows/quay`
2. Attach quay/quay as a repo
3. Run a full dev cycle: `/start` → `/code` → `/pr` → `/poll`
4. Verify all hooks fire, skills resolve, docs load

### Phase 4: Switch over

1. Update the quay ACP agent config to use ai-helpers as the workflow repo
2. Remove `.claude/` from quay/quay (PR to quay/quay)
3. Update any CI that references `.claude/` paths

### Phase 5: Onboard other projects

```bash
# Example: adding clair
mkdir -p workflows/clair
cd workflows/clair
cat > apm.yml << 'EOF'
name: clair-workflow
version: 0.1.0
dependencies:
  apm:
    - ../../plugins/dev
    - ../../plugins/jira-planning
EOF
cat > CLAUDE.md << 'EOF'
@/workspace/repos/clair/AGENTS.md
EOF
apm install
# Configure ACP: activeWorkflow.path = workflows/clair
```

## Open Questions

1. **hydrate.sh subpath extraction** — When `activeWorkflow.path` is
   `workflows/quay`, does hydrate.sh clone the full ai-helpers repo and use
   the subpath as CWD, or does it sparse-checkout? If the full repo is cloned,
   the `../../plugins/` relative paths in `apm.yml` resolve naturally. If
   only the subpath is extracted, we need git URL syntax instead.

2. **APM binary in runner image** — `apm install` requires the `apm` binary.
   Options: add `apm` to the runner image, or use `pip install apm-cli` in
   session-setup.sh. The standalone binary has no dependencies beyond
   glibc 2.35+.

3. **Git dirty state from apm install** — `apm install` writes to
   `apm_modules/` and deploys files to `.claude/`. Options:
   - Add `apm_modules/` and APM-managed `.claude/` subdirectories to
     `.gitignore` (recommended)
   - Pre-install in CI and commit the result (eliminates runtime dependency)
   - Accept the dirty state (session state is ephemeral)

4. **settings.json hook paths** — Hook commands reference `.claude/scripts/X`.
   After APM installs scripts there, the paths resolve. But if APM fails,
   hooks break. Should session-setup.sh validate the install succeeded?

5. **Lock file with local paths** — `apm.lock.yaml` records local path
   dependencies differently from remote ones. Need to verify the lock file
   is portable across environments where the repo is cloned to different
   absolute paths (it should be, since we use relative paths).

## Benefits

- **Single source of truth** for all agent infrastructure across the quay org
- **Reproducible installs** via `apm.lock.yaml` with commit SHA pinning
- **Automatic updates** — plugin improvements flow to all workflows
- **Clean separation** — code repos carry only code and documentation
- **Native integration** — APM deploys skills, hooks, commands, and scripts
  to `.claude/` without custom post-install scripts
- **Easy onboarding** — new project workflow = directory + `apm.yml` + env vars
- **Composable** — each workflow picks only the plugins it needs
- **Testable** — plugin changes can be tested against all workflows in CI
- **Security** — content scanning, integrity hashes, and optional policy
  enforcement via `apm-policy.yml`
