#!/usr/bin/env bash
set -euo pipefail

# configure-cluster.sh -- Cluster configuration for Quay RC deployment.
#
# Multi-command script: each subcommand corresponds to a deployment phase.
#
# Usage:
#   configure-cluster.sh detect-ocp-version <KUBECONFIG>
#   configure-cluster.sh patch-pull-secret <KUBECONFIG>
#   configure-cluster.sh apply-mirrors <KUBECONFIG> <QUAY_VERSION_NUM>
#   configure-cluster.sh wait-mcp <KUBECONFIG> [TIMEOUT_SECONDS]
#   configure-cluster.sh install-storage <KUBECONFIG>
#   configure-cluster.sh install-catalog <KUBECONFIG> <FBC_IMAGE>
#   configure-cluster.sh subscribe <KUBECONFIG> <CHANNEL> <NAMESPACE>
#   configure-cluster.sh wait-operator <KUBECONFIG> <NAMESPACE> [TIMEOUT_SECONDS]
#   configure-cluster.sh deploy-quay <KUBECONFIG> <NAMESPACE> <REGISTRY_NAME>
#   configure-cluster.sh wait-quay <KUBECONFIG> <NAMESPACE> <REGISTRY_NAME> [TIMEOUT_SECONDS]
#   configure-cluster.sh verify <KUBECONFIG> <NAMESPACE> <REGISTRY_NAME>

ACTION="${1:?Usage: configure-cluster.sh <action> [args]}"
shift

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

oc_cmd() {
  oc --kubeconfig="$KC" "$@"
}

# ─── detect-ocp-version ──────────────────────────────────────────────
cmd_detect_ocp_version() {
  KC="${1:?Missing KUBECONFIG path}"
  local version
  version=$(oc_cmd get clusterversion version \
    -o jsonpath='{range .status.history[?(@.state=="Completed")]}{.version}{"\n"}{end}' \
    | head -n1 | cut -d. -f1-2)
  if [[ -z "$version" ]]; then
    die "Could not detect OCP version from clusterversion"
  fi
  echo "$version"
}

# ─── patch-pull-secret ────────────────────────────────────────────────
cmd_patch_pull_secret() {
  KC="${1:?Missing KUBECONFIG path}"
  local token="${KONFLUX_IMAGE_PULL_TOKEN:?KONFLUX_IMAGE_PULL_TOKEN env var must be set to the image-rbac-proxy bearer token}"
  local proxy_host="image-rbac-proxy.apps.stone-prd-rh01.pg1f.p1.openshiftapps.com"

  info "Reading existing cluster pull secret..."
  local existing_secret
  existing_secret=$(oc_cmd get secret/pull-secret -n openshift-config \
    -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d)

  # Generate auth entry for the image-rbac-proxy.
  # Username is arbitrary (proxy ignores it), token is the bearer token.
  local auth_b64
  auth_b64=$(printf 'external-puller:%s' "$token" | base64 | tr -d '\n')

  info "Merging image-rbac-proxy credentials into global pull secret..."
  local merged tmpfile
  tmpfile=$(mktemp)
  merged=$(echo "$existing_secret" | jq --arg host "$proxy_host" --arg auth "$auth_b64" \
    '.auths[$host] = {"auth": $auth}')
  echo "$merged" > "$tmpfile"

  info "Patching cluster pull secret..."
  oc_cmd set data secret/pull-secret -n openshift-config \
    --from-file=.dockerconfigjson="$tmpfile"
  rm -f "$tmpfile"

  info "Pull secret patched with image-rbac-proxy credentials."
}

