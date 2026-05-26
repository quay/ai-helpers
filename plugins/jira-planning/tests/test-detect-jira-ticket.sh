#!/bin/bash
# test-detect-jira-ticket.sh — regression tests for detect-jira-ticket.sh
#
# Usage: bash tests/test-detect-jira-ticket.sh
# Exit 0 if all pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${SCRIPT_DIR}/scripts/detect-jira-ticket.sh"

PASS=0
FAIL=0

run_hook() {
  echo "$1" | bash "$HOOK" 2>/dev/null
}

assert_output() {
  local desc="$1" input="$2" check="$3" expect="$4"
  local output
  output=$(run_hook "$input") || true

  local result
  case "$check" in
    empty)
      [ -z "$output" ] && result=pass || result=fail
      ;;
    not_empty)
      [ -n "$output" ] && result=pass || result=fail
      ;;
    contains)
      echo "$output" | grep -qF "$expect" && result=pass || result=fail
      ;;
    not_contains)
      echo "$output" | grep -qF "$expect" && result=fail || result=pass
      ;;
    valid_json)
      echo "$output" | jq . >/dev/null 2>&1 && result=pass || result=fail
      ;;
  esac

  if [ "$result" = "pass" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    input:  $input"
    echo "    output: ${output:-(empty)}"
    echo "    check:  $check ${expect:+= $expect}"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Ticket Key Detection ==="

assert_output "fires on PROJQUAY ticket key" \
  '{"prompt": "Look at PROJQUAY-11620"}' \
  not_empty ""

assert_output "fires on QUAYIO ticket key" \
  '{"prompt": "Check QUAYIO-999"}' \
  not_empty ""

assert_output "includes ticket key in output" \
  '{"prompt": "Look at PROJQUAY-11620"}' \
  contains "PROJQUAY-11620"

assert_output "includes multiple ticket keys" \
  '{"prompt": "compare PROJQUAY-100 with PROJQUAY-200"}' \
  contains "PROJQUAY-100"

echo ""
echo "=== Keyword Detection ==="

assert_output "fires on 'jira' keyword" \
  '{"prompt": "check the jira backlog"}' \
  not_empty ""

assert_output "fires on 'ticket' keyword" \
  '{"prompt": "assign this ticket to me"}' \
  not_empty ""

assert_output "fires on 'backlog' keyword" \
  '{"prompt": "review the backlog"}' \
  not_empty ""

assert_output "fires on 'sprint' keyword" \
  '{"prompt": "what is the current sprint?"}' \
  not_empty ""

assert_output "fires on 'epic' keyword" \
  '{"prompt": "create an epic for this work"}' \
  not_empty ""

assert_output "fires on 'story' keyword" \
  '{"prompt": "write a story for this feature"}' \
  not_empty ""

assert_output "fires on 'stories' keyword" \
  '{"prompt": "break this into stories"}' \
  not_empty ""

assert_output "fires on 'triage' keyword" \
  '{"prompt": "triage these bugs"}' \
  not_empty ""

assert_output "fires on 'target version' keyword" \
  '{"prompt": "check the target version"}' \
  not_empty ""

assert_output "case-insensitive: fires on 'JIRA' uppercase" \
  '{"prompt": "what is in the JIRA backlog?"}' \
  not_empty ""

assert_output "keyword match shows (keyword match) hint" \
  '{"prompt": "check the jira backlog"}' \
  contains "(keyword match)"

echo ""
echo "=== Operational Context Injection ==="

assert_output "includes jira-ops.sh reference" \
  '{"prompt": "Look at PROJQUAY-11620"}' \
  contains "jira-ops.sh"

assert_output "includes view command" \
  '{"prompt": "Look at PROJQUAY-11620"}' \
  contains "view <KEY>"

assert_output "includes assign command" \
  '{"prompt": "Look at PROJQUAY-11620"}' \
  contains "assign <KEY>"

assert_output "includes transition command" \
  '{"prompt": "Look at PROJQUAY-11620"}' \
  contains "transition <KEY> <STATUS>"

assert_output "includes check-version command" \
  '{"prompt": "Look at PROJQUAY-11620"}' \
  contains "check-version <KEY>"

assert_output "includes set-version command" \
  '{"prompt": "Look at PROJQUAY-11620"}' \
  contains "set-version <KEY> <VERSION>"

assert_output "includes comment command" \
  '{"prompt": "Look at PROJQUAY-11620"}' \
  contains "comment <KEY> <TEXT>"

assert_output "keyword-only also gets operational context" \
  '{"prompt": "check the jira backlog"}' \
  contains "jira-ops.sh"

assert_output "still mentions /jira skill" \
  '{"prompt": "Look at PROJQUAY-11620"}' \
  contains "/jira <ticket>"

assert_output "still mentions /start skill" \
  '{"prompt": "Look at PROJQUAY-11620"}' \
  contains "/start <ticket>"

echo ""
echo "=== Skip Conditions ==="

assert_output "skips /jira invocation" \
  '{"prompt": "/jira PROJQUAY-11620"}' \
  empty ""

assert_output "skips /start invocation" \
  '{"prompt": "/start PROJQUAY-11620"}' \
  empty ""

assert_output "skips /backport invocation" \
  '{"prompt": "/backport PROJQUAY-11620"}' \
  empty ""

assert_output "skips /implement-story invocation" \
  '{"prompt": "/implement-story PROJQUAY-11620"}' \
  empty ""

assert_output "skips /create-plan invocation" \
  '{"prompt": "/create-plan PROJQUAY-11620"}' \
  empty ""

assert_output "skips /estimate-issue invocation" \
  '{"prompt": "/estimate-issue PROJQUAY-11620"}' \
  empty ""

assert_output "skips /create-epic invocation" \
  '{"prompt": "/create-epic PROJQUAY-11620"}' \
  empty ""

assert_output "skips /create-stories invocation" \
  '{"prompt": "/create-stories PROJQUAY-11620"}' \
  empty ""

echo ""
echo "=== No False Positives ==="

assert_output "silent on unrelated input" \
  '{"prompt": "fix the login page CSS"}' \
  empty ""

assert_output "silent on empty prompt" \
  '{"prompt": ""}' \
  empty ""

assert_output "silent on concert tickets (word boundary)" \
  '{"prompt": "I bought concert tickets online"}' \
  empty ""

echo ""
echo "=== JSON Validity ==="

assert_output "ticket key output is valid JSON" \
  '{"prompt": "Look at PROJQUAY-11620"}' \
  valid_json ""

assert_output "keyword output is valid JSON" \
  '{"prompt": "check the jira backlog"}' \
  valid_json ""

echo ""
echo "=== Custom Env Vars ==="

# Test custom keyword pattern
ORIG_KEYWORD="${JIRA_KEYWORD_PATTERN:-}"
export JIRA_KEYWORD_PATTERN='\b(custom_keyword)\b'
assert_output "custom keyword pattern: fires on custom_keyword" \
  '{"prompt": "check the custom_keyword"}' \
  not_empty ""
assert_output "custom keyword pattern: silent on jira (overridden)" \
  '{"prompt": "check the jira backlog"}' \
  empty ""
if [ -n "$ORIG_KEYWORD" ]; then
  export JIRA_KEYWORD_PATTERN="$ORIG_KEYWORD"
else
  unset JIRA_KEYWORD_PATTERN
fi

echo ""
echo "=========================================="
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
