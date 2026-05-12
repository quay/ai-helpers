#!/bin/bash
# enforce-pr-skill.sh -- PreToolUse hook for gh pr create.
# Ensures the /pr skill conventions are followed before creating a PR:
#   1. PR title matches CI-enforced regex
#   2. /tmp/pr-body.md exists with required template sections
#   3. The command references /tmp/pr-body.md for the body
#   4. If AGENTIC_SESSION_NAME is set, --label is present
#   5. --base flag is specified
#
# Environment variables:
#   PR_TITLE_PATTERN       — regex for PR title validation
#   PR_REQUIRED_SECTIONS   — comma-separated required body sections
#   AMBIENT_SESSION_LABEL  — label name for ambient sessions
#   PRIMARY_BRANCH         — default base branch name

set -uo pipefail

: "${PR_TITLE_PATTERN:=^(\[redhat-[0-9]+\.[0-9]+\] )?(PROJQUAY-[0-9]+|QUAYIO-[0-9]+|NO-ISSUE): [a-z]+(\([^)]+\))?: .+$}"
: "${AMBIENT_SESSION_LABEL:=ambient-session}"
: "${PRIMARY_BRANCH:=master}"

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

if ! echo "$CMD" | grep -q 'gh pr create'; then
  exit 0
fi

ERRORS=()

# --- Check 1: PR title matches CI-enforced regex ---
TITLE=$(python3 -c '
import shlex, sys

cmd = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    argv = shlex.split(cmd, posix=True)
except ValueError:
    sys.exit(0)

title = ""
for i, arg in enumerate(argv):
    if arg == "--title" and i + 1 < len(argv):
        title = argv[i + 1]
        break
    if arg.startswith("--title="):
        title = arg.split("=", 1)[1]
        break

print(title, end="")
' "$CMD")

if [ -n "$TITLE" ] && ! echo "$TITLE" | grep -qE "$PR_TITLE_PATTERN"; then
  ERRORS+=("PR title does not match required format. Pattern: ${PR_TITLE_PATTERN}. Got: $TITLE")
fi

# --- Check 2: /tmp/pr-body.md exists and has required template sections ---
if [ ! -f /tmp/pr-body.md ]; then
  ERRORS+=("PR body file /tmp/pr-body.md not found. The /pr skill writes the filled PR description template there before creating the PR. Run /pr to create PRs correctly.")
else
  IFS=',' read -ra SECTIONS <<< "${PR_REQUIRED_SECTIONS:-## Summary,## Test Plan,## JIRA}"
  for section in "${SECTIONS[@]}"; do
    section=$(echo "$section" | xargs)
    if ! grep -qF "$section" /tmp/pr-body.md; then
      ERRORS+=("PR body file /tmp/pr-body.md is missing required section: $section.")
    fi
  done
fi

# --- Check 3: Command references /tmp/pr-body.md for the body ---
if ! echo "$CMD" | grep -q 'pr-body\.md'; then
  ERRORS+=("The gh pr create command must use /tmp/pr-body.md for the --body content.")
fi

# --- Check 4: Ambient session label ---
if [ -n "${AGENTIC_SESSION_NAME:-}" ]; then
  if ! echo "$CMD" | grep -qE "${AMBIENT_SESSION_LABEL}"; then
    ERRORS+=("AGENTIC_SESSION_NAME is set ($AGENTIC_SESSION_NAME) but --label \"${AMBIENT_SESSION_LABEL}\" is missing.")
  fi
fi

# --- Check 5: --base flag is specified ---
if ! echo "$CMD" | grep -q -- '--base'; then
  ERRORS+=("Missing --base flag. The /pr skill requires --base ${PRIMARY_BRANCH} (or the target branch for backports).")
fi

# --- Report ---
if [ ${#ERRORS[@]} -gt 0 ]; then
  echo "BLOCKED: gh pr create does not follow /pr skill conventions." >&2
  echo "" >&2
  for err in "${ERRORS[@]}"; do
    echo "  - $err" >&2
  done
  echo "" >&2
  echo "Use the /pr skill to create PRs correctly, or fix the issues above." >&2
  exit 2
fi