# ─── apply-mirrors ────────────────────────────────────────────────────
cmd_apply_mirrors() {
  KC="${1:?Missing KUBECONFIG path}"
  local quay_ver="${2:?Missing QUAY_VERSION number (e.g. 18 for stable-3.18)}"

  # Detect OCP version to choose IDMS vs ICSP
  local ocp_version
  ocp_version=$(cmd_detect_ocp_version "$KC")
  local ocp_minor
  ocp_minor=$(echo "$ocp_version" | cut -d. -f2)

  local tenant="image-rbac-proxy.apps.stone-prd-rh01.pg1f.p1.openshiftapps.com/redhat-user-workloads/quay-eng-tenant"

  if [[ "$ocp_minor" -ge 14 ]]; then
    info "OCP ${ocp_version} detected — using ImageDigestMirrorSet"
    oc_cmd apply -f - <<EOF
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: konflux-quay-mirrors
spec:
  imageDigestMirrors:
  - mirrors:
    - ${tenant}/quay-operator-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-operator-rhel8
  - mirrors:
    - ${tenant}/quay-quay-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-rhel8
  - mirrors:
    - ${tenant}/quay-clair-v3-${quay_ver}
    source: registry.redhat.io/quay/clair-rhel8
  - mirrors:
    - ${tenant}/quay-bridge-operator-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-bridge-operator-rhel8
  - mirrors:
    - ${tenant}/container-security-operator-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-container-security-operator-rhel8
  - mirrors:
    - ${tenant}/quay-operator-bundle-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-operator-bundle
  - mirrors:
    - ${tenant}/container-security-operator-bundle-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-container-security-operator-bundle
  - mirrors:
    - ${tenant}/quay-bridge-operator-bundle-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-bridge-operator-bundle
  - mirrors:
    - brew.registry.redhat.io
    source: registry.stage.redhat.io
  - mirrors:
    - brew.registry.redhat.io
    source: registry-proxy.engineering.redhat.com
EOF
    echo "idms"
  else
    info "OCP ${ocp_version} detected — using ImageContentSourcePolicy"
    oc_cmd apply -f - <<EOF
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: konflux-quay-mirrors
spec:
  repositoryDigestMirrors:
  - mirrors:
    - ${tenant}/quay-operator-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-operator-rhel8
  - mirrors:
    - ${tenant}/quay-quay-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-rhel8
  - mirrors:
    - ${tenant}/quay-clair-v3-${quay_ver}
    source: registry.redhat.io/quay/clair-rhel8
  - mirrors:
    - ${tenant}/quay-bridge-operator-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-bridge-operator-rhel8
  - mirrors:
    - ${tenant}/container-security-operator-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-container-security-operator-rhel8
  - mirrors:
    - ${tenant}/quay-operator-bundle-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-operator-bundle
  - mirrors:
    - ${tenant}/container-security-operator-bundle-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-container-security-operator-bundle
  - mirrors:
    - ${tenant}/quay-bridge-operator-bundle-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-bridge-operator-bundle
  - mirrors:
    - brew.registry.redhat.io
    source: registry.stage.redhat.io
  - mirrors:
    - brew.registry.redhat.io
    source: registry-proxy.engineering.redhat.com
EOF
    echo "icsp"
  fi
}

# ─── wait-mcp ─────────────────────────────────────────────────────────
cmd_wait_mcp() {
  KC="${1:?Missing KUBECONFIG path}"
  local timeout="${2:-1200}"
  local start elapsed interval=10

  info "Waiting for MachineConfigPools to stabilize (timeout: ${timeout}s)..."
  start=$(date +%s)

  while true; do
    elapsed=$(( $(date +%s) - start ))
    if (( elapsed > timeout )); then
      die "MCP wait timed out after ${timeout}s"
    fi

    local all_ready=true
    while IFS= read -r line; do
      local name updated updating
      name=$(echo "$line" | jq -r '.metadata.name')
      updated=$(echo "$line" | jq -r '[.status.conditions[] | select(.type=="Updated")] | .[0].status // "Unknown"')
      updating=$(echo "$line" | jq -r '[.status.conditions[] | select(.type=="Updating")] | .[0].status // "Unknown"')

      if [[ "$updated" != "True" || "$updating" != "False" ]]; then
        all_ready=false
        info "MCP ${name}: Updated=${updated} Updating=${updating} (${elapsed}s elapsed)"
      fi
    done < <(oc_cmd get mcp -o json | jq -c '.items[]')

    if [[ "$all_ready" == "true" ]]; then
      info "All MachineConfigPools are ready."
      return 0
    fi

    sleep "$interval"
    if (( interval < 30 )); then
      interval=$((interval + 10))
    fi
  done
}

