# Enhancement 002: Quay Bug Fix Workflow

| Field | Value |
|-------|-------|
| **Status** | Draft |
| **Author** | quay-devel |
| **Created** | 2026-05-07 |
| **Dependencies** | [#2](https://github.com/quay/ai-helpers/pull/2) (Ralph Loop workflow), Enhancement 001 (Centralized Workflow Architecture), [ambient-code/workflows](https://github.com/ambient-code/workflows) (bugfix workflow reference) |

## Summary

Add a bug-specific investigation workflow (`workflows/quay-bugfix/`) that
combines Ambient's phase-gated investigation discipline with Quay's existing
plugin infrastructure. The workflow adds structured assess, reproduce, and
diagnose phases before handing off to Quay's execution tooling for fix,
test, and PR creation.

## Motivation

Quay has two modes for working JIRA tickets today:

1. **Ralph Loop** (`workflows/quay-ticket/`) — a tick-loop state machine
   that drives a ticket from ASSIGN to COMPLETE in one continuous loop.
   Optimized for execution throughput.

2. **Planning commands** (`/create-plan-from-issue`) — a JIRA-based planning
   tool that classifies issues and creates todo lists, but doesn't enforce
   a structured investigation process.

Neither is designed for bugs that need investigation before coding. The Ralph
Loop's "never stop between ticks" discipline assumes the developer already
understands what to fix. The planning command creates a todo list but doesn't
gate execution on understanding.

**Problems this creates:**

1. **Premature coding.** Complex bugs get ASSIGN → BRANCH → IMPLEMENT
   immediately. Without reproduction or root cause analysis, the first fix
   attempt often addresses symptoms instead of causes.

2. **No investigation artifacts.** When a fix attempt fails, there's no
   written record of what was tried, what was learned, or why the first
   hypothesis was wrong. The next attempt starts from scratch.

3. **Missing self-review.** Ralph Loop has no review gate between
   implementation and PR creation. The fix goes straight to CI, where
   failures are more expensive to debug than a pre-PR self-review.

4. **No documentation generation.** Bug fixes often need release notes,
   changelog entries, and JIRA updates. Ralph Loop produces a PR but not
   the surrounding documentation.

### Reference: Ambient's Bugfix Workflow

The [ambient-code/workflows](https://github.com/ambient-code/workflows)
repository contains a generic `bugfix` workflow that addresses all four
problems with a 9-phase, skill-based, phase-gated architecture:

| Phase | Purpose |
|-------|---------|
| Assess | Understand the bug report, check for existing work |
| Reproduce | Confirm the bug exists and document reproduction |
| Diagnose | Root cause analysis and impact assessment |
| Fix | Implement the minimal correct fix |
| Test | Regression tests + full suite verification |
| Review | Self-review gate with verdict |
| Document | Release notes, changelog, JIRA updates |
| PR | Create pull request |
| Summary | Synthesize all artifacts |

Key architectural patterns:
- **Controller skill** orchestrates phase transitions
- **Hard gates** (`AskUserQuestion`) between every phase — never auto-advance
- **Artifact-based state** — each phase writes to `artifacts/bugfix/`
- **Speedrun mode** — runs remaining phases without stopping for unattended use
- **Escalation rules** — stops when confidence < 80% or root cause unclear

This workflow is generic (project-agnostic). The proposal adapts it for Quay.

## Design

### Workflow Position

The quay-bugfix workflow is complementary to Ralph Loop, not a replacement:

| Scenario | Workflow |
|----------|----------|
| Well-understood bug, clear fix | Ralph Loop (`/work PROJQUAY-XXXX`) |
| Bug needs investigation before coding | Quay Bugfix (this workflow) |
| Feature implementation | Ralph Loop |
| Production incident, careful analysis needed | Quay Bugfix |
| Simple chore or dependency update | Ralph Loop |

### Capability Comparison

| Capability | Ambient bugfix | Quay Ralph Loop | Quay bugfix (proposed) |
|------------|:-:|:-:|:-:|
| Structured assessment | Yes | No | Yes |
| Systematic reproduction | Yes | No | Yes |
| Root cause diagnosis | Yes | No | Yes |
| Self-review gate | Yes | No | Yes |
| JIRA integration | No | Yes | Yes |
| CI polling / feedback loops | No | Yes | Yes |
| PR title/commit validation | No | Yes | Yes |
| Release documentation | Yes | Partial | Yes |
| Quay subsystem awareness | No | Yes | Yes |
| Backport detection | No | Yes | Yes |
| Resumable after disconnect | Yes | Yes | Yes |
| Speedrun / unattended mode | Yes | Yes | Yes |
| Rubric self-scoring | No | Yes | Yes |

### Directory Layout

```
workflows/quay-bugfix/
├── .ambient/
│   └── ambient.json              # ACP metadata, env vars, rubric
├── .claude/
│   ├── scripts/
│   │   └── session-setup.sh      # Bootstrap (plain copy from scripts/)
│   └── skills/
│       ├── controller/SKILL.md   # Phase orchestrator
│       ├── speedrun/SKILL.md     # Unattended execution
│       ├── assess/SKILL.md       # Phase 1: Understand the bug
│       ├── reproduce/SKILL.md    # Phase 2: Reproduce it
│       ├── diagnose/SKILL.md     # Phase 3: Root cause analysis
│       ├── fix/SKILL.md          # Phase 4: Implement fix
│       ├── test/SKILL.md         # Phase 5: Verify fix
│       ├── review/SKILL.md       # Phase 6: Self-review gate
│       ├── document/SKILL.md     # Phase 7: Release docs
│       ├── pr/SKILL.md           # Phase 8: Create PR
│       └── summary/SKILL.md      # Phase 9: Synthesize results
├── .lola-req                     # Pulls in dev + jira-planning plugins
├── CLAUDE.md                     # Quay-specific engineering discipline
└── README.md                     # Usage documentation
```

### How It Adapts the Ambient Pattern for Quay

| Ambient (generic) | Quay bugfix (adapted) |
|--------------------|-----------------------|
| Reads GitHub issue | Reads JIRA ticket via `jira-ops.sh`, downloads attachments, classifies UI vs backend |
| Generic env setup | Quay-specific: `make local-dev-up`, Playwright for UI, pytest for backend |
| Generic code tracing | Subsystem-aware: knows `endpoints/`, `data/model/`, `workers/`, `buildman/`, `web/src/` |
| Generic branch + implement | Quay commit format, `format-and-lint.sh`, AGENTS.md conventions |
| Generic test runner | `make unit-test`, `make registry-test`, Cypress for UI |
| Fork-based PR with fallback | Quay PR title regex, JIRA link, ambient session label, `poll-pr.sh` |
| Artifact-based state only | Artifacts for investigation, tick-state available for execution |
| No JIRA lifecycle | Transitions: New → ASSIGNED → POST → ON_QA |
| No backport | Detects via Target Version, suggests `/dev:backport` at completion |
| No rubric | Self-scoring on investigation quality, fix correctness, test coverage, documentation |

### Plugin Reuse via Lola

The workflow reuses existing plugins — no script duplication:

`.lola-req`:

```
https://github.com/quay/ai-helpers.git@main --module-content=plugins/dev
https://github.com/quay/ai-helpers.git@main --module-content=plugins/jira-planning
```

Scripts available after `lola sync`:

| Script | Source Plugin | Used By Phase |
|--------|-------------|---------------|
| `jira-ops.sh` | jira-planning | Assess, Fix, Document |
| `format-and-lint.sh` | dev | Fix, Test |
| `validate-pr-title.sh` | dev | PR |
| `poll-pr.sh` | dev | PR |
| `tick-state.sh` | dev | Available if needed |

### Artifact Organization

```
artifacts/quay-bugfix/
├── reports/
│   ├── assessment.md             # Phase 1: bug understanding
│   └── reproduction.md           # Phase 2: reproduction results
├── analysis/
│   └── root-cause.md             # Phase 3: root cause diagnosis
├── fixes/
│   └── implementation-notes.md   # Phase 4: what changed and why
├── tests/
│   └── verification.md           # Phase 5: test results
├── review/
│   └── verdict.md                # Phase 6: adequate / incomplete / inadequate
├── docs/
│   ├── release-notes.md          # Phase 7: release notes entry
│   ├── changelog-entry.md        # Phase 7: changelog addition
│   └── pr-description.md         # Phase 7: PR body text
└── summary.md                    # Phase 9: synthesized overview
```

Artifacts enable:
- **Resumption** — if a session disconnects, the next session reads artifacts
  to determine what's already done
- **Speedrun** — checks artifact existence to skip completed phases
- **Audit trail** — investigation artifacts persist alongside the PR

### Controller and Phase Gating

The controller skill manages phase transitions with hard gates:

```
Phase 1 (assess) → [GATE: AskUserQuestion] → Phase 2 (reproduce) → [GATE] → ...
```

After each phase, the controller:
1. Announces the completed phase
2. Recommends the next step with alternatives
3. Waits for explicit user input via `AskUserQuestion`
4. Never auto-advances

This prevents the premature-coding problem. The user must actively choose
to proceed past investigation before any code is written.

### Speedrun Mode

For unattended execution (e.g., overnight bug fixes), the speedrun skill
runs remaining phases without stopping. It:
- Checks for existing artifacts to determine next incomplete phase
- Executes phases sequentially without waiting
- Still respects escalation rules (confidence < 80%, security concerns)
- Attempts one review-fix-test cycle if review says "inadequate"

### Rubric

```json
{
  "investigation_quality": "Were phases 1-3 done thoroughly before coding? (1-5)",
  "fix_correctness": "Does fix address root cause, handle all states, follow conventions? (1-5)",
  "test_coverage": "Regression test fails without fix/passes with it, full suite passes? (1-5)",
  "documentation": "PR description, release notes, JIRA updates complete and accurate? (1-5)"
}
```

The rubric emphasizes investigation quality as the primary differentiator
from Ralph Loop.

### Environment Variables

Reuses the same env vars as `quay-ticket`:

| Variable | Value | Used By |
|----------|-------|---------|
| `JIRA_DOMAIN` | `redhat.atlassian.net` | jira-ops.sh |
| `JIRA_PROJECTS` | `PROJQUAY,QUAYIO` | JIRA ticket detection |
| `DEFAULT_REPO` | `quay/quay` | GitHub searches, PR creation |
| `PRIMARY_BRANCH` | `master` | Branch creation, PR base |
| `REVIEW_TEAM` | `@quay/downstream` | PR review requests |
| `JIRA_TARGET_VERSION_FIELD` | `customfield_10855` | Backport detection |
| `PR_TITLE_PATTERN` | CI-enforced regex | PR title validation |
| `COMMIT_MESSAGE_PATTERN` | `^[[:alnum:]_/.-]+: .+` | Commit validation |

## Why Not Extend Ralph Loop?

The Ralph Loop's tick-loop model and phase-gated investigation are
architecturally incompatible:

| Dimension | Ralph Loop | Phase-Gated Investigation |
|-----------|------------|--------------------------|
| Execution discipline | Never stop between ticks | Hard gate between every phase |
| User interaction | Only in manual mode (optional) | Required between all phases |
| Phase ordering | Fixed state machine | User can skip, reorder, re-run |
| Optimization target | Throughput | Correctness |
| State model | JSON file with transitions | Markdown artifacts per phase |

Adding investigation phases to the tick-loop would either:
- **Break "never stop" discipline** — investigation needs user confirmation
  points, which contradicts the tick-loop's core principle
- **Lose investigation value** — if phases auto-advance like tick states,
  there's no gate to prevent premature coding

Two complementary workflows serve both modes better than one hybrid that
compromises on both.

## Alternatives Considered

### Extend `/create-plan-from-issue`

The planning command already classifies bugs and creates todo lists. We
could add reproduction and diagnosis steps to it.

**Rejected because:** Planning commands produce a plan but don't enforce
execution. Nothing prevents skipping straight to implementation. The
phase-gated controller pattern enforces the investigation sequence.

### Add investigation ticks to Ralph Loop

Insert ASSESS, REPRODUCE, DIAGNOSE states before IMPLEMENT in the tick-loop.

**Rejected because:** Investigation states need user confirmation gates,
which contradicts the tick-loop's "never stop between ticks" rule. Manual
mode partially solves this but makes investigation optional, not enforced.

### Use Ambient's generic bugfix workflow directly

Point Quay at the ambient-code/workflows bugfix workflow without adaptation.

**Rejected because:** The generic workflow lacks JIRA integration, Quay
subsystem awareness, commit/PR conventions, CI polling, and backport
detection. These are not optional for Quay development.

## Implementation Plan

### Phase 1: Enhancement Review

Submit this enhancement for team review. Align on:
- Workflow scope (which phases to include)
- Skill boundaries (how much to adapt vs. copy from Ambient)
- Naming (`quay-bugfix` vs `quay-bug` vs `quay-investigate`)

### Phase 2: Scaffold

1. Create `workflows/quay-bugfix/` directory structure
2. Create `.ambient/ambient.json` with metadata, env vars, rubric
3. Create `.lola-req` referencing dev + jira-planning plugins
4. Copy `session-setup.sh` bootstrap script
5. Create `CLAUDE.md` with Quay engineering discipline

### Phase 3: Core Skills

Implement skills in priority order:

1. **controller** — phase orchestrator (gates everything)
2. **assess** — JIRA ticket analysis (depends on jira-ops.sh)
3. **diagnose** — root cause analysis (Quay subsystem-aware)
4. **fix** — implementation (bridges to Quay plugins)
5. **test** — verification (Quay test patterns)
6. **reproduce** — bug reproduction (Quay dev environment)
7. **review** — self-review gate
8. **pr** — PR creation (delegates to Quay PR conventions)
9. **document** — release documentation
10. **summary** — artifact synthesis
11. **speedrun** — unattended execution

### Phase 4: Validate

Test with ACP's "Custom Workflow" feature:
- URL: `https://github.com/quay/ai-helpers.git`
- Branch: feature branch
- Path: `workflows/quay-bugfix`

Run against 3-5 real JIRA bugs of varying complexity.

### Phase 5: Iterate and Ship

Refine skills based on validation results. Merge to main. The workflow
becomes automatically discoverable in ACP.

## Open Questions

1. **Naming** — `quay-bugfix` vs `quay-bug` vs `quay-investigate`. The name
   appears in the ACP workflow picker. "Fix a Quay Bug" mirrors Ambient's
   "Fix a bug" naming.

2. **Reproduce phase feasibility** — Quay's local dev environment setup is
   non-trivial (`make local-dev-up` requires Docker, database, Redis, etc.).
   Should the reproduce phase attempt full environment setup, or focus on
   code-level reproduction (unit tests, targeted scripts)?

3. **Speedrun as default?** — Ralph Loop runs autonomously by default with
   manual mode as an option. Should quay-bugfix default to controller
   (interactive) or speedrun (autonomous)? The Ambient reference defaults
   to controller.

4. **Shared skill extraction** — Several skills (review, summary, speedrun)
   are project-agnostic. Should they become a shared plugin (e.g.,
   `plugins/investigation/`) that other project workflows can reuse?

## Benefits

- **Investigation before coding** — structured phases prevent premature fixes
- **Artifacts for continuity** — investigation state persists across sessions
- **Self-review gate** — catches issues before CI, reducing feedback cycles
- **Documentation automation** — release notes and JIRA updates generated
- **Aligned with Ambient** — follows the platform's reference architecture
- **Plugin reuse** — leverages existing Quay scripts via Lola
- **Complementary** — doesn't replace Ralph Loop, serves a different need
- **Rubric-scored** — investigation quality is measurable and improvable
