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
#   configure-cluster.sh verify-images <KUBECONFIG> <NAMESPACE>

ACTION="${1:?Usage: configure-cluster.sh <action> [args]}"
shift

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*" >&2; }

oc_cmd() {
  oc --kubeconfig="$KC" "$@"
}

# --- detect-ocp-version --------------------------------------------------
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

# --- patch-pull-secret ---------------------------------------------------
cmd_patch_pull_secret() {
  KC="${1:?Missing KUBECONFIG path}"
  local token="${KONFLUX_IMAGE_PULL_TOKEN:?KONFLUX_IMAGE_PULL_TOKEN env var must be set to the image-rbac-proxy bearer token}"
  local proxy_host="image-rbac-proxy.apps.stone-prd-rh01.pg1f.p1.openshiftapps.com"

  info "Reading existing cluster pull secret..."
  local existing_secret
  existing_secret=$(oc_cmd get secret/pull-secret -n openshift-config \
    -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d)

  local auth_b64
  auth_b64=$(printf 'external-puller:%s' "$token" | base64 | tr -d '\n')

  info "Merging image-rbac-proxy credentials into global pull secret..."
  local merged tmpfile
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' RETURN
  merged=$(echo "$existing_secret" | jq --arg host "$proxy_host" --arg auth "$auth_b64" \
    '.auths[$host] = {"auth": $auth}')
  echo "$merged" > "$tmpfile"

  info "Patching cluster pull secret..."
  oc_cmd set data secret/pull-secret -n openshift-config \
    --from-file=.dockerconfigjson="$tmpfile"
  rm -f "$tmpfile"
  trap - RETURN

  info "Pull secret patched with image-rbac-proxy credentials."
}

