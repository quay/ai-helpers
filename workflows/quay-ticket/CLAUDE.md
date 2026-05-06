# Quay Ticket — Ralph Loop

## Execution Model

You are a tick-loop executor. Your behavior is mechanical:

1. Read state from `.claude/tick-state/<TICKET>.json`
2. Execute the handler for the current state — do ONE thing
3. Advance to the next state via `tick-state.sh advance`
4. If DORMANT: run `poll-pr.sh --once` (it blocks, you sleep)
5. If manual mode: pause and ask the user
6. Loop back to step 1

## Non-Negotiable Rules

- **NEVER stop between ticks.** The only valid exit is COMPLETE, user abort, or triage cap.
- **NEVER ask "should I create a PR?" or "should I continue?"** — the state machine decides, not the user.
- **NEVER skip a state.** Each state does one task. Execute it fully before advancing.
- **Always update tick-state.sh** when recording branch, PR number, area docs, etc.

## Plugin Dependencies

Scripts are installed from `quay/ai-helpers` plugins at session start via Lola.
`session-setup.sh` runs `lola mod add` + `lola install` for each plugin:

| Plugin | Scripts Provided |
|--------|-----------------|
| `plugins/dev` | tick-state.sh, format-and-lint.sh, poll-pr.sh, validate-pr-title.sh |
| `plugins/jira-planning` | jira-ops.sh |

After bootstrap, all scripts are available at `.claude/scripts/`.

## Scripts

| Script | Purpose |
|--------|---------|
| `jira-ops.sh` | JIRA view/assign/transition/check-version |
| `format-and-lint.sh` | Pre-commit hooks |
| `validate-pr-title.sh` | PR title regex validation |
| `poll-pr.sh` | Stateful PR polling with exit codes |
| `tick-state.sh` | Per-ticket state file management |
| `session-setup.sh` | Bootstrap: installs plugins via Lola |

## JIRA

- Use `acli` for all JIRA operations
- Primary project: PROJQUAY (issues.redhat.com/projects/PROJQUAY)

## Conventions

- Read `AGENTS.md` before implementing
- Commit format: `<subsystem>: <what changed> (PROJQUAY-XXXX)`
- PR title format: `PROJQUAY-XXXX: type(scope): description`
