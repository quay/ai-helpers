#!/usr/bin/env bash
# triage-state.sh -- Manage triage deduplication state.
#
# Usage:
#   bash scripts/triage-state.sh init
#   bash scripts/triage-state.sh is-triaged <pipelinerun-name>
#   bash scripts/triage-state.sh record <pipelinerun-name> <failure_type> <component> <session_name>
#   bash scripts/triage-state.sh count-component <component>
#   bash scripts/triage-state.sh list
#   bash scripts/triage-state.sh prune --older-than <duration>

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STATE_DIR="${REPO_ROOT}/.claude/triage-state"
STATE_FILE="${STATE_DIR}/triaged.json"
mkdir -p "$STATE_DIR"

COMMAND="${1:?Usage: triage-state.sh <init|is-triaged|record|list|count-component|prune>}"
shift

case "$COMMAND" in
  init)
    if [ ! -f "$STATE_FILE" ]; then
      echo '{"triaged": {}, "last_poll": null, "cycle_count": 0}' > "$STATE_FILE"
      echo "Initialized triage state at ${STATE_FILE}"
    else
      echo "Triage state already exists (cycle_count: $(jq '.cycle_count' "$STATE_FILE"))"
    fi
    ;;

  is-triaged)
    PR_NAME="${1:?Usage: triage-state.sh is-triaged <pipelinerun-name>}"
    if [ ! -f "$STATE_FILE" ]; then
      exit 1
    fi
    EXISTS=$(jq -r --arg name "$PR_NAME" '.triaged[$name] // empty' "$STATE_FILE")
    if [ -n "$EXISTS" ]; then
      exit 0
    else
      exit 1
    fi
    ;;

  record)
    PR_NAME="${1:?}"
    FAILURE_TYPE="${2:?}"
    COMPONENT="${3:?}"
    SESSION_NAME="${4:?}"

    TRIAGED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    TMP=$(mktemp)
    jq --arg name "$PR_NAME" \
       --arg ft "$FAILURE_TYPE" \
       --arg comp "$COMPONENT" \
       --arg sess "$SESSION_NAME" \
       --arg at "$TRIAGED_AT" \
       '.triaged[$name] = {
          triaged_at: $at,
          failure_type: $ft,
          component: $comp,
          fix_session: $sess,
          fix_session_status: "spawned"
        } | .last_poll = $at | .cycle_count += 1' \
       "$STATE_FILE" > "$TMP"
    mv "$TMP" "$STATE_FILE"
    echo "Recorded: ${PR_NAME} → session ${SESSION_NAME}"
    ;;

  count-component)
    COMPONENT="${1:?Usage: triage-state.sh count-component <component>}"
    if [ ! -f "$STATE_FILE" ]; then
      echo "0"
      exit 0
    fi
    jq --arg comp "$COMPONENT" \
       '[.triaged | to_entries[] | select(.value.component == $comp)] | length' \
       "$STATE_FILE"
    ;;

  list)
    if [ ! -f "$STATE_FILE" ]; then
      echo "No triage state file"
      exit 0
    fi
    jq '.' "$STATE_FILE"
    ;;

  prune)
    DURATION="7d"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --older-than) DURATION="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    DAYS=$(echo "$DURATION" | grep -oP '\d+')
    CUTOFF=$(date -u -d "${DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
             date -u -v-${DAYS}d +%Y-%m-%dT%H:%M:%SZ)
    BEFORE=$(jq '.triaged | length' "$STATE_FILE")
    TMP=$(mktemp)
    jq --arg cutoff "$CUTOFF" \
       '.triaged |= with_entries(select(.value.triaged_at > $cutoff))' \
       "$STATE_FILE" > "$TMP"
    mv "$TMP" "$STATE_FILE"
    AFTER=$(jq '.triaged | length' "$STATE_FILE")
    echo "Pruned: ${BEFORE} → ${AFTER} entries (removed $(( BEFORE - AFTER )) older than ${DURATION})"
    ;;

  *)
    echo "Unknown command: ${COMMAND}" >&2
    exit 1
    ;;
esac
