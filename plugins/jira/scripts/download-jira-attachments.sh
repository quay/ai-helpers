#!/bin/bash
# download-jira-attachments.sh -- Download attachments from a JIRA issue.
#
# Usage: bash scripts/download-jira-attachments.sh <ISSUE-KEY>

set -e

ISSUE_KEY="$1"

if [ -z "$ISSUE_KEY" ]; then
  echo "Usage: $0 <ISSUE-KEY>"
  exit 1
fi

if ! command -v acli &>/dev/null; then
  echo "Error: acli CLI is not installed or not in PATH"
  exit 1
fi

TEMP_JSON="/tmp/issue-${ISSUE_KEY}.json"
acli jira workitem view "$ISSUE_KEY" --json --fields "*all" >"$TEMP_JSON"

ATTACHMENT_COUNT=$(jq -r '.fields.attachment | length' "$TEMP_JSON" 2>/dev/null || echo "0")

if [ "$ATTACHMENT_COUNT" -gt 0 ]; then
  ATTACH_DIR=".claude/attachments/${ISSUE_KEY}"
  mkdir -p "$ATTACH_DIR"

  echo "Found $ATTACHMENT_COUNT attachment(s) for $ISSUE_KEY"

  if [ -z "$JIRA_USER" ]; then
    JIRA_USER=$(acli jira auth status 2>/dev/null | grep 'Email:' | awk '{print $2}')
  fi
  if [ -z "$JIRA_SITE" ]; then
    JIRA_SITE=$(acli jira auth status 2>/dev/null | grep 'Site:' | awk '{print $2}')
  fi

  if [ -z "$JIRA_API_TOKEN" ] || [ -z "$JIRA_USER" ]; then
    echo "Error: Could not determine JIRA credentials."
    echo "Set JIRA_USER and JIRA_API_TOKEN, or configure acli jira auth."
    rm -f "$TEMP_JSON"
    exit 1
  fi

  jq -r '.fields.attachment[] | "\(.filename)|\(.content)"' "$TEMP_JSON" | while IFS='|' read -r filename url; do
    if [ -n "$JIRA_SITE" ]; then
      # shellcheck disable=SC2001
      url=$(echo "$url" | sed "s|https://[^/]*/|https://${JIRA_SITE}/|")
    fi
    echo "  Downloading: $filename"
    curl -s --fail -L -u "${JIRA_USER}:${JIRA_API_TOKEN}" \
      -o "$ATTACH_DIR/$filename" \
      "$url"
  done

  echo "Downloaded to: $ATTACH_DIR/"

  echo ""
  echo "Attachments:"
  for file in "$ATTACH_DIR"/*; do
    if [ -f "$file" ]; then
      basename "$file"
      file -b "$file" | head -c 80
      echo ""
    fi
  done
else
  echo "No attachments found for $ISSUE_KEY"
fi

rm -f "$TEMP_JSON"
