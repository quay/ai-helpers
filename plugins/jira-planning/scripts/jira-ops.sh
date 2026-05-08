#!/bin/bash
# jira-ops.sh -- JIRA operations for development workflows.
#
# Usage:
#   bash scripts/jira-ops.sh view <ISSUE_KEY>
#   bash scripts/jira-ops.sh assign <ISSUE_KEY> [assignee]
#   bash scripts/jira-ops.sh transition <ISSUE_KEY> <status>
#   bash scripts/jira-ops.sh comment <ISSUE_KEY> <comment_text>
#   bash scripts/jira-ops.sh check-version <ISSUE_KEY>
#   bash scripts/jira-ops.sh set-version <ISSUE_KEY> <version>
#
# Environment variables:
#   JIRA_DOMAIN                — JIRA instance (default: redhat.atlassian.net)
#   JIRA_TARGET_VERSION_FIELD  — custom field ID (default: customfield_10855)
#   JIRA_DEFAULT_EMAIL         — fallback email (default: quay-devel@redhat.com)
#   ACLI_DOWNLOAD_URL          — acli binary URL
#   ACLI_INSTALL_DIR           — install directory (default: ~/.local/bin)
#   ACLI_AUTO_INSTALL          — set to 0 to skip auto-install

set -euo pipefail

ACTION="${1:?Usage: jira-ops.sh <action> <ISSUE_KEY> [args...]}"
ISSUE_KEY="${2:?Usage: jira-ops.sh <action> <ISSUE_KEY> [args...]}"
shift 2

: "${JIRA_DOMAIN:=redhat.atlassian.net}"
: "${JIRA_TARGET_VERSION_FIELD:=customfield_10855}"
: "${JIRA_DEFAULT_EMAIL:=quay-devel@redhat.com}"
: "${ACLI_DOWNLOAD_URL:=https://acli.atlassian.com/linux/latest/acli_linux_amd64/acli}"
: "${ACLI_INSTALL_DIR:=${HOME}/.local/bin}"

TV_FIELD="${JIRA_TARGET_VERSION_FIELD}"

install_acli() {
  mkdir -p "$ACLI_INSTALL_DIR"
  echo "Installing acli to ${ACLI_INSTALL_DIR}..."
  curl -fsSL -o "${ACLI_INSTALL_DIR}/acli" "$ACLI_DOWNLOAD_URL" || {
    echo "ERROR: Failed to download acli." >&2
    return 1
  }
  chmod +x "${ACLI_INSTALL_DIR}/acli"
  export PATH="${ACLI_INSTALL_DIR}:${PATH}"

  local token="${JIRA_API_TOKEN:-}"
  local email="${JIRA_USER:-${JIRA_DEFAULT_EMAIL}}"
  if [ -n "$token" ]; then
    echo "$token" | acli jira auth login --site "${JIRA_DOMAIN}" --email "$email" --token 2>/dev/null && echo "acli authenticated." || echo "Warning: acli installed but auth failed." >&2
  else
    echo "acli installed. Authenticate with: acli jira auth login --site ${JIRA_DOMAIN} --email <email> --token" >&2
  fi
}

JIRA_CLI=""
if command -v acli &>/dev/null; then
  JIRA_CLI="acli"
elif [ "${ACLI_AUTO_INSTALL:-1}" != "0" ]; then
  install_acli
  if command -v acli &>/dev/null; then
    JIRA_CLI="acli"
  fi
fi

get_jira_creds() {
  local email="" token=""

  if [ -f "$HOME/.config/acli/jira_config.yaml" ]; then
    email=$(grep -E '^\s*email:' "$HOME/.config/acli/jira_config.yaml" | awk '{print $2}' | head -1)
  fi

  for f in "$HOME/.config/acli/token.txt" "$HOME/.acli-token"; do
    if [ -f "$f" ]; then
      token=$(cat "$f")
      break
    fi
  done

  [ -z "$token" ] && token="${JIRA_API_TOKEN:-}"
  [ -z "$email" ] && email="${JIRA_USER:-${JIRA_DEFAULT_EMAIL}}"

  echo "${email}:${token}"
}

jira_rest() {
  local method="$1" path="$2" data="${3:-}"
  local creds
  creds=$(get_jira_creds)

  local token="${creds#*:}"
  if [ -z "$token" ]; then
    echo "ERROR: No JIRA API token found. Set JIRA_API_TOKEN or configure acli token." >&2
    return 1
  fi

  local args=(-sS -f -H "Content-Type: application/json" -u "$creds")
  if [ -n "$data" ]; then
    args+=(-X "$method" -d "$data")
  fi

  curl "${args[@]}" "https://${JIRA_DOMAIN}/rest/api/3/${path}"
}

