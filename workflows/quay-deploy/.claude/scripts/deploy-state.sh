#!/bin/bash
# deploy-state.sh -- State management for the Quay Deploy pipeline.
#
# Each deployment gets a state file at .claude/deploy-state/<DEPLOY_ID>.json
# The state loop reads state, executes the current handler, writes back, and continues.
#
# Usage:
#   bash .claude/scripts/deploy-state.sh init <DEPLOY_ID> --fbc-image <IMG> [--channel stable-3.XX] [--ocp-version 4.XX] [--kubeconfig /path] [--feature <path|ticket>] [--mode manual]
#   bash .claude/scripts/deploy-state.sh list
#   bash .claude/scripts/deploy-state.sh read <DEPLOY_ID>
#   bash .claude/scripts/deploy-state.sh current <DEPLOY_ID>
#   bash .claude/scripts/deploy-state.sh advance <DEPLOY_ID> <NEXT_STATE>
#   bash .claude/scripts/deploy-state.sh set <DEPLOY_ID> <FIELD> <VALUE>

set -euo pipefail

STATE_DIR=".claude/deploy-state"
mkdir -p "$STATE_DIR"

ACTION="${1:?Usage: deploy-state.sh <action> [args]}"
shift

validate_deploy_id() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "ERROR: invalid deploy ID: $1" >&2
    exit 1
  }
}

state_file() {
  validate_deploy_id "$1"
  echo "${STATE_DIR}/${1}.json"
}

# Auto-detect channel from FBC image reference.
# e.g. quay.io/.../stable-3-18-v4-21@sha256:... → stable-3.18
detect_channel() {
  local img="$1"
  local component
  component=$(echo "$img" | sed -n 's|.*/\([^@]*\)@.*|\1|p')
  if [[ -z "$component" ]]; then
    component=$(echo "$img" | sed -n 's|.*/\([^:]*\).*|\1|p')
  fi
  # Extract stable-X-YY pattern and convert dashes to dots
  local channel
  channel=$(echo "$component" | sed -n 's/.*\(stable-[0-9]*-[0-9]*\).*/\1/p' | sed 's/\(stable-[0-9]*\)-/\1./')
  echo "${channel:-}"
}

