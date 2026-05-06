# Enhancement 001: Centralized Workflow Architecture

| Field | Value |
|-------|-------|
| **Status** | Draft |
| **Author** | quay-devel |
| **Created** | 2026-05-06 |
| **Dependencies** | [#3](https://github.com/quay/ai-helpers/pull/3) (Konflux plugin), [#4](https://github.com/quay/ai-helpers/pull/4) (Lola support), [RedHatProductSecurity/lola](https://github.com/RedHatProductSecurity/lola) |

## Summary

Move Ambient Code Platform (ACP) workflow definitions into `quay/ai-helpers`
alongside the existing plugins. Use [Lola](https://github.com/RedHatProductSecurity/lola)
to compose reusable plugins into per-project workflows. Project-specific
documentation (AGENTS.md, agent_docs/) stays in each source repo.

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

## Design

### Repository Layout

```
quay/ai-helpers/
├── plugins/                            # Reusable Lola modules
│   ├── dev/                            # 7 skills, 10 scripts, 2 templates
│   ├── jira-planning/                  # 1 skill, 5 scripts, 8 commands
│   ├── openshift-testing/              # 2 skills, 2 scripts
│   └── konflux/                        # 1 skill, 1 script
│
├── workflows/                          # Per-project workflow definitions
│   └── quay/                           # ← ACP activeWorkflow.path
│       ├── .claude/
│       │   ├── settings.json           # Hook wiring
│       │   ├── skills/                 # ← populated by lola sync
│       │   ├── scripts/               # ← populated by lola sync
│       │   ├── commands/              # ← populated by lola sync
│       │   └── templates/             # ← populated by lola sync
│       ├── .lola-req                   # Plugin dependencies
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
├── scripts/
│   └── lola-post-install.sh            # Shared Lola post-install hook
└── README.md
```

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
   - Runs `uvx --python 3.13 --from lola-ai lola sync` → installs plugins
   - Standard bootstrap (pre-commit, gh auth, etc.)
5. Claude discovers skills, reads `CLAUDE.md` → follows reference to
   `/workspace/repos/quay/AGENTS.md`

### Plugin Composition

`workflows/quay/.lola-req`:

```
# Plugins installed at session start
../../plugins/dev
../../plugins/jira-planning
../../plugins/openshift-testing
../../plugins/konflux
```

Lola installs SKILL.md files to `.claude/skills/` and post-install hooks
([#4](https://github.com/quay/ai-helpers/pull/4)) copy scripts, templates,
and commands to their expected `.claude/` locations.

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
installed from plugins via Lola at session start.

## Migration Plan

### Phase 1: Env var portability

Audit all plugins and ensure every project-specific value is externalized via
env var with a sensible default. The six customized skills and six customized
scripts need their hardcoded values replaced.

### Phase 2: Create `workflows/quay/`

1. Create the directory structure shown above
2. Move quay-specific files from quay/quay
3. Create `.lola-req` referencing all four plugins
4. Create `CLAUDE.md` with `@/workspace/repos/quay/AGENTS.md` reference
5. Verify `lola sync` installs all plugins correctly

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
mkdir -p workflows/clair/.claude
cat > workflows/clair/.lola-req << 'EOF'
../../plugins/dev
../../plugins/jira-planning
EOF
cat > workflows/clair/CLAUDE.md << 'EOF'
@/workspace/repos/clair/AGENTS.md
EOF
# Configure ACP: activeWorkflow.path = workflows/clair
```

## Open Questions

1. **hydrate.sh subpath extraction** — When `activeWorkflow.path` is
   `workflows/quay`, does hydrate.sh clone the full ai-helpers repo and use
   the subpath as CWD, or does it sparse-checkout? If the full repo is cloned,
   the `../../plugins/` relative paths in `.lola-req` resolve naturally. If
   only the subpath is extracted, we need git URL syntax instead.

2. **Python 3.13 in runner image** — Lola requires Python 3.13. Current
   sessions have `uvx` available which can auto-fetch it. Need to confirm this
   works reliably in the runner image, or add Python 3.13 to the image.

3. **Lola relative path support** — Verify that `.lola-req` supports relative
   local paths (`../../plugins/dev`). Fallback: use git URLs with
   `--module-content` syntax.

4. **Git dirty state from lola sync** — `lola sync` writes files to `.claude/`
   at runtime, creating uncommitted changes. Options:
   - Add `.claude/skills/`, `.claude/scripts/`, `.claude/commands/`,
     `.claude/templates/` to `.gitignore`
   - Accept the dirty state (session state is ephemeral)
   - Pre-install in CI and commit the result (eliminates runtime dependency)

5. **settings.json hook paths** — Hook commands reference `.claude/scripts/X`.
   After Lola installs scripts there, the paths resolve. But if Lola fails,
   hooks break. Should session-setup.sh validate the install succeeded?

## Benefits

- **Single source of truth** for all agent infrastructure across the quay org
- **Automatic updates** — plugin improvements flow to all workflows
- **Clean separation** — code repos carry only code and documentation
- **Easy onboarding** — new project workflow = directory + `.lola-req` + env vars
- **Composable** — each workflow picks only the plugins it needs
- **Testable** — plugin changes can be tested against all workflows in CI
