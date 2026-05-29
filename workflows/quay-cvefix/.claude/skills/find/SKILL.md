---
name: find
description: >
  Query PROJQUAY Jira for open CVE tickets. Extracts CVE IDs, container
  names, packages, and target branches. Saves results to artifacts.
allowed-tools:
  - Bash(bash .claude/scripts/jira-ops.sh *)
  - Bash(curl *)
  - Bash(jq *)
  - Bash(python3 *)
  - Bash(cat *)
  - Bash(echo *)
  - Bash(ls *)
  - Read
  - Write
  - Glob
  - Grep
---

# Find CVEs in Jira

## Purpose

Discover and catalog CVE issues reported in PROJQUAY Jira. Query the Jira
API, parse ticket summaries to extract structured data, and save results
for the assess and fix phases.

## Execution Style

**Be concise. Brief status + final summary only.**

```text
Querying Jira... Found 7 CVEs

Results:
- PROJQUAY-12345: CVE-2026-44432 quay/quay-rhel9: urllib3 [quay-3.17]
- PROJQUAY-12346: CVE-2026-33210 quay/clair-rhel9: golang.org/x/net [quay-3.17]
...

Report: artifacts/quay-cvefix/find/cve-issues-20260529-143018.md
```

## Prerequisites

- `JIRA_API_TOKEN` and `JIRA_EMAIL` environment variables
- `jq` installed for JSON parsing
- Access to `redhat.atlassian.net`

## Process

### 1. Parse Arguments

- Parse command arguments for optional flags:
  - `--ignore-resolved` — exclude issues with status "Resolved"
  - `--ignore-vex` — exclude issues closed as "Not a Bug"
  - Container name filter (optional, e.g., `quay/quay-rhel9`)
- If no filter provided, find all CVEs for all Quay components

### 2. Verify Jira Access

Check for Jira MCP server first, then fall back to curl with Basic Auth:

```bash
JIRA_BASE_URL="https://redhat.atlassian.net"
AUTH=$(echo -n "${JIRA_EMAIL}:${JIRA_API_TOKEN}" | base64 | tr -d '\n')

TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X GET \
  --connect-timeout 10 --max-time 15 \
  -H "Authorization: Basic ${AUTH}" \
  -H "Content-Type: application/json" \
  "${JIRA_BASE_URL}/rest/api/3/myself")
```

- HTTP 200 → proceed
- HTTP 401 → credentials invalid, inform user
- HTTP 000 → network issue, inform user

### 3. Query Jira for CVE Issues

Build JQL query:

```bash
JQL='project = PROJQUAY AND summary ~ "CVE*" AND labels = SecurityTracking'

# Optional filters
if [ "$IGNORE_RESOLVED" = "true" ]; then
  JQL="${JQL} AND status not in (\"Resolved\")"
fi
if [ "$IGNORE_VEX" = "true" ]; then
  JQL="${JQL} AND NOT (status = \"Closed\" AND resolution in (\"Not a Bug\", \"Obsolete\", \"Won'\''t Fix\"))"
fi

ENCODED_JQL=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''${JQL}'''))")

RESPONSE=$(curl -s -X GET \
  --connect-timeout 10 --max-time 30 \
  --retry 3 --retry-delay 2 \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic ${AUTH}" \
  "${JIRA_BASE_URL}/rest/api/3/search/jql?jql=${ENCODED_JQL}&fields=key,summary,status,priority,created,description,issuelinks&maxResults=100")
```

Handle cursor-based pagination (v3 API uses `nextPageToken` and `isLast`).

### 4. Filter Ignored Issues

Check each issue for automation-ignore comments:

- `cve-automation-ignore`
- `skip-cve-automation`
- `ignore-cve-automation`

Skip issues with these comments; document them separately.

### 5. Parse Jira Summaries

Extract structured data from each ticket summary. The format is:

```text
CVE-YYYY-XXXXX container/name: package: description [quay-X.Y]
```

For each issue, extract:

```bash
SUMMARY="CVE-2026-44432 quay/quay-rhel9: urllib3: Denial of Service [quay-3.17]"

CVE_ID=$(echo "$SUMMARY" | grep -oP 'CVE-[0-9]+-[0-9]+')
CONTAINER=$(echo "$SUMMARY" | grep -oP '(?<=CVE-[0-9]+-[0-9]+ )[\w/.-]+(?=:)')
PACKAGE=$(echo "$SUMMARY" | sed 's/.*: \([^:]*\):.*/\1/' | xargs)
TARGET_BRANCH=$(echo "$SUMMARY" | grep -oP '(?<=\[quay-)[0-9.]+(?=\])')
```

Map the container to an upstream repo using `component-repository-mappings.json`.

### 6. Generate Report

Save structured output to `artifacts/quay-cvefix/find/cve-issues-<timestamp>.md`:

```bash
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
OUTPUT_FILE="artifacts/quay-cvefix/find/cve-issues-${TIMESTAMP}.md"
mkdir -p artifacts/quay-cvefix/find
```

The report includes:
- Component, query date, total count
- Per-issue: key, CVE ID, container, package, target branch, status, priority
- Summary by status and priority
- List of ignored issues (if any)

### 7. Print Console Summary

Display the first 15 issues to the console with:
- Jira key, CVE ID, container, package, and target branch
- Total count and link to the full report

## Output

- `artifacts/quay-cvefix/find/cve-issues-<timestamp>.md`

## Success Criteria

- [ ] Complete list of PROJQUAY CVE issues retrieved
- [ ] Summaries parsed into structured data (CVE ID, container, package, branch)
- [ ] Issues with ignore comments filtered out
- [ ] Results saved to artifacts
- [ ] Console summary printed