case "$ACTION" in

  init)
    DEPLOY_ID="${1:?Missing deploy ID}"
    shift
    FBC_IMAGE=""
    CHANNEL=""
    OCP_VERSION="4.18"
    KUBECONFIG_PATH="/tmp/k"
    FEATURE=""
    MODE="auto"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --fbc-image) FBC_IMAGE="$2"; shift 2 ;;
        --channel) CHANNEL="$2"; shift 2 ;;
        --ocp-version) OCP_VERSION="$2"; shift 2 ;;
        --kubeconfig) KUBECONFIG_PATH="$2"; shift 2 ;;
        --feature) FEATURE="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    if [[ -z "$FBC_IMAGE" ]]; then
      echo "ERROR: --fbc-image is required" >&2
      exit 1
    fi

    FILE=$(state_file "$DEPLOY_ID")
    if [ -f "$FILE" ]; then
      STATE=$(jq -r '.state' "$FILE")
      echo "Resuming ${DEPLOY_ID} from state: ${STATE} (tick #$(jq '.tick_count' "$FILE"))"
      cat "$FILE"
      exit 0
    fi

    # Auto-detect channel if not provided
    if [[ -z "$CHANNEL" ]]; then
      CHANNEL=$(detect_channel "$FBC_IMAGE")
      if [[ -z "$CHANNEL" ]]; then
        echo "ERROR: could not detect channel from FBC image; pass --channel explicitly" >&2
        exit 1
      fi
    fi

    jq -n \
      --arg deploy_id "$DEPLOY_ID" \
      --arg state "PROVISION" \
      --arg mode "$MODE" \
      --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg session "${SESSION_ID:-local}" \
      --arg fbc_image "$FBC_IMAGE" \
      --arg channel "$CHANNEL" \
      --arg ocp_version "$OCP_VERSION" \
      --arg kubeconfig_path "$KUBECONFIG_PATH" \
      --arg feature "$FEATURE" \
      '{
        deploy_id: $deploy_id,
        state: $state,
        mode: $mode,
        created_at: $created,
        last_updated: $created,
        session_id: $session,
        tick_count: 0,
        fbc_image: $fbc_image,
        channel: $channel,
        ocp_version: $ocp_version,
        kubeconfig_path: $kubeconfig_path,
        cluster_api_url: null,
        cluster_console_url: null,
        ocp_detected_version: null,
        mirror_type: null,
        pull_secret_configured: false,
        storage_ready: false,
        catalog_name: null,
        operator_csv: null,
        operator_version: null,
        quay_namespace: "quay",
        quay_route: null,
        feature_path: (if $feature == "" then null else $feature end),
        feature_summary: null,
        playwright_deployed: false,
        frontend_validated: false,
        feature_tested: false,
        ui_bugs: [],
        artifacts: [],
        retry_count: 0,
        history: []
      }' > "$FILE"

    echo "Deploy state initialized: ${DEPLOY_ID} → PROVISION (mode: ${MODE})"
    if [[ -n "$CHANNEL" ]]; then
      echo "Channel: ${CHANNEL} (auto-detected from image)"
    fi
    ;;

  list)
    # List all active (non-COMPLETE) deployments, most recent first
    if [ -z "$(ls -A "$STATE_DIR" 2>/dev/null)" ]; then
      echo "No active deployments."
      exit 0
    fi
    for f in "$STATE_DIR"/*.json; do
      [ -f "$f" ] || continue
      local_id=$(jq -r '.deploy_id' "$f")
      local_state=$(jq -r '.state' "$f")
      [[ "$local_state" == "COMPLETE" ]] && continue
      local_image=$(jq -r '.fbc_image' "$f")
      local_updated=$(jq -r '.last_updated' "$f")
      local_tick=$(jq '.tick_count' "$f")
      echo "${local_id}  state=${local_state}  tick=#${local_tick}  updated=${local_updated}"
      echo "  image=${local_image}"
    done
    ;;

  read)
    DEPLOY_ID="${1:?Missing deploy ID}"
    FILE=$(state_file "$DEPLOY_ID")
    [ -f "$FILE" ] || { echo "No deploy state for ${DEPLOY_ID}" >&2; exit 1; }
    cat "$FILE"
    ;;

  current)
    DEPLOY_ID="${1:?Missing deploy ID}"
    FILE=$(state_file "$DEPLOY_ID")
    [ -f "$FILE" ] || { echo "No deploy state for ${DEPLOY_ID}" >&2; exit 1; }
    jq -r '.state' "$FILE"
    ;;

  advance)
    DEPLOY_ID="${1:?Missing deploy ID}"
    NEXT="${2:?Missing next state}"
    FILE=$(state_file "$DEPLOY_ID")
    [ -f "$FILE" ] || { echo "No deploy state for ${DEPLOY_ID}" >&2; exit 1; }

    NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    PREV=$(jq -r '.state' "$FILE")
    TICK=$(jq '.tick_count' "$FILE")
    NEW_TICK=$((TICK + 1))

    TMP=$(mktemp)
    jq --arg next "$NEXT" \
       --arg now "$NOW" \
       --arg prev "$PREV" \
       --argjson tick "$NEW_TICK" \
       '.state = $next |
        .last_updated = $now |
        .tick_count = $tick |
        .history += [{from: $prev, to: $next, at: $now, tick: $tick}]' \
       "$FILE" > "$TMP" && mv "$TMP" "$FILE"

    echo "${PREV} → ${NEXT} (tick #${NEW_TICK})"
    ;;

  set)
    DEPLOY_ID="${1:?Missing deploy ID}"
    FIELD="${2:?Missing field}"
    VALUE="${3:?Missing value}"
    FILE=$(state_file "$DEPLOY_ID")
    [ -f "$FILE" ] || { echo "No deploy state for ${DEPLOY_ID}" >&2; exit 1; }

    TMP=$(mktemp)
    # Try to parse as JSON (numbers, booleans, arrays), fall back to string
    if echo "$VALUE" | jq . >/dev/null 2>&1; then
      jq --argjson v "$VALUE" --arg f "$FIELD" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.[$f] = $v | .last_updated = $now' "$FILE" > "$TMP"
    else
      jq --arg v "$VALUE" --arg f "$FIELD" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.[$f] = $v | .last_updated = $now' "$FILE" > "$TMP"
    fi
    mv "$TMP" "$FILE"
    echo "Set ${FIELD}=${VALUE}"
    ;;

  *)
    echo "Unknown action: ${ACTION}" >&2
    echo "Actions: init, list, read, current, advance, set" >&2
    exit 1
    ;;
esac
