#!/usr/bin/env bash
# validate-label-author.sh -- Check that a label on a GitHub PR was added by
# a user with write access to the repository.
#
# Usage: bash .claude/scripts/validate-label-author.sh <REPO> <PR_NUMBER> <LABEL>
#
# Exit codes:
#   0 — label was added by an authorized collaborator (login printed to stdout)
#   1 — unauthorized, missing, or error (reason printed to stderr)

set -euo pipefail

REPO="${1:?Usage: validate-label-author.sh <REPO> <PR_NUMBER> <LABEL>}"
PR_NUMBER="${2:?Usage: validate-label-author.sh <REPO> <PR_NUMBER> <LABEL>}"
LABEL="${3:?Usage: validate-label-author.sh <REPO> <PR_NUMBER> <LABEL>}"

LABEL_ACTOR=$(gh api "repos/${REPO}/issues/${PR_NUMBER}/events" \
  --jq "[.[] | select(.event == \"labeled\" and .label.name == \"${LABEL}\")] | last | .actor.login")

if [ -z "$LABEL_ACTOR" ]; then
  echo "No event found for '${LABEL}' label on ${REPO}#${PR_NUMBER}" >&2
  exit 1
fi

if gh api "repos/${REPO}/collaborators/${LABEL_ACTOR}" --silent 2>/dev/null; then
  echo "$LABEL_ACTOR"
  exit 0
else
  echo "Label added by ${LABEL_ACTOR} who is not a collaborator on ${REPO} — removing label" >&2
  gh api "repos/${REPO}/issues/${PR_NUMBER}/labels/${LABEL}" --method DELETE --silent 2>/dev/null || true
  exit 1
fi
