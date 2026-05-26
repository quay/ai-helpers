#!/bin/bash
# detect-jira-ticket.sh -- UserPromptSubmit hook that detects JIRA references.
#
# If the user mentions a JIRA ticket key or JIRA-related keyword without
# using a JIRA-aware skill, injects operational context for acli jira commands.
#
# Environment variables:
#   JIRA_TICKET_KEY_PATTERN — regex for ticket keys (default: (PROJQUAY|QUAYIO)-\d+)
#   JIRA_KEYWORD_PATTERN    — regex for JIRA keywords (default: built-in list)

: "${JIRA_TICKET_KEY_PATTERN:=(PROJQUAY|QUAYIO)-[0-9]+}"
: "${JIRA_KEYWORD_PATTERN:=\b(jira|ticket|backlog|sprint|epic|story|stories|triage|target[-[:space:]]+version)\b}"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Skip if user is already invoking a JIRA-aware skill
echo "$PROMPT" | grep -qP '^\s*/(jira|start|backport|implement-story|create-plan|estimate-issue|create-epic|create-stories)(\s|$)' && exit 0

TICKETS=$(echo "$PROMPT" | grep -oP "${JIRA_TICKET_KEY_PATTERN}" | sort -u | head -5)
TICKET_LIST=""
if [ -n "$TICKETS" ]; then
  TICKET_LIST=$(echo "$TICKETS" | tr '\n' ', ' | sed 's/,$//')
fi

# If no ticket keys found, check for JIRA-related keywords
if [ -z "$TICKETS" ]; then
  echo "$PROMPT" | grep -qiP "${JIRA_KEYWORD_PATTERN}" || exit 0
fi

TICKET_HINT="Detected JIRA reference(s): ${TICKET_LIST:-(keyword match)}."

read -r -d '' OPS_CONTEXT <<'OPSEOF'
JIRA operations available via bash .claude/scripts/jira-ops.sh:
  - view <KEY>          -- fetch ticket summary, status, description
  - assign <KEY>        -- assign ticket to current user
  - transition <KEY> <STATUS> -- change status (New, ASSIGNED, POST, ON_QA, Verified, Release Pending, Closed, MODIFIED)
  - check-version <KEY> -- check Target Version (backport requirement)
  - set-version <KEY> <VERSION> -- set Target Version
  - comment <KEY> <TEXT> -- add a comment to the ticket
OPSEOF

jq -n --arg hint "$TICKET_HINT" --arg ops "$OPS_CONTEXT" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:($hint + " Use /jira <ticket> to view details or /start <ticket> to begin work on a ticket.\n\n" + $ops)}}'
