# Quay Bugfix Workflow

## Engineering Discipline

- Show code with `file:line` references, not abstractions
- Search the codebase for the complete list of states, phases, or conditions — never assume
- Follow the target project's own CLAUDE.md and AGENTS.md conventions

## Confidence and Escalation

The workflow operates in confidence-gated autonomous mode. Confidence is
assessed per-phase via artifact footers, and the controller reads these to
determine phase advancement.

| Level | Threshold | Action |
|-------|-----------|--------|
| High | >=90% | Advance to next phase automatically |
| Medium | 70-89% | Post JIRA comment with findings and open questions, then advance |
| Low | <70% | Post JIRA comment, stop and escalate via AskUserQuestion |

Escalate when: root cause unclear, multiple valid solutions with different trade-offs, architectural decisions needed, security implications, confidence < 70%.

## Safety

- No direct commits to main/master
- No force-push
- No secret/token logging
- No skipping CI or pre-commit hooks
- Follow Quay's commit format: `<subsystem>: <what changed> (PROJQUAY-XXXX)`
- Follow Quay's PR title regex (validated by `validate-pr-title.sh`)

## Quay Subsystem Map

When diagnosing bugs, understand which subsystem is involved:

| Subsystem | Location | What It Does |
|-----------|----------|--------------|
| API endpoints | `endpoints/` | REST API routes (v1, v2) |
| Data layer | `data/database.py`, `data/model/` | ORM models, business logic |
| Workers | `workers/` | Background job processors |
| Auth | `auth/` | Authentication mechanisms |
| Storage | `storage/` | Blob storage backends |
| Build system | `buildman/` | Container build orchestration |
| Config | `config.py`, `config-tool/` | Configuration and validation |
| Frontend | `web/src/` | React UI (PatternFly) |
| Migrations | `data/migrations/versions/` | Alembic schema migrations |
