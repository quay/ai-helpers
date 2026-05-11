#!/usr/bin/env bash
# validate-label-author.sh -- Check that the "autofix" label on a JIRA issue
# was added by a member of the Quay Atlassian team.
#
# Usage: bash .claude/scripts/validate-label-author.sh <ISSUE_KEY>
#
# Exit codes:
#   0 — label was added by an authorized team member (displayName printed to stdout)
#   1 — unauthorized, missing, or error (reason printed to stderr)
#
# Environment variables:
#   JIRA_DOMAIN        — JIRA instance (default: redhat.atlassian.net)
#   JIRA_USER          — JIRA email for API auth (required)
#   JIRA_API_TOKEN     — Atlassian API token (required)
#   ATLASSIAN_ORG_ID   — Atlassian org ID
#   ATLASSIAN_QUAY_TEAM_ID  — QuayAtlassian team ID

set -euo pipefail

ISSUE_KEY="${1:?Usage: validate-label-author.sh <ISSUE_KEY>}"

: "${JIRA_DOMAIN:=redhat.atlassian.net}"
: "${JIRA_API_TOKEN:?JIRA_API_TOKEN must be set}"

if [ -z "${JIRA_USER:-}" ] && [ -f "$HOME/.config/acli/jira_config.yaml" ]; then
  JIRA_USER=$(grep -E '^\s*email:' "$HOME/.config/acli/jira_config.yaml" | awk '{print $2}' | head -1)
fi
: "${JIRA_USER:?JIRA_USER must be set (or email must exist in acli config)}"
: "${ATLASSIAN_ORG_ID:?ATLASSIAN_ORG_ID must be set}"
: "${ATLASSIAN_QUAY_TEAM_ID:?ATLASSIAN_QUAY_TEAM_ID must be set}"

AUTH="${JIRA_USER}:${JIRA_API_TOKEN}"

# --- Step 1: Find who added the "autofix" label via the changelog ---

ISSUE_JSON=$(curl -sS -f \
  -u "$AUTH" \
  "https://${JIRA_DOMAIN}/rest/api/3/issue/${ISSUE_KEY}?expand=changelog&fields=labels")

AUTHOR_ACCOUNT_ID=$(echo "$ISSUE_JSON" | jq -r '
  [ .changelog.histories[]
    | select(.items[]
        | select(.field == "labels" and (.toString // "" | test("\\bautofix\\b")))
      )
    | .author.accountId // empty
  ] | last // empty
')

AUTHOR_DISPLAY_NAME=$(echo "$ISSUE_JSON" | jq -r '
  [ .changelog.histories[]
    | select(.items[]
        | select(.field == "labels" and (.toString // "" | test("\\bautofix\\b")))
      )
    | .author.displayName // empty
  ] | last // empty
')

if [ -z "$AUTHOR_ACCOUNT_ID" ]; then
  echo "No changelog entry found for 'autofix' label on ${ISSUE_KEY}" >&2
  exit 1
fi

# --- Step 2: Fetch members of the Atlassian team ---

TEAM_RESPONSE=$(curl -sS -f \
  -u "$AUTH" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"first": 50}' \
  "https://${JIRA_DOMAIN}/gateway/api/public/teams/v1/org/${ATLASSIAN_ORG_ID}/teams/${ATLASSIAN_QUAY_TEAM_ID}/members")

IS_MEMBER=$(echo "$TEAM_RESPONSE" | jq -r \
  --arg aid "$AUTHOR_ACCOUNT_ID" \
  '[ .results[] | .accountId ] | if index($aid) then "yes" else "no" end')

if [ "$IS_MEMBER" = "yes" ]; then
  echo "$AUTHOR_DISPLAY_NAME"
  exit 0
else
  echo "Label added by ${AUTHOR_DISPLAY_NAME} (${AUTHOR_ACCOUNT_ID}) who is not a member of the Quay team" >&2
  exit 1
fi
