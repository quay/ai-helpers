#!/usr/bin/env bash
# SessionStart hook for konflux-build-debugger workflow.
#
# 1. Installs oc (OpenShift CLI) for cluster auth and component queries
# 2. Installs kubectl and configures kubeconfig from KONFLUX_KUBECONFIG_DATA
# 3. Installs kubectl-ka (KubeArchive plugin) for historical PipelineRun data
# 4. Installs plugins via Lola (.lola-req: konflux-ci/skills + dev plugin)
#
# Must be committed directly — symlinks do not survive ACP hydrate.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLAUDE_DIR="${WORKFLOW_DIR}/.claude"
LOLA_REQ="${WORKFLOW_DIR}/.lola-req"
LOLA="uvx --python 3.13 --from lola-ai lola"
NAMESPACE="${KONFLUX_NAMESPACE:-quay-eng-tenant}"

# ── 1. Install oc (OpenShift CLI) ────────────────────────────────────────────

if ! command -v oc &>/dev/null; then
  echo "[session-setup] Installing oc (OpenShift CLI)..."
  OC_URL="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz"
  OC_SHA_URL="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/sha256sum.txt"
  if curl -sL "$OC_URL" -o /tmp/openshift-client-linux.tar.gz 2>/dev/null \
     && curl -sL "$OC_SHA_URL" -o /tmp/oc.sha256sum 2>/dev/null; then
    if grep "openshift-client-linux.tar.gz" /tmp/oc.sha256sum | (cd /tmp && sha256sum --check --status 2>/dev/null); then
      tar xz -C /tmp -f /tmp/openshift-client-linux.tar.gz oc 2>/dev/null
      rm -f /tmp/openshift-client-linux.tar.gz /tmp/oc.sha256sum
      chmod +x /tmp/oc
      mv /tmp/oc /usr/local/bin/oc 2>/dev/null || {
        mkdir -p ~/.local/bin
        mv /tmp/oc ~/.local/bin/oc
        export PATH="$HOME/.local/bin:$PATH"
      }
      echo "[session-setup] oc $(oc version --client -o json 2>/dev/null | jq -r '.releaseClientVersion // "installed"') installed (checksum verified)"
    else
      echo "WARNING: oc checksum verification failed — skipping installation"
      rm -f /tmp/openshift-client-linux.tar.gz /tmp/oc.sha256sum
    fi
  else
    echo "WARNING: Failed to download oc CLI — cluster access requires oc"
  fi
else
  echo "[session-setup] oc already available"
fi

# ── 2. Install kubectl ──────────────────────────────────────────────────────

if ! command -v kubectl &>/dev/null; then
  echo "[session-setup] Installing kubectl..."
  KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
  curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
  if ! echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check --status 2>/dev/null; then
    echo "ERROR: kubectl checksum verification failed"
    rm -f kubectl kubectl.sha256
    exit 1
  fi
  rm -f kubectl.sha256
  chmod +x kubectl
  mv kubectl /usr/local/bin/kubectl 2>/dev/null || {
    mkdir -p ~/.local/bin
    mv kubectl ~/.local/bin/kubectl
    export PATH="$HOME/.local/bin:$PATH"
  }
  echo "[session-setup] kubectl ${KUBECTL_VERSION} installed (checksum verified)"
else
  echo "[session-setup] kubectl already available"
fi

# ── 3. Decode kubeconfig ─────────────────────────────────────────────────────

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

# ── 4. Install kubectl-ka (KubeArchive) ─────────────────────────────────────

if ! kubectl ka version &>/dev/null 2>&1; then
  echo "[session-setup] Installing kubectl-ka (KubeArchive plugin)..."
  KA_VERSION=$(curl -sL "https://api.github.com/repos/kubearchive/kubearchive/releases/latest" \
    | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"//;s/".*//' || echo "")
  if [ -n "$KA_VERSION" ]; then
    KA_URL="https://github.com/kubearchive/kubearchive/releases/download/${KA_VERSION}/kubectl-ka-linux-amd64.tar.gz"
    KA_SHA_URL="${KA_URL}.sha256"
    if curl -sL "$KA_URL" -o /tmp/kubectl-ka.tar.gz 2>/dev/null; then
      if curl -sL "$KA_SHA_URL" -o /tmp/kubectl-ka.sha256 2>/dev/null \
         && grep -q "[0-9a-f]" /tmp/kubectl-ka.sha256 2>/dev/null; then
        if ! (cd /tmp && sed "s|kubectl-ka-linux-amd64.tar.gz|kubectl-ka.tar.gz|" kubectl-ka.sha256 | sha256sum --check --status 2>/dev/null); then
          echo "WARNING: kubectl-ka checksum verification failed — skipping installation"
          rm -f /tmp/kubectl-ka.tar.gz /tmp/kubectl-ka.sha256
          KA_VERSION=""
        fi
      else
        echo "[session-setup] No kubectl-ka checksum available — installing without verification"
      fi
      if [ -n "$KA_VERSION" ]; then
        tar xz -C /tmp -f /tmp/kubectl-ka.tar.gz kubectl-ka 2>/dev/null
        rm -f /tmp/kubectl-ka.tar.gz /tmp/kubectl-ka.sha256
        chmod +x /tmp/kubectl-ka
        mv /tmp/kubectl-ka /usr/local/bin/kubectl-ka 2>/dev/null || {
          mkdir -p ~/.local/bin
          mv /tmp/kubectl-ka ~/.local/bin/kubectl-ka
          export PATH="$HOME/.local/bin:$PATH"
        }
        echo "[session-setup] kubectl-ka ${KA_VERSION} installed"
      fi
    else
      echo "WARNING: Failed to download kubectl-ka — KubeArchive fallback unavailable"
    fi
  else
    echo "WARNING: Could not determine kubectl-ka version — KubeArchive fallback unavailable"
  fi
else
  echo "[session-setup] kubectl-ka already available"
fi

# Configure KubeArchive host from the cluster's ConfigMap
if command -v kubectl &>/dev/null && [ -f ~/.kube/config ]; then
  KA_HOST=$(kubectl get cm -n product-kubearchive kubearchive-api-url -o jsonpath='{.data.URL}' 2>/dev/null || echo "")
  if [ -n "$KA_HOST" ]; then
    kubectl ka config set host "$KA_HOST" 2>/dev/null || true
    echo "[session-setup] KubeArchive configured: ${KA_HOST}"
  else
    echo "WARNING: Could not discover KubeArchive host — historical log retrieval unavailable"
  fi
fi

# ── 5. Install plugins via Lola ──────────────────────────────────────────────

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
    $LOLA install "$name" -a claude-code --scope project --force "$WORKFLOW_DIR" 2>&1
  done < "$LOLA_REQ"

  if [ -n "$(ls -A "${CLAUDE_DIR}/skills" 2>/dev/null)" ]; then
    echo "[session-setup] Skills installed: $(ls "${CLAUDE_DIR}/skills" 2>/dev/null | tr '\n' ' ')"
  fi
  if [ -n "$(ls -A "${CLAUDE_DIR}/scripts" 2>/dev/null)" ]; then
    echo "[session-setup] Scripts installed: $(ls "${CLAUDE_DIR}/scripts" 2>/dev/null | tr '\n' ' ')"
  fi
fi

echo "[session-setup] Setup complete"
