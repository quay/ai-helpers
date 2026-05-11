#!/bin/bash
# PostToolUse hook: parse `gh pr create` stdout, emit poll nudge.
set -uo pipefail

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
RESPONSE=$(echo "$INPUT" | jq -r '.tool_response.stdout // empty')
PR_URL=$(echo "$RESPONSE" | sed -n 's|.*\(https://github\.com/[^/][^/]*/[^/][^/]*/pull/[0-9][0-9]*\).*|\1|p' | head -1 || true)

if [ -n "$PR_URL" ]; then
  PR_NUM=$(echo "$PR_URL" | sed 's|.*/||')
  jq -n --arg pr "$PR_NUM" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("PR #" + $pr + " created. You MUST now run the poll skill for PR #" + $pr + " immediately.")}}'
fi
