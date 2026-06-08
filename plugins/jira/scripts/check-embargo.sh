#!/bin/bash
# check-embargo.sh -- Block processing of embargoed JIRA tickets.
#
# Hook for UserPromptSubmit and PreToolUse events.
# Checks the embargo status field on referenced tickets.
#
# Environment variables:
#   JIRA_EMBARGO_STATUS_FIELD — custom field ID (default: customfield_10860)
#   JIRA_EMBARGO_BLOCKED_VALUE — value that indicates embargo (default: True)
#
# Exit 0 = allow, Exit 2 = block

set -o pipefail

: "${JIRA_EMBARGO_STATUS_FIELD:=customfield_10860}"
: "${JIRA_EMBARGO_BLOCKED_VALUE:=True}"

ACLI="${ACLI_PATH:-acli}"

if ! command -v "$ACLI" &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')

case "$HOOK_EVENT" in
  PreToolUse)
    TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
    [ "$TOOL_NAME" != "Bash" ] && exit 0
    TEXT=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    echo "$TEXT" | grep -qi 'jira' || exit 0
    ;;
  UserPromptSubmit)
    TEXT=$(echo "$INPUT" | jq -r '.prompt // empty')
    ;;
  *)
    exit 0
    ;;
esac

[ -z "$TEXT" ] && exit 0

KEYS=$(echo "$TEXT" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | sort -u)
[ -z "$KEYS" ] && exit 0

BLOCKED=""
while IFS= read -r KEY; do
  RESULT=$(timeout 10 "$ACLI" jira workitem view "$KEY" --fields "${JIRA_EMBARGO_STATUS_FIELD}" --json 2>/dev/null) || continue
  EMBARGO_VAL=$(echo "$RESULT" | jq -r ".fields.${JIRA_EMBARGO_STATUS_FIELD}.value // empty")
  if [ "$EMBARGO_VAL" = "${JIRA_EMBARGO_BLOCKED_VALUE}" ]; then
    BLOCKED="${BLOCKED}  - ${KEY}\n"
  fi
done <<<"$KEYS"

if [ -n "$BLOCKED" ]; then
  cat >&2 <<EOF
BLOCKED: Embargoed JIRA ticket(s) detected.
Embargoed tickets must not be processed by AI assistants.

Embargoed tickets:
$(echo -e "$BLOCKED")
Remove these ticket references from your prompt to proceed.
If the embargo has been lifted, update the ticket's Embargo Status in JIRA first.
EOF
  exit 2
fi

exit 0