extract_target_version() {
  local json="$1"
  echo "$json" | jq -r "
    .fields.${TV_FIELD} // null |
    if type == \"array\" and length > 0 then
      [.[].name] | join(\", \")
    else
      null
    end
  " 2>/dev/null
}

case "$ACTION" in
  view)
    echo "Fetching ${ISSUE_KEY}..."
    if [ "$JIRA_CLI" = "acli" ]; then
      acli jira workitem view "$ISSUE_KEY" 2>/dev/null || {
        echo "acli failed, trying REST API..."
        RESULT=$(jira_rest GET "issue/${ISSUE_KEY}")
        TV_VALUE=$(extract_target_version "$RESULT")
        echo "$RESULT" | jq --arg tv "${TV_VALUE:-not set}" '{
          key: .key,
          summary: .fields.summary,
          status: .fields.status.name,
          assignee: (.fields.assignee.displayName // "unassigned"),
          type: .fields.issuetype.name,
          priority: .fields.priority.name,
          target_version: $tv,
          labels: .fields.labels,
          description: ([.fields.description // {} | .. | .text? // empty] | .[0:10] | join(" "))
        }' 2>/dev/null || echo "$RESULT"
      }
    else
      RESULT=$(jira_rest GET "issue/${ISSUE_KEY}")
      TV_VALUE=$(extract_target_version "$RESULT")
      echo "$RESULT" | jq --arg tv "${TV_VALUE:-not set}" '{
        key: .key,
        summary: .fields.summary,
        status: .fields.status.name,
        assignee: (.fields.assignee.displayName // "unassigned"),
        type: .fields.issuetype.name,
        priority: .fields.priority.name,
        target_version: $tv,
        labels: .fields.labels,
        description: ([.fields.description // {} | .. | .text? // empty] | .[0:10] | join(" "))
      }' 2>/dev/null || echo "$RESULT"
    fi
    ;;

  assign)
    ASSIGNEE="${1:-}"
    echo "Assigning ${ISSUE_KEY}..."
    if [ "$JIRA_CLI" = "acli" ]; then
      if [ -n "$ASSIGNEE" ]; then
        acli jira workitem edit --key "$ISSUE_KEY" --assignee "$ASSIGNEE" --yes
      else
        acli jira workitem edit --key "$ISSUE_KEY" --assignee "@me" --yes
      fi
    else
      if [ -n "$ASSIGNEE" ]; then
        DATA=$(jq -n --arg id "$ASSIGNEE" '{"fields":{"assignee":{"accountId":$id}}}')
        jira_rest PUT "issue/${ISSUE_KEY}" "$DATA"
      else
        echo "Cannot auto-assign via REST without knowing your accountId. Use acli or pass accountId."
        exit 1
      fi
    fi
    echo "Assigned."
    ;;

  transition)
    STATUS="${1:?Usage: jira-ops.sh transition <ISSUE_KEY> <status>}"
    echo "Transitioning ${ISSUE_KEY} to '${STATUS}'..."
    if [ "$JIRA_CLI" = "acli" ]; then
      acli jira workitem transition --key "$ISSUE_KEY" --status "$STATUS" --yes 2>/dev/null || {
        echo "Transition failed. Available transitions:"
        acli jira workitem transitions --key "$ISSUE_KEY" 2>/dev/null || echo "(could not list transitions)"
        exit 1
      }
    else
      TRANSITIONS=$(jira_rest GET "issue/${ISSUE_KEY}/transitions")
      TRANSITION_ID=$(echo "$TRANSITIONS" | jq -r --arg status "$STATUS" '.transitions[] | select((.name | ascii_downcase) == ($status | ascii_downcase)) | .id' | head -1)
      if [ -n "$TRANSITION_ID" ]; then
        jira_rest POST "issue/${ISSUE_KEY}/transitions" "{\"transition\":{\"id\":\"${TRANSITION_ID}\"}}"
        echo "Transitioned to '${STATUS}'."
      else
        echo "Transition '${STATUS}' not available. Available:" >&2
        echo "$TRANSITIONS" | jq -r '.transitions[].name' 2>/dev/null >&2
        exit 1
      fi
    fi
    ;;

  check-version)
    echo "Checking Target Version for ${ISSUE_KEY}..."
    RESULT=$(jira_rest GET "issue/${ISSUE_KEY}?fields=${TV_FIELD}")
    TV_VALUE=$(extract_target_version "$RESULT")

    if [ -n "$TV_VALUE" ] && [ "$TV_VALUE" != "null" ]; then
      echo "Target Version: ${TV_VALUE}"
      echo "Backporting REQUIRED after merge."
    else
      echo "No Target Version set. Backporting not required."
    fi
    ;;

  set-version)
    VERSION="${1:?Usage: jira-ops.sh set-version <ISSUE_KEY> <version>}"
    echo "Setting Target Version on ${ISSUE_KEY} to '${VERSION}'..."
    DATA=$(jq -n --arg ver "$VERSION" --arg field "$TV_FIELD" '{fields: {($field): [{"name": $ver}]}}')
    jira_rest PUT "issue/${ISSUE_KEY}" "$DATA"
    echo "Target Version set to '${VERSION}'."
    ;;

  comment)
    COMMENT_TEXT="${1:?Usage: jira-ops.sh comment <ISSUE_KEY> <comment_text>}"
    echo "Adding comment to ${ISSUE_KEY}..."
    DATA=$(jq -n --arg body "$COMMENT_TEXT" '{
      body: {
        type: "doc",
        version: 1,
        content: [
          {
            type: "paragraph",
            content: [
              { type: "text", text: $body }
            ]
          }
        ]
      }
    }')
    jira_rest POST "issue/${ISSUE_KEY}/comment" "$DATA" && \
      echo "Comment added to ${ISSUE_KEY}." || \
      { echo "ERROR: Failed to add comment to ${ISSUE_KEY}." >&2; exit 1; }
    ;;

  *)
    echo "Unknown action: ${ACTION}"
    echo "Usage: jira-ops.sh <view|assign|transition|comment|check-version|set-version> <ISSUE_KEY> [args...]"
    exit 1
    ;;
esac
