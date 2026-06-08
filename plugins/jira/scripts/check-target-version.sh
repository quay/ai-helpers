#!/bin/bash
# check-target-version.sh -- PostToolUse hook after git push.
#
# Warns if the JIRA ticket doesn't have Target Version set.
#
# Environment variables:
#   JIRA_DOMAIN                — JIRA instance (default: redhat.atlassian.net)
#   JIRA_TARGET_VERSION_FIELD  — custom field ID (default: customfield_10855)
#   JIRA_TICKET_KEY_PATTERN    — regex for ticket keys (default: (PROJQUAY|QUAYIO)-\d+)
#   PRIMARY_BRANCH             — main branch name (default: master)

: "${JIRA_DOMAIN:=redhat.atlassian.net}"
: "${JIRA_TARGET_VERSION_FIELD:=customfield_10855}"
: "${JIRA_TICKET_KEY_PATTERN:=(PROJQUAY|QUAYIO)-[0-9]+}"
: "${PRIMARY_BRANCH:=master}"

ACLI="${ACLI_PATH:-acli}"

BRANCH=$(git branch --show-current 2>/dev/null || true)
[ -z "$BRANCH" ] && exit 0
[ "$BRANCH" = "${PRIMARY_BRANCH}" ] && exit 0

TICKET=$(echo "$BRANCH" | grep -oiP "${JIRA_TICKET_KEY_PATTERN}" | head -1 || true)
[ -z "$TICKET" ] && exit 0

TARGET_VERSION=""
if command -v "$ACLI" &>/dev/null; then
  RESULT=$(timeout 10 "$ACLI" jira workitem view "$TICKET" --fields "${JIRA_TARGET_VERSION_FIELD}" --json 2>/dev/null) || true
  TARGET_VERSION=$(echo "$RESULT" | jq -r ".fields.${JIRA_TARGET_VERSION_FIELD}[0].name // empty" 2>/dev/null || true)
fi

if [ -z "$TARGET_VERSION" ] && [ -n "${JIRA_API_TOKEN:-}" ] && [ -n "${JIRA_USER:-}" ]; then
  RESULT=$(curl -s -u "${JIRA_USER}:${JIRA_API_TOKEN}" \
    "https://${JIRA_DOMAIN}/rest/api/2/issue/${TICKET}?fields=${JIRA_TARGET_VERSION_FIELD}" 2>/dev/null) || true
  TARGET_VERSION=$(echo "$RESULT" | jq -r ".fields.${JIRA_TARGET_VERSION_FIELD}[0].name // empty" 2>/dev/null || true)
fi

if [ -z "$TARGET_VERSION" ]; then
  jq -n --arg ticket "$TICKET" \
    '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("Warning: " + $ticket + " has no Target Version set. The merge bot will block this PR. Run /jira " + $ticket + " set-version to fix.")}}'
fi

exit 0
