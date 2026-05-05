#!/bin/bash
# session-setup.sh -- One-time session bootstrap for development.
#
# Handles: session state restore, acli install+auth, pre-commit, gh auth check.
# Runs automatically via SessionStart hook, or manually.
#
# Environment variables:
#   ACLI_DOWNLOAD_URL  — acli binary URL (default: Linux amd64 latest)
#   ACLI_INSTALL_DIR   — installation directory (default: ~/.local/bin)
#   JIRA_DOMAIN        — JIRA instance (default: redhat.atlassian.net)
#   JIRA_DEFAULT_EMAIL — fallback JIRA email (default: quay-devel@redhat.com)

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SETUP_MARKER="${HOME}/.session-setup-done"

: "${ACLI_DOWNLOAD_URL:=https://acli.atlassian.com/linux/latest/acli_linux_amd64/acli}"
: "${ACLI_INSTALL_DIR:=${HOME}/.local/bin}"
: "${JIRA_DOMAIN:=redhat.atlassian.net}"
: "${JIRA_DEFAULT_EMAIL:=quay-devel@redhat.com}"

echo "=== Session Bootstrap ==="

# ── 1. Restore session state (always runs, even on re-entry) ────
STATE_FILE="${REPO_ROOT}/.claude/session-state/current.json"
CONTEXT=""
if [ -f "$STATE_FILE" ]; then
  echo "[1/4] Restoring previous session state..."
  BRANCH=$(jq -r '.branch // empty' "$STATE_FILE" 2>/dev/null || true)
  TICKET=$(jq -r '.ticket // empty' "$STATE_FILE" 2>/dev/null || true)
  PR_NUM=$(jq -r '.pr_number // empty' "$STATE_FILE" 2>/dev/null || true)
  SAVED_AT=$(jq -r '.saved_at // empty' "$STATE_FILE" 2>/dev/null || true)

  CONTEXT="Previous session state (saved ${SAVED_AT}):"
  [ -n "$BRANCH" ] && CONTEXT="${CONTEXT} branch=${BRANCH}"
  [ -n "$TICKET" ] && CONTEXT="${CONTEXT}, ticket=${TICKET}"
  [ -n "$PR_NUM" ] && CONTEXT="${CONTEXT}, PR=#${PR_NUM}"
  echo "  ${CONTEXT}"
else
  echo "[1/4] No previous session state found."
fi

# Skip expensive bootstrap if already done this session
if [ -f "$SETUP_MARKER" ]; then
  echo "Session already bootstrapped. Delete ${SETUP_MARKER} to re-run."
  if [ -n "$CONTEXT" ]; then
    jq -n --arg ctx "$CONTEXT" \
      '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
  fi
  exit 0
fi

# ── 2. acli ──────────────────────────────────────────────────────
if ! command -v acli &>/dev/null; then
  echo "[2/4] Installing acli..."
  mkdir -p "$ACLI_INSTALL_DIR"
  curl -sSL -o "${ACLI_INSTALL_DIR}/acli" "$ACLI_DOWNLOAD_URL"
  chmod +x "${ACLI_INSTALL_DIR}/acli"
  export PATH="${ACLI_INSTALL_DIR}:${PATH}"
  echo "  Installed to ${ACLI_INSTALL_DIR}/acli"
else
  echo "[2/4] acli already installed."
fi

# Auth acli if credentials available
if command -v acli &>/dev/null; then
  if ! acli jira auth status &>/dev/null; then
    token="${JIRA_API_TOKEN:-}"
    email="${JIRA_USER:-${JIRA_DEFAULT_EMAIL}}"
    if [ -n "$token" ]; then
      echo "$token" | acli jira auth login \
        --site "${JIRA_DOMAIN}" \
        --email "$email" --token 2>/dev/null && echo "  acli authenticated as ${email}." \
        || echo "  Warning: acli auth failed. Run manually: acli jira auth login --site ${JIRA_DOMAIN} --email ${email} --token"
    else
      echo "  Warning: No JIRA_API_TOKEN set. Set it or run: acli jira auth login --site ${JIRA_DOMAIN} --email <email> --token"
    fi
  else
    echo "  acli already authenticated."
  fi
fi

# ── 3. pre-commit ───────────────────────────────────────────────
echo "[3/4] Checking pre-commit hooks..."
if [ -f "${REPO_ROOT}/.pre-commit-config.yaml" ]; then
  if command -v pre-commit &>/dev/null; then
    (cd "$REPO_ROOT" && pre-commit install --allow-missing-config 2>/dev/null) && echo "  pre-commit hooks installed." || echo "  pre-commit install failed (non-fatal)."
  else
    echo "  pre-commit not found (hooks will run in CI)."
  fi
else
  echo "  No .pre-commit-config.yaml found."
fi

# ── 4. gh CLI ───────────────────────────────────────────────────
echo "[4/4] Checking GitHub CLI auth..."
if command -v gh &>/dev/null; then
  if gh auth status &>/dev/null; then
    echo "  gh authenticated."
  else
    echo "  Warning: gh not authenticated. Run: gh auth login"
  fi
else
  echo "  Warning: gh CLI not found."
fi

# Mark complete
touch "$SETUP_MARKER"
echo "=== Bootstrap complete ==="

# Inject restored context into the model
if [ -n "$CONTEXT" ]; then
  jq -n --arg ctx "$CONTEXT" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
fi
