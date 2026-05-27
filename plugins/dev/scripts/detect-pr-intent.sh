#!/bin/bash
# detect-pr-intent.sh -- UserPromptSubmit hook.
# Injects a /pr skill reminder when the user's prompt contains PR- or
# commit-related intent keywords.  Exits 0 so the prompt is never blocked.

set -uo pipefail

PROMPT=$(cat | jq -r '.prompt // empty' 2>/dev/null | tr '[:upper:]' '[:lower:]')

if [ -z "$PROMPT" ]; then
  exit 0
fi

if echo "$PROMPT" | grep -qE '\b(create pr|open pr|pull request|make a pr|submit pr|commit and push|push and pr|merge this|raise a pr|open a pull)\b'; then
  cat <<'EOF'
[workflow] PR-related intent detected.
[workflow] REQUIRED: use the /pr skill — never call 'gh pr create' directly.
[workflow] The /pr skill handles fork setup, title regex validation,
[workflow] /tmp/pr-body.md with required sections, and cross-fork PR creation.
EOF
fi
