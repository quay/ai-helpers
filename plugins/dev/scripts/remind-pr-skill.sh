#!/bin/bash
# remind-pr-skill.sh -- PreToolUse hook for gh pr create.
# Injects /pr skill requirements as guidance context before enforce-pr-skill.sh
# blocks the command.  Always exits 0 so the enforcement hook runs next.

set -uo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$CMD" ]; then
  exit 0
fi

if ! echo "$CMD" | grep -qE '(^|[;&|[:space:]])gh pr create([[:space:]]|$)'; then
  exit 0
fi

cat <<'EOF'
[workflow] gh pr create detected. Verifying /pr skill conventions:
[workflow]   1. PR title must match the CI regex (validate-pr-title.sh)
[workflow]   2. /tmp/pr-body.md must exist with: ## Summary, ## Test Plan, ## JIRA
[workflow]   3. --body must reference /tmp/pr-body.md
[workflow]   4. --base flag must be present
[workflow]   5. If AGENTIC_SESSION_NAME is set, --label ambient-session is required
[workflow] If invoked via /pr, the next hook will verify compliance automatically.
EOF
