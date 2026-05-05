#!/bin/bash
# validate-pr-title.sh -- Validate a PR title against the CI-enforced regex.
#
# Usage: bash scripts/validate-pr-title.sh "PROJQUAY-1234: fix(api): description"
#
# Environment variables:
#   PR_TITLE_PATTERN — regex for PR title (default: PROJQUAY/QUAYIO/NO-ISSUE pattern)

set -euo pipefail

: "${PR_TITLE_PATTERN:=^(\[redhat-[0-9]+\.[0-9]+\] )?(PROJQUAY-[0-9]+|QUAYIO-[0-9]+|NO-ISSUE): [a-z]+(\([^)]+\))?: .+$}"

TITLE="${1:?Usage: validate-pr-title.sh \"<PR title>\"}"

if echo "$TITLE" | grep -qE "$PR_TITLE_PATTERN"; then
  echo "PR title is valid: $TITLE"
  exit 0
else
  echo "INVALID PR title: $TITLE" >&2
  echo "Expected pattern: $PR_TITLE_PATTERN" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  PROJQUAY-1234: fix(api): add pagination to tag listing" >&2
  echo "  NO-ISSUE: chore: update dependencies" >&2
  echo "  [redhat-3.12] PROJQUAY-1234: fix(api): backport tag pagination" >&2
  exit 1
fi