# --- apply-mirrors -------------------------------------------------------
cmd_apply_mirrors() {
  KC="${1:?Missing KUBECONFIG path}"
  local quay_ver="${2:?Missing QUAY_VERSION number (e.g. 18 for stable-3.18)}"

  local ocp_version
  ocp_version=$(cmd_detect_ocp_version "$KC")
  local ocp_minor
  ocp_minor=$(echo "$ocp_version" | cut -d. -f2)

  local tenant="image-rbac-proxy.apps.stone-prd-rh01.pg1f.p1.openshiftapps.com/redhat-user-workloads/quay-eng-tenant"

  if [[ "$ocp_minor" -ge 14 ]]; then
    info "OCP ${ocp_version} detected — using ImageDigestMirrorSet (NeverContactSource)"
    # Redirect stdout to stderr: only the mirror-type token goes to stdout (for capture)
    oc_cmd apply -f - >&2 <<EOF
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: konflux-quay-mirrors
spec:
  imageDigestMirrors:
  - mirrors:
    - ${tenant}/quay-operator-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-operator-rhel8
    mirrorSourcePolicy: NeverContactSource
  - mirrors:
    - ${tenant}/quay-quay-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-rhel8
    mirrorSourcePolicy: NeverContactSource
  - mirrors:
    - ${tenant}/quay-clair-v3-${quay_ver}
    source: registry.redhat.io/quay/clair-rhel8
    mirrorSourcePolicy: NeverContactSource
  - mirrors:
    - ${tenant}/quay-bridge-operator-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-bridge-operator-rhel8
    mirrorSourcePolicy: NeverContactSource
  - mirrors:
    - ${tenant}/container-security-operator-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-container-security-operator-rhel8
    mirrorSourcePolicy: NeverContactSource
  - mirrors:
    - ${tenant}/quay-operator-bundle-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-operator-bundle
    mirrorSourcePolicy: NeverContactSource
  - mirrors:
    - ${tenant}/container-security-operator-bundle-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-container-security-operator-bundle
    mirrorSourcePolicy: NeverContactSource
  - mirrors:
    - ${tenant}/quay-bridge-operator-bundle-v3-${quay_ver}
    source: registry.redhat.io/quay/quay-bridge-operator-bundle
    mirrorSourcePolicy: NeverContactSource
  - mirrors:
    - brew.registry.redhat.io
    source: registry.stage.redhat.io
    mirrorSourcePolicy: NeverContactSource
  - mirrors:
    - brew.registry.redhat.io
    source: registry-proxy.engineering.redhat.com
    mirrorSourcePolicy: NeverContactSource
EOF
    echo "idms"
  else
    info "OCP ${ocp_version} detected — using ImageContentSourcePolicy"
    oc_cmd apply -f - >&2 <<EOF
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

# --- wait-mcp ------------------------------------------------------------
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
    local mcp_json
    mcp_json=$(oc_cmd get mcp -o json) || { info "Failed to fetch MachineConfigPools"; all_ready=false; sleep "$interval"; continue; }

    while IFS= read -r line; do
      local name updated updating degraded
      name=$(echo "$line" | jq -r '.metadata.name')
      updated=$(echo "$line" | jq -r '[.status.conditions[] | select(.type=="Updated")] | .[0].status // "Unknown"')
      updating=$(echo "$line" | jq -r '[.status.conditions[] | select(.type=="Updating")] | .[0].status // "Unknown"')
      degraded=$(echo "$line" | jq -r '[.status.conditions[] | select(.type=="Degraded")] | .[0].status // "Unknown"')

      if [[ "$updated" != "True" || "$updating" != "False" || "$degraded" != "False" ]]; then
        all_ready=false
        info "MCP ${name}: Updated=${updated} Updating=${updating} Degraded=${degraded} (${elapsed}s elapsed)"
      fi
    done < <(jq -c '.items[]' <<<"$mcp_json")

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

# --- install-storage -----------------------------------------------------
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
  local start elapsed csv_ready=false
  start=$(date +%s)
  for _ in $(seq 1 60); do
    elapsed=$(( $(date +%s) - start ))
    local phase
    phase=$(oc_cmd -n openshift-storage get csv \
      -l operators.coreos.com/odf-operator.openshift-storage \
      -o jsonpath='{.items[*].status.phase}' 2>/dev/null || true)
    if [[ "$phase" == "Succeeded" ]]; then
      info "ODF operator installed (${elapsed}s)"
      csv_ready=true
      break
    fi
    sleep 10
  done
  [[ "$csv_ready" == "true" ]] || die "ODF CSV did not reach Succeeded within 10 minutes"

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
  local noobaa_ready=false
  for _ in $(seq 1 60); do
    local phase
    phase=$(oc_cmd get noobaas noobaa -n openshift-storage \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$phase" == "Ready" ]]; then
      info "NooBaa ready."
      noobaa_ready=true
      break
    fi
    sleep 10
  done
  [[ "$noobaa_ready" == "true" ]] || die "NooBaa did not reach Ready within 10 minutes"

  info "Waiting for backing store..."
  local backing_ready=false
  for _ in $(seq 1 60); do
    local phase
    phase=$(oc_cmd get backingstore noobaa-default-backing-store -n openshift-storage \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$phase" == "Ready" ]]; then
      info "Backing store ready."
      backing_ready=true
      break
    fi
    sleep 10
  done
  [[ "$backing_ready" == "true" ]] || die "Backing store did not reach Ready within 10 minutes"

  info "Object storage installation complete."
}

# --- install-catalog -----------------------------------------------------
cmd_install_catalog() {
  KC="${1:?Missing KUBECONFIG path}"
  local fbc_image="${2:?Missing FBC image reference}"

  # CatalogSource must use quay.io — OLM's catalog pod runs in openshift-marketplace
  # and has no credentials for image-rbac-proxy. The IDMS mirrors redirect the
  # operator/operand images declared inside the catalog; the FBC index image itself
  # must be publicly pullable from quay.io.
  local catalog_image="$fbc_image"
  local proxy_host="image-rbac-proxy.apps.stone-prd-rh01.pg1f.p1.openshiftapps.com"
  if [[ "$catalog_image" == *"${proxy_host}"* ]]; then
    catalog_image="${catalog_image//${proxy_host}/quay.io}"
    info "FBC image rewritten for CatalogSource: ${proxy_host} → quay.io"
    info "  catalog image: ${catalog_image}"
  fi

  info "Creating CatalogSource for FBC image..."
  oc_cmd apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: konflux-quay-catalog
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: ${catalog_image}
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

# --- subscribe -----------------------------------------------------------
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

# --- wait-operator -------------------------------------------------------
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

# --- deploy-quay ---------------------------------------------------------
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

# --- wait-quay -----------------------------------------------------------
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

# --- verify --------------------------------------------------------------
cmd_verify() {
  KC="${1:?Missing KUBECONFIG path}"
  local ns="${2:?Missing namespace}"
  local name="${3:?Missing registry name}"

  info "Running health checks on QuayRegistry ${name}..."

  local route
  route=$(oc_cmd get route -n "$ns" \
    -l "quay-operator/quayregistry=${name}" \
    -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)

  if [[ -z "$route" ]]; then
    die "No route found for QuayRegistry in namespace ${ns}"
  fi

  local quay_url="https://${route}"
  info "Quay route: ${quay_url}"

  # Health check — fail fast if unreachable or unexpected payload
  local health_status
  health_status=$(curl -sk --connect-timeout 10 --max-time 30 \
    "${quay_url}/health/instance") || die "Health endpoint unreachable at ${quay_url}/health/instance"
  local parsed_status
  parsed_status=$(echo "$health_status" | jq -r '.data // .status' 2>/dev/null || true)
  if [[ "$parsed_status" == "true" || "$parsed_status" == "healthy" || "$parsed_status" == "OK" ]]; then
    info "Health check: OK (${parsed_status})"
  else
    die "Health check returned unhealthy status: ${parsed_status:-unparseable} — full response: ${health_status}"
  fi

  # Login page — fail fast if unreachable or Quay not present
  local login_page
  login_page=$(curl -sk --connect-timeout 10 --max-time 30 \
    "${quay_url}/") || die "Login page unreachable at ${quay_url}/"
  if echo "$login_page" | grep -qi "quay"; then
    info "Login page: accessible"
  else
    die "Login page verification failed — 'quay' not found in response from ${quay_url}/"
  fi

  echo ""
  echo "=== Verification Complete ==="
  echo "Route: ${quay_url}"
  echo "Health endpoint: ${quay_url}/health/instance"
}

# --- verify-images -------------------------------------------------------
cmd_verify_images() {
  KC="${1:?Missing KUBECONFIG path}"
  local ns="${2:?Missing namespace}"

  info "Checking pod image sources in ${ns} — expecting Konflux images from image-rbac-proxy..."

  local fail_count=0 ok_count=0 skip_count=0

  while IFS= read -r line; do
    local pod container image_id
    pod=$(echo "$line" | jq -r '.pod')
    container=$(echo "$line" | jq -r '.container')
    image_id=$(echo "$line" | jq -r '.imageID // ""')

    if [[ -z "$image_id" ]]; then
      continue
    fi

    if echo "$image_id" | grep -q "image-rbac-proxy"; then
      info "  OK   ${pod}/${container} <- Konflux (image-rbac-proxy)"
      ok_count=$((ok_count + 1))
    elif echo "$image_id" | grep -q "registry.redhat.io"; then
      info "  FAIL ${pod}/${container} <- registry.redhat.io (GA build, not Konflux RC!)"
      info "       imageID: ${image_id}"
      fail_count=$((fail_count + 1))
    else
      local registry
      registry=$(echo "$image_id" | cut -d/ -f1)
      info "  SKIP ${pod}/${container} <- ${registry} (not a mirrored Quay image)"
      skip_count=$((skip_count + 1))
    fi
  done < <(oc_cmd get pods -n "$ns" -o json | jq -c '
    .items[] | .metadata.name as $pod |
    .status.containerStatuses[]? |
    {pod: $pod, container: .name, imageID: .imageID}
  ')

  info "Image source summary: ${ok_count} from Konflux, ${fail_count} from GA registry, ${skip_count} from other"

  if [[ "$fail_count" -gt 0 ]]; then
    die "${fail_count} container(s) pulled GA images from registry.redhat.io — IDMS mirror auth may be broken or NeverContactSource not applied"
  fi

  if [[ "$ok_count" -eq 0 ]]; then
    die "No containers found pulling from image-rbac-proxy — check that IDMS mirrors are applied and pull secret is patched"
  fi

  info "Image verification passed: all Quay containers are running Konflux RC images."
}

# --- dispatch ------------------------------------------------------------
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
  verify-images)      cmd_verify_images "$@" ;;
  *)
    echo "Unknown action: ${ACTION}" >&2
    echo "Actions: detect-ocp-version, patch-pull-secret, apply-mirrors, wait-mcp," >&2
    echo "         install-storage, install-catalog, subscribe, wait-operator," >&2
    echo "         deploy-quay, wait-quay, verify, verify-images" >&2
    exit 1
    ;;
esac
