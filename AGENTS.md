# AGENTS.md

## Plugin script paths

Skills reference scripts using `.claude/scripts/<script-name>.sh` paths.
This is the consumer-facing path after plugin installation — skillsaw
copies plugin scripts from `plugins/<plugin>/scripts/` into
`.claude/scripts/` when a plugin is installed. Skill files (SKILL.md)
must use the installed `.claude/scripts/` path, not the source-level
`plugins/<plugin>/scripts/` path.

Do not use bare relative paths like `scripts/foo.sh` or
`${CLAUDE_PLUGIN_ROOT}/scripts/` in skill definitions.

**Existing deviations:** The `cve` plugin skills (`assess`, `fix-node`)
currently use `${CLAUDE_PLUGIN_ROOT}/scripts/` paths, and the
`debug-playwright` skill co-locates its script in a skill-local
`scripts/` subdirectory with bare relative references. These predate
this convention and should be migrated to `.claude/scripts/` paths.

All scripts for a plugin live in `plugins/<plugin>/scripts/`. The
`.skillsaw.yaml` `agentskill-structure` rule for skill-local `scripts/`
subdirectories is currently disabled; do not co-locate scripts inside
individual skill directories.