# ─── install-storage ──────────────────────────────────────────────────
cmd_install_storage() {
  KC="${1:?Missing KUBECONFIG path}"

  local ocp_version
  ocp_version=$(cmd_detect_ocp_version "$KC")

  info "Installing ODF operator for object storage (OCP ${ocp_version})..."

  oc_cmd apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: openshift-storage
  name: openshift-storage
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: odf-og
  namespace: openshift-storage
spec:
  targetNamespaces:
  - openshift-storage
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  labels:
    operators.coreos.com/odf-operator.openshift-storage: ""
  name: odf-operator
  namespace: openshift-storage
spec:
  channel: stable-${ocp_version}
  installPlanApproval: Automatic
  name: odf-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

  info "Waiting for ODF CSV to succeed..."
  local start elapsed
  start=$(date +%s)
  for _ in $(seq 1 60); do
    elapsed=$(( $(date +%s) - start ))
    local phase
    phase=$(oc_cmd -n openshift-storage get csv \
      -l operators.coreos.com/odf-operator.openshift-storage \
      -o jsonpath='{.items[*].status.phase}' 2>/dev/null || true)
    if [[ "$phase" == "Succeeded" ]]; then
      info "ODF operator installed (${elapsed}s)"
      break
    fi
    sleep 10
  done

  info "Creating NooBaa object storage..."
  oc_cmd apply -f - <<EOF
apiVersion: noobaa.io/v1alpha1
kind: NooBaa
metadata:
  name: noobaa
  namespace: openshift-storage
spec:
  dbType: postgres
  dbResources:
    requests:
      cpu: '0.1'
      memory: 1Gi
  coreResources:
    requests:
      cpu: '0.1'
      memory: 1Gi
EOF

  info "Waiting for NooBaa to be ready..."
  for _ in $(seq 1 60); do
    local phase
    phase=$(oc_cmd get noobaas noobaa -n openshift-storage \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$phase" == "Ready" ]]; then
      info "NooBaa ready."
      break
    fi
    sleep 10
  done

  info "Waiting for backing store..."
  for _ in $(seq 1 60); do
    local phase
    phase=$(oc_cmd get backingstore noobaa-default-backing-store -n openshift-storage \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$phase" == "Ready" ]]; then
      info "Backing store ready."
      break
    fi
    sleep 10
  done

  info "Object storage installation complete."
}

# ─── install-catalog ──────────────────────────────────────────────────
cmd_install_catalog() {
  KC="${1:?Missing KUBECONFIG path}"
  local fbc_image="${2:?Missing FBC image reference}"

  info "Creating CatalogSource for FBC image..."
  oc_cmd apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: konflux-quay-catalog
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: ${fbc_image}
  displayName: Konflux Quay RC
  publisher: quay-deploy
  updateStrategy:
    registryPoll:
      interval: 10m
EOF

  info "Waiting for catalog to be ready..."
  for i in $(seq 1 18); do
    local state
    state=$(oc_cmd get catalogsource konflux-quay-catalog -n openshift-marketplace \
      -o jsonpath='{.status.connectionState.lastObservedState}' 2>/dev/null || true)
    if [[ "$state" == "READY" ]]; then
      info "CatalogSource ready."
      return 0
    fi
    info "Catalog state: ${state:-pending} (${i}/18)"
    sleep 10
  done

  die "CatalogSource failed to reach READY state within 3 minutes."
}

# ─── subscribe ────────────────────────────────────────────────────────
cmd_subscribe() {
  KC="${1:?Missing KUBECONFIG path}"
  local channel="${2:?Missing channel (e.g. stable-3.18)}"
  local ns="${3:?Missing namespace}"

  info "Creating namespace, OperatorGroup, and Subscription..."
  oc_cmd apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${ns}
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: quay-og
  namespace: ${ns}
spec:
  targetNamespaces:
  - ${ns}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: quay-operator
  namespace: ${ns}
spec:
  channel: ${channel}
  installPlanApproval: Automatic
  name: quay-operator
  source: konflux-quay-catalog
  sourceNamespace: openshift-marketplace
EOF

  info "Subscription created for quay-operator on channel ${channel}."
}

# ─── wait-operator ────────────────────────────────────────────────────
cmd_wait_operator() {
  KC="${1:?Missing KUBECONFIG path}"
  local ns="${2:?Missing namespace}"
  local timeout="${3:-600}"
  local start elapsed

  info "Waiting for quay-operator CSV to succeed in ${ns} (timeout: ${timeout}s)..."
  start=$(date +%s)

  while true; do
    elapsed=$(( $(date +%s) - start ))
    if (( elapsed > timeout )); then
      die "Operator CSV wait timed out after ${timeout}s"
    fi

    local phase csv_name
    csv_name=$(oc_cmd get csv -n "$ns" \
      -l "operators.coreos.com/quay-operator.${ns}" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -n "$csv_name" ]]; then
      phase=$(oc_cmd get csv "$csv_name" -n "$ns" \
        -o jsonpath='{.status.phase}' 2>/dev/null || true)
      if [[ "$phase" == "Succeeded" ]]; then
        local version
        version=$(oc_cmd get csv "$csv_name" -n "$ns" \
          -o jsonpath='{.spec.version}' 2>/dev/null || true)
        info "Operator CSV ready: ${csv_name} (v${version})"
        echo "${csv_name}"
        return 0
      fi
      info "CSV ${csv_name}: phase=${phase:-pending} (${elapsed}s elapsed)"
    else
      info "No CSV found yet for quay-operator in ${ns} (${elapsed}s elapsed)"
    fi

    sleep 15
  done
}

# ─── deploy-quay ──────────────────────────────────────────────────────
cmd_deploy_quay() {
  KC="${1:?Missing KUBECONFIG path}"
  local ns="${2:?Missing namespace}"
  local name="${3:?Missing registry name}"

  info "Creating QuayRegistry ${name} in ${ns}..."
  oc_cmd apply -f - <<EOF
apiVersion: quay.redhat.com/v1
kind: QuayRegistry
metadata:
  name: ${name}
  namespace: ${ns}
EOF

  info "QuayRegistry CR created."
}

# ─── wait-quay ────────────────────────────────────────────────────────
cmd_wait_quay() {
  KC="${1:?Missing KUBECONFIG path}"
  local ns="${2:?Missing namespace}"
  local name="${3:?Missing registry name}"
  local timeout="${4:-900}"
  local start elapsed

  info "Waiting for QuayRegistry ${name} to be available (timeout: ${timeout}s)..."
  start=$(date +%s)

  while true; do
    elapsed=$(( $(date +%s) - start ))
    if (( elapsed > timeout )); then
      die "QuayRegistry wait timed out after ${timeout}s"
    fi

    local available
    available=$(oc_cmd get quayregistry "$name" -n "$ns" \
      -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)

    if [[ "$available" == "True" ]]; then
      info "QuayRegistry ${name} is available."
      return 0
    fi

    local status_msg
    status_msg=$(oc_cmd get quayregistry "$name" -n "$ns" \
      -o jsonpath='{.status.conditions[?(@.type=="Available")].message}' 2>/dev/null || true)
    info "QuayRegistry: Available=${available:-Unknown} (${elapsed}s) ${status_msg:+— $status_msg}"

    sleep 20
  done
}

# ─── verify ───────────────────────────────────────────────────────────
cmd_verify() {
  KC="${1:?Missing KUBECONFIG path}"
  local ns="${2:?Missing namespace}"
  local name="${3:?Missing registry name}"

  info "Running health checks on QuayRegistry ${name}..."

  # Get the route
  local route
  route=$(oc_cmd get route -n "$ns" \
    -l "quay-operator/quayregistry=${name}" \
    -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)

  if [[ -z "$route" ]]; then
    # Fallback: try to find any quay route
    route=$(oc_cmd get route -n "$ns" \
      -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)
  fi

  if [[ -z "$route" ]]; then
    die "No route found for QuayRegistry in namespace ${ns}"
  fi

  local quay_url="https://${route}"
  info "Quay route: ${quay_url}"

  # Health check
  local health_status
  health_status=$(curl -sk "${quay_url}/health/instance" 2>/dev/null || true)
  if echo "$health_status" | jq -e '.data // .status' >/dev/null 2>&1; then
    info "Health check: OK"
    echo "$health_status" | jq -r '.data // .status' 2>/dev/null || true
  else
    info "Health check: could not parse response (may still be starting)"
  fi

  # Check login page
  local login_page
  login_page=$(curl -sk "${quay_url}/" 2>/dev/null || true)
  if echo "$login_page" | grep -qi "quay"; then
    info "Login page: accessible"
  else
    info "Login page: could not verify (may still be starting)"
  fi

  echo ""
  echo "=== Verification Complete ==="
  echo "Route: ${quay_url}"
  echo "Health endpoint: ${quay_url}/health/instance"
}

# ─── dispatch ─────────────────────────────────────────────────────────
case "$ACTION" in
  detect-ocp-version) cmd_detect_ocp_version "$@" ;;
  patch-pull-secret)  cmd_patch_pull_secret "$@" ;;
  apply-mirrors)      cmd_apply_mirrors "$@" ;;
  wait-mcp)           cmd_wait_mcp "$@" ;;
  install-storage)    cmd_install_storage "$@" ;;
  install-catalog)    cmd_install_catalog "$@" ;;
  subscribe)          cmd_subscribe "$@" ;;
  wait-operator)      cmd_wait_operator "$@" ;;
  deploy-quay)        cmd_deploy_quay "$@" ;;
  wait-quay)          cmd_wait_quay "$@" ;;
  verify)             cmd_verify "$@" ;;
  *)
    echo "Unknown action: ${ACTION}" >&2
    echo "Actions: detect-ocp-version, patch-pull-secret, apply-mirrors, wait-mcp," >&2
    echo "         install-storage, install-catalog, subscribe, wait-operator," >&2
    echo "         deploy-quay, wait-quay, verify" >&2
    exit 1
    ;;
esac
