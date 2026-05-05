#!/bin/bash
# tick-state.sh -- State machine for the /work tick-loop.
#
# Manages JSON state files for ticket-scoped workflow execution.
# Each ticket gets its own state file tracking current state, metadata,
# and progress counters.
#
# Usage:
#   bash scripts/tick-state.sh init <TICKET> [--mode auto|manual]
#   bash scripts/tick-state.sh read <TICKET>
#   bash scripts/tick-state.sh advance <TICKET> <NEXT_STATE>
#   bash scripts/tick-state.sh set <TICKET> <KEY> <VALUE>
#
# State file: .claude/tick-state/<TICKET>.json

set -euo pipefail

STATE_DIR=".claude/tick-state"
mkdir -p "$STATE_DIR"

COMMAND="${1:?Usage: tick-state.sh <init|read|advance|set> <TICKET> [args...]}"
shift

case "$COMMAND" in
  init)
    TICKET="${1:?Usage: tick-state.sh init <TICKET> [--mode auto|manual]}"
    shift
    MODE="auto"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --mode) MODE="${2:-auto}"; shift 2 ;;
        *) shift ;;
      esac
    done

    STATE_FILE="${STATE_DIR}/${TICKET}.json"

    if [ -f "$STATE_FILE" ]; then
      echo "Resuming existing state for ${TICKET}:"
      cat "$STATE_FILE"
    else
      CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      jq -n \
        --arg ticket "$TICKET" \
        --arg state "ASSIGN" \
        --arg mode "$MODE" \
        --arg created_at "$CREATED_AT" \
        '{
          ticket: $ticket,
          state: $state,
          mode: $mode,
          created_at: $created_at,
          tick_count: 0,
          triage_attempts: 0,
          branch: null,
          pr_number: null,
          backport_required: false,
          area_docs: [],
          last_poll_exit: null
        }' > "$STATE_FILE"
      echo "Initialized state for ${TICKET} in ${MODE} mode:"
      cat "$STATE_FILE"
    fi
    ;;

  read)
    TICKET="${1:?Usage: tick-state.sh read <TICKET>}"
    STATE_FILE="${STATE_DIR}/${TICKET}.json"

    if [ ! -f "$STATE_FILE" ]; then
      echo "No state file found for ${TICKET}. Run 'init' first." >&2
      exit 1
    fi

    cat "$STATE_FILE"
    ;;

  advance)
    TICKET="${1:?Usage: tick-state.sh advance <TICKET> <NEXT_STATE>}"
    NEXT_STATE="${2:?Usage: tick-state.sh advance <TICKET> <NEXT_STATE>}"
    STATE_FILE="${STATE_DIR}/${TICKET}.json"

    if [ ! -f "$STATE_FILE" ]; then
      echo "No state file found for ${TICKET}. Run 'init' first." >&2
      exit 1
    fi

    UPDATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    PREV_STATE=$(jq -r '.state' "$STATE_FILE")
    TICK_COUNT=$(jq '.tick_count' "$STATE_FILE")

    TMP=$(mktemp)
    jq \
      --arg state "$NEXT_STATE" \
      --arg prev "$PREV_STATE" \
      --arg updated_at "$UPDATED_AT" \
      --argjson tick "$((TICK_COUNT + 1))" \
      '.state = $state | .previous_state = $prev | .updated_at = $updated_at | .tick_count = $tick' \
      "$STATE_FILE" > "$TMP"
    mv "$TMP" "$STATE_FILE"

    echo "Advanced ${TICKET}: ${PREV_STATE} -> ${NEXT_STATE} (tick #$((TICK_COUNT + 1)))"
    ;;

  set)
    TICKET="${1:?Usage: tick-state.sh set <TICKET> <KEY> <VALUE>}"
    KEY="${2:?Usage: tick-state.sh set <TICKET> <KEY> <VALUE>}"
    VALUE="${3:?Usage: tick-state.sh set <TICKET> <KEY> <VALUE>}"
    STATE_FILE="${STATE_DIR}/${TICKET}.json"

    if [ ! -f "$STATE_FILE" ]; then
      echo "No state file found for ${TICKET}. Run 'init' first." >&2
      exit 1
    fi

    TMP=$(mktemp)
    # Try to parse VALUE as JSON (for arrays, objects, booleans, numbers)
    if echo "$VALUE" | jq . &>/dev/null; then
      jq --argjson v "$VALUE" --arg k "$KEY" '.[$k] = $v' "$STATE_FILE" > "$TMP" 2>/dev/null \
        || jq --arg v "$VALUE" --arg k "$KEY" '.[$k] = $v' "$STATE_FILE" > "$TMP"
    else
      jq --arg v "$VALUE" --arg k "$KEY" '.[$k] = $v' "$STATE_FILE" > "$TMP"
    fi
    mv "$TMP" "$STATE_FILE"

    echo "Set ${TICKET}.${KEY} = ${VALUE}"
    ;;

  *)
    echo "Unknown command: ${COMMAND}" >&2
    echo "Usage: tick-state.sh <init|read|advance|set> <TICKET> [args...]" >&2
    exit 1
    ;;
esac
