# jira-planning

JIRA operations and planning workflows. Provides ticket management, planning
commands for epics/stories/estimates, and safety hooks for embargoed tickets.

## Skills

| Skill | Purpose |
|-------|---------|
| `/jira-planning:jira` | View, assign, transition, check/set Target Version |

## Commands

| Command | Purpose |
|---------|---------|
| `/jira-planning:create-epic-from-feature` | Decompose a feature into epics |
| `/jira-planning:create-stories-from-epic` | Break an epic into stories |
| `/jira-planning:create-plan-from-issue` | Generate implementation plan |
| `/jira-planning:estimate-issue` | Estimate story complexity |
| `/jira-planning:implement-story` | Guide for implementing a story |
| `/jira-planning:jira-ticket` | Work with JIRA tickets |
| `/jira-planning:quarterly-plan` | Create quarterly roadmap |
| `/jira-planning:review-pr` | Code review checklist |

## Scripts

| Script | Purpose |
|--------|---------|
| `jira-ops.sh` | JIRA operations via REST API or acli |
| `detect-jira-ticket.sh` | UserPromptSubmit hook for JIRA key detection |
| `check-embargo.sh` | Block processing of embargoed tickets |
| `check-target-version.sh` | PostToolUse hook for Target Version warnings |
| `download-jira-attachments.sh` | Download attachments from JIRA issues |

## Configuration

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `JIRA_DOMAIN` | `redhat.atlassian.net` | JIRA instance |
| `JIRA_TARGET_VERSION_FIELD` | `customfield_10855` | Target Version field ID |
| `JIRA_EMBARGO_STATUS_FIELD` | `customfield_10860` | Embargo Status field ID |
| `JIRA_DEFAULT_EMAIL` | `quay-devel@redhat.com` | Default assignee email |
| `JIRA_TICKET_KEY_PATTERN` | `(PROJQUAY\|QUAYIO)-[0-9]+` | Ticket key regex |
| `ACLI_DOWNLOAD_URL` | acli Linux amd64 URL | acli binary download |
| `ACLI_INSTALL_DIR` | `~/.local/bin` | acli install directory |
