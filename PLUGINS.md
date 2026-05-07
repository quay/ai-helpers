# Available Plugins

This document lists all available Claude Code plugins and their commands in the ai-helpers repository.

- [Dev](#dev-plugin)
- [Jira Planning](#jira-planning-plugin)
- [Openshift Testing](#openshift-testing-plugin)

### Dev Plugin

Ralph Loop development lifecycle: ticket assignment through merge-ready PR. Includes start, code, pr, poll, ci, backport, and the unified /work orchestrator.

**Skills:**
- **`/dev:backport`** - Trigger the cherry-pick robot to backport a merged PR to a release branch. Checks Target Version from JIRA if no branch is specified.
- **`/dev:ci`** - Quick CI status check for a pull request. Shows pass/fail/pending status for all GitHub Actions jobs and other CI checks.
- **`/dev:code`** - Implement changes following project conventions. Reads AGENTS.md and area-specific docs, then guides implementation, quality checks (pre-commit, tests), and commit with proper message format.
- **`/dev:poll`** - Stateful PR poller: tracks GitHub Actions CI, CodeRabbit, Codecov, and human reviews across polls. Loops with adaptive backoff internally. Run via the Bash tool with run_in_background: true so the platform notifies the agent on exit.
- **`/dev:pr`** - Create a pull request with the correct title format, filled-in description template, and JIRA reference. Handles fork workflow with fallback ladder. Validates the PR title against the CI-enforced regex before creating.
- **`/dev:start`** - Begin work on a JIRA ticket. Assigns the ticket, creates a feature branch, checks if backporting is needed, and loads the relevant agent_docs/ for the ticket's area.
- **`/dev:work`** - Ralph Loop tick-loop for single-ticket development. Replaces the /start -> /code -> /pr -> /poll skill chain with one continuous state machine. Each tick: read state, do one thing, write state, continue.

See [plugins/dev/README.md](plugins/dev/README.md) for detailed documentation.

### Jira Planning Plugin

JIRA operations (view, assign, transition, check-version) and planning commands (epics, stories, estimates, quarterly plans).

**Skills:**
- **`/jira-planning:jira`** - View or update a JIRA ticket. Supports view, assign, transition, check-version, and set-version operations via REST API or acli.

**Commands:**
- **`/jira-planning:create-epic-from-feature` `<feature-key>`** - Generate an epic structure from a JIRA feature and create it in JIRA
- **`/jira-planning:create-plan-from-issue` `<issue-key>`** - Systematically plan a bug or feature based on a JIRA issue
- **`/jira-planning:create-stories-from-epic` `<epic-key>`** - Generate child stories from a JIRA epic, review them, and create in JIRA with approval
- **`/jira-planning:estimate-issue` `<issue-key>`** - Estimate complexity and effort for a JIRA issue
- **`/jira-planning:implement-story`** - Implement a JIRA story end-to-end with tests
- **`/jira-planning:jira-ticket`** - Create or edit JIRA tickets in PROJQUAY or QUAYIO projects
- **`/jira-planning:quarterly-plan` `<quarter> <must-have-issues> e.g., "2026-Q3 QUAYIO-1234,QUAYIO-5678"`** - Plan the next quarter by tagging JIRA issues with the quarterly label
- **`/jira-planning:review-pr`** - Perform a comprehensive code quality review of a pull request

See [plugins/jira-planning/README.md](plugins/jira-planning/README.md) for detailed documentation.

### Openshift Testing Plugin

OpenShift cluster provisioning via Gangway API and remote Playwright browser server deployment for E2E testing.

**Skills:**
- **`/openshift-testing:cluster-provision`** - Provision an ephemeral OpenShift cluster via the OpenShift CI Gangway API. Claims a cluster from a Hive ClusterPool, downloads and decrypts kubeconfig, and validates connectivity. Requires GANGWAY_TOKEN and KUBECONFIG_ENCRYPTION_KEY env vars. Clusters auto-expire after ~4 hours. Use when you need a real OpenShift cluster for blackbox testing or integration work.
- **`/openshift-testing:remote-playwright`** - Deploy and connect to a remote Playwright browser on an OpenShift cluster. Sets up a Playwright run-server pod, port-forwarding, and @playwright/cli for interactive browser automation (goto, click, snapshot, screenshot, video recording). Use when you need a remote browser for E2E interaction or visual verification on a cluster.

See [plugins/openshift-testing/README.md](plugins/openshift-testing/README.md) for detailed documentation.
