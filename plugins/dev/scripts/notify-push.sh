#!/bin/bash
# PostToolUse hook: emit poll nudge after `git push` when an open PR exists.
set -uo pipefail

if ! command -v jq &>/dev/null; then
  exit 0
fi

PR_NUM=$(gh pr view --json number,state -q 'select(.state=="OPEN") | .number' 2>/dev/null || true)
if [ -n "$PR_NUM" ]; then
  jq -n --arg pr "$PR_NUM" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("Push detected for open PR #" + $pr + ". You MUST now run the poll skill for PR #" + $pr + " immediately. Do NOT continue other work until poll is running.")}}'
fi
