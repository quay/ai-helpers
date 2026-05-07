#!/usr/bin/env bash
# SessionStart hook for konflux-build-triage workflow.
#
# 1. Installs kubectl and configures kubeconfig from KONFLUX_KUBECONFIG_DATA
# 2. Installs notebooklm-mcp-cli for NotebookLM MCP access
# 3. Installs plugins via Lola (.lola-req: konflux-ci/skills + dev plugin)
# 4. Discovers Konflux components and caches the component-to-repo map
#
# Must be committed directly — symlinks do not survive ACP hydrate.sh.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CLAUDE_DIR="${REPO_ROOT}/.claude"
LOLA_REQ="${REPO_ROOT}/.lola-req"
LOLA="uvx --python 3.13 --from lola-ai lola"
NAMESPACE="${KONFLUX_NAMESPACE:-quay-eng-tenant}"

# ── 1. Install kubectl ──────────────────────────────────────────────────────

if ! command -v kubectl &>/dev/null; then
  echo "[session-setup] Installing kubectl..."
  KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
  curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x kubectl
  mv kubectl /usr/local/bin/kubectl 2>/dev/null || {
    mkdir -p ~/.local/bin
    mv kubectl ~/.local/bin/kubectl
    export PATH="$HOME/.local/bin:$PATH"
  }
  echo "[session-setup] kubectl ${KUBECTL_VERSION} installed"
else
  echo "[session-setup] kubectl already available"
fi

# ── 2. Decode kubeconfig ─────────────────────────────────────────────────────

if [ -n "${KONFLUX_KUBECONFIG_DATA:-}" ]; then
  echo "[session-setup] Configuring kubeconfig..."
  mkdir -p ~/.kube
  echo "${KONFLUX_KUBECONFIG_DATA}" | base64 -d > ~/.kube/config
  chmod 600 ~/.kube/config

  if kubectl get pipelineruns -n "$NAMESPACE" --no-headers 2>/dev/null | head -1 > /dev/null; then
    echo "[session-setup] Cluster access validated (namespace: ${NAMESPACE})"
  else
    echo "WARNING: Cannot list pipelineruns in ${NAMESPACE} — check kubeconfig and permissions"
  fi
else
  echo "WARNING: KONFLUX_KUBECONFIG_DATA not set — cluster access unavailable"
fi

# ── 3. Install notebooklm-mcp-cli ───────────────────────────────────────────

if ! command -v notebooklm-mcp &>/dev/null; then
  echo "[session-setup] Installing notebooklm-mcp-cli..."
  uv tool install notebooklm-mcp-cli 2>&1 | tail -3
  echo "[session-setup] notebooklm-mcp-cli installed"
else
  echo "[session-setup] notebooklm-mcp-cli already available"
fi

if [ -z "${NOTEBOOKLM_COOKIES:-}" ]; then
  echo "WARNING: NOTEBOOKLM_COOKIES not set — NotebookLM consultation will be skipped (graceful degradation)"
fi

# ── 4. Install plugins via Lola ──────────────────────────────────────────────

if [ ! -f "$LOLA_REQ" ]; then
  echo "[session-setup] No .lola-req found, skipping plugin install"
else
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [ -z "$line" ] && continue

    url="${line%% --*}"
    content_dir=""
    if [[ "$line" == *"--module-content="* ]]; then
      content_dir="${line#*--module-content=}"
      content_dir="${content_dir%% *}"
    fi

    name="$(basename "${content_dir:-$url}" | sed 's/\.git$//')"

    echo "[session-setup] Installing plugin: ${name}"
    if [ -n "$content_dir" ]; then
      $LOLA mod add "$url" --module-content="$content_dir" --name "$name" 2>&1 | tail -1
    else
      $LOLA mod add "$url" --name "$name" 2>&1 | tail -1
    fi
    $LOLA install "$name" -a claude-code --scope project --force "$REPO_ROOT" 2>&1
  done < "$LOLA_REQ"

  if [ -n "$(ls -A "${CLAUDE_DIR}/skills" 2>/dev/null)" ]; then
    echo "[session-setup] Skills installed: $(ls "${CLAUDE_DIR}/skills" 2>/dev/null | tr '
' ' ')"
  fi
  if [ -n "$(ls -A "${CLAUDE_DIR}/scripts" 2>/dev/null)" ]; then
    echo "[session-setup] Scripts installed: $(ls "${CLAUDE_DIR}/scripts" 2>/dev/null | tr '
' ' ')"
  fi
fi

# ── 5. Discover Konflux components ──────────────────────────────────────────

if command -v kubectl &>/dev/null && [ -f ~/.kube/config ]; then
  echo "[session-setup] Discovering Konflux components..."
  bash "${REPO_ROOT}/scripts/discover-components.sh" 2>&1
else
  echo "[session-setup] Skipping component discovery (no cluster access)"
fi

echo "[session-setup] Setup complete"
