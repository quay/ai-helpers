# dev

Ralph Loop development lifecycle plugin. Provides the full ticket-to-merge-ready-PR
workflow as a continuous state machine.

## Skills

| Skill | Purpose |
|-------|---------|
| `/dev:work` | Full tick-loop: assign, branch, implement, test, commit, PR, poll |
| `/dev:start` | Begin work on a JIRA ticket |
| `/dev:code` | Implement changes following project conventions |
| `/dev:pr` | Create PR with validated title and description |
| `/dev:poll` | Stateful PR poller for CI, reviews, and feedback |
| `/dev:ci` | Quick CI status check |
| `/dev:backport` | Trigger cherry-pick robot for backporting |

## Scripts

| Script | Purpose |
|--------|---------|
| `tick-state.sh` | State machine for the /work tick-loop |
| `session-setup.sh` | One-time session bootstrap (acli, pre-commit, gh) |
| `format-and-lint.sh` | Pre-commit hook runner |
| `poll-pr.sh` | Stateful PR poller with adaptive backoff |
| `check-ci.sh` | Quick CI status checker |
| `validate-commit-msg.sh` | Commit message format validation hook |
| `validate-pr-title.sh` | PR title regex validation |
| `enforce-pr-skill.sh` | PR creation convention enforcement hook |
| `save-session-state.sh` | PreCompact state persistence hook |
| `workflow-next-step.sh` | Stop hook suggesting next action |

## Configuration

See `templates/settings.json.template` for the recommended hook configuration.

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `PRIMARY_BRANCH` | `master` | Main branch name |
| `DEFAULT_REPO` | `quay/quay` | GitHub org/repo |
| `PR_TITLE_PATTERN` | PROJQUAY/QUAYIO regex | CI-enforced PR title regex |
| `COMMIT_MESSAGE_PATTERN` | `^[[:alnum:]_/.-]+: .+` | Commit message regex |
| `AMBIENT_SESSION_LABEL` | `ambient-session` | PR label for ambient sessions |
| `REVIEW_TEAM` | `downstream` | GitHub team for review requests |
