# quay-cvefix

Automated CVE remediation workflow for Quay components on the
[Ambient Code Platform](https://ambient.engineering).

## What it does

Discovers CVE tickets in PROJQUAY Jira, triages each one by consulting
advisories and analyzing source code impact, then creates fix PRs for
vulnerabilities that can be resolved with dependency bumps.

**Phases:** Find → Assess → Fix

## When to use

| Scenario | Workflow |
|----------|----------|
| CVE ticket needs a dependency bump | **quay-cvefix** (this workflow) |
| CVE needs code changes or investigation | quay-bugfix |
| Non-security bug fix | quay-bugfix or quay-ticket |
| Feature implementation | quay-ticket (Ralph Loop) |

## Usage

Start by providing a JIRA ticket key, a CVE ID, or ask to find all open
CVEs. The controller skill guides you through each phase.

```text
# Fix a specific ticket
PROJQUAY-12345

# Find all open CVEs for Quay
find

# Assess a CVE without fixing
assess PROJQUAY-12345
```

## Architecture

This workflow follows the
[centralized workflow architecture](../../enhancements/001-workflow-architecture.md).
Scripts are installed at session start from shared plugins via
[Lola](https://github.com/redhat-ai-tools/lola):

```text
.lola-req              # declares plugin dependencies
.ambient/ambient.json  # workflow metadata + envVars
.claude/
  scripts/
    session-setup.sh   # bootstrap: installs plugins via lola
  settings.json        # SessionStart hook for bootstrap
  skills/
    controller/        # find -> assess -> fix orchestrator
    find/              # Jira CVE discovery
    assess/            # CVE triage + advisory analysis
    fix/               # apply fix + create PR
component-repository-mappings.json  # container-to-repo mapping
CLAUDE.md              # safety guardrails
```

### Plugin dependencies

Declared in `.lola-req`:

- **plugins/dev** — `/dev:code`, `/dev:pr`, format-and-lint.sh, and dev
  tooling scripts
- **plugins/jira-planning** — jira-ops.sh and JIRA integration scripts

## CVE Fix Types

| Type | Where Fixed | Strategy |
|------|-------------|----------|
| Python dependency | quay/quay | Bump in requirements.txt, regenerate requirements-build.txt with pybuild-deps |
| Go dependency | upstream repo | `go get` + `go mod tidy` |
| Go stdlib | quay-konflux-components | Bump go-toolset image tag in Containerfile |
| Node.js dependency | quay/quay | `npm update` or npm overrides |

## Assessment Verdicts

| Verdict | Action | PR? |
|---------|--------|-----|
| `package-bump` | Apply version bump | Yes |
| `go-stdlib` | Bump go-toolset in Konflux | Yes |
| `rpm-layer` | Comment on Jira, skip | No |
| `code-change-required` | Escalate to team | No |
| `not-affected` | VEX justification on Jira | No |

## Component Mapping

The workflow maps Jira container names to upstream repos via
`component-repository-mappings.json`:

| Container | Upstream Repo | Languages |
|-----------|---------------|-----------|
| quay/quay-rhel8, quay/quay-rhel9 | quay/quay | Python, Node.js, Go |
| quay/clair-rhel8, quay/clair-rhel9 | quay/clair | Go |
| quay/quay-operator-rhel8, -rhel9 | quay/quay-operator | Go |
| quay/quay-bridge-operator-rhel8, -rhel9 | quay/quay-bridge-operator | Go |
| quay/quay-builder-rhel8, -rhel9 | quay/quay-builder | Go |
| quay/quay-builder-qemu-rhcos-rhel8 | quay/quay-builder-qemu | Go |
| quay/quay-container-security-operator-* | quay/container-security-operator | Go |
| openshift/mirror-registry-rhel8 | quay/mirror-registry | Go |

## Branch Rules

- Fixes must exist on `master` before being applied to release branches
- Branch `[quay-X.Y]` in the Jira summary indicates the target
- Branches 3.11 and 3.13 are EOL — skipped automatically
- Each branch gets a separate PR

## Environment variables

Set in `ambient.json`:

| Variable | Value |
|----------|-------|
| `JIRA_DOMAIN` | redhat.atlassian.net |
| `JIRA_PROJECTS` | PROJQUAY |
| `KONFLUX_REPO` | quay/quay-konflux-components |
| `PRIMARY_BRANCH` | master |
| `REVIEW_TEAM` | @quay/downstream |

## Artifacts

```text
artifacts/quay-cvefix/
├── find/            # Jira CVE issue lists
├── assess/          # Per-CVE triage reports
└── fixes/           # Fix implementations, test results, PR summaries
    └── test-results/
```

## Related

- [quay-bugfix](../quay-bugfix/) — structured bug investigation workflow
- [quay-ticket](../quay-ticket/) — Ralph Loop for general ticket work
- [Enhancement 001](../../enhancements/001-workflow-architecture.md) — centralized architecture
