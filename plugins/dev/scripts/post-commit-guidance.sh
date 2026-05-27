#!/bin/bash
# post-commit-guidance.sh -- PostToolUse hook for git commit.
# Injects a reminder to use /pr after committing.  Exits 0, never blocks.

set -uo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$CMD" ]; then
  exit 0
fi

if ! echo "$CMD" | grep -qE '(^|[;&|[:space:]])git commit([[:space:]]|$)'; then
  exit 0
fi

cat <<'EOF'
[workflow] Commit recorded. Next: push and open a PR via the /pr skill.
[workflow] Run /pr — it validates your title, writes /tmp/pr-body.md with
[workflow] required sections (## Summary, ## Test Plan, ## JIRA), pushes to
[workflow] your fork, and creates the cross-fork PR correctly.
EOF
