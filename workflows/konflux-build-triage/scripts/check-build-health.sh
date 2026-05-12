#!/usr/bin/env bash
# check-build-health.sh — Show build health of all Konflux components
#
# For each component in the namespace, checks whether its latest on-push
# PipelineRun succeeded or failed. Outputs JSON grouped by application.

set -euo pipefail

# Defaults (env vars take precedence, CLI flags override both)
NAMESPACE="${KONFLUX_NAMESPACE:-quay-eng-tenant}"
APPLICATION=""
EXCLUDE_APP_REGEX="${EXCLUDE_APP_REGEX:-}"
FAILED_ONLY=false
TABLE_OUTPUT=false
CONCURRENCY=20

usage() {
  cat <<'EOF'
Usage: check-build-health.sh [OPTIONS]

Show build health of all Konflux components by checking their latest
on-push PipelineRun via KubeArchive.

Options:
  -n, --namespace NS     Namespace (default: quay-eng-tenant)
  -a, --application APP  Filter to a single application
  -e, --exclude REGEX    Exclude applications matching regex (or EXCLUDE_APP_REGEX env)
  -f, --failed-only      Only show components with failed builds
  -t, --table            Human-readable table output instead of JSON
  -P, --parallel N       Max parallel queries (default: 20)
  -h, --help             Show this help
EOF
  exit 0
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace) NAMESPACE="$2"; shift 2 ;;
    -a|--application) APPLICATION="$2"; shift 2 ;;
    -e|--exclude) EXCLUDE_APP_REGEX="$2"; shift 2 ;;
    -f|--failed-only) FAILED_ONLY=true; shift ;;
    -t|--table) TABLE_OUTPUT=true; shift ;;
    -P|--parallel) CONCURRENCY="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

# Check prerequisites
for cmd in curl jq oc python3; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is required but not found" >&2
    exit 1
  fi
done

# Auth token
TOKEN=$(oc whoami -t 2>/dev/null) || {
  echo "Error: Not logged in. Run: oc login" >&2
  exit 1
}

# Discover KubeArchive host
KA_HOST=$(oc get cm -n product-kubearchive kubearchive-api-url -o jsonpath='{.data.URL}' 2>/dev/null) || true
if [[ -z "$KA_HOST" ]]; then
  KA_HOST="https://kubearchive-api-server-product-kubearchive.apps.$(oc whoami --show-server | sed -E 's|^.*api\.?(.*):[0-9]+$|\1|')"
fi

# Verify KubeArchive connectivity
if ! curl -s -f -o /dev/null -H "Authorization: Bearer ${TOKEN}" "${KA_HOST}/livez" 2>/dev/null; then
  echo "Error: Cannot reach KubeArchive at ${KA_HOST}" >&2
  exit 1
fi

# URL-encode a string
urlencode() {
  python3 -c "import urllib.parse; print(urllib.parse.quote('$1', safe=''))"
}

# Temp dir for parallel results
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Get all components from cluster
COMPONENTS_JSON=$(oc get components -n "$NAMESPACE" -o json 2>/dev/null) || {
  echo "Error: Failed to get components from namespace ${NAMESPACE}" >&2
  exit 1
}

# Extract component metadata, filter by application/exclusion
JQ_APP_FILTER="true"
if [[ -n "$APPLICATION" ]]; then
  JQ_APP_FILTER=".spec.application == \$app"
fi
JQ_EXCLUDE="true"
if [[ -n "$EXCLUDE_APP_REGEX" ]]; then
  JQ_EXCLUDE="(.spec.application | test(\$exclude) | not)"
fi

echo "$COMPONENTS_JSON" | jq -r --arg app "$APPLICATION" --arg exclude "$EXCLUDE_APP_REGEX" \
  ".items[] | select(${JQ_APP_FILTER}) | select(${JQ_EXCLUDE}) | [.metadata.name, .spec.application, (.spec.source.git.url // \"\"), (.spec.source.git.revision // \"\")] | @tsv" > "$TMPDIR/components.tsv"

TOTAL=$(wc -l < "$TMPDIR/components.tsv" | tr -d ' ')
if [[ "$TOTAL" -eq 0 ]]; then
  echo "No components found." >&2
  exit 0
fi

if [[ "$TABLE_OUTPUT" == "true" ]]; then
  echo "Checking ${TOTAL} components..." >&2
fi

# Function to query latest on-push PLR for a single component
query_component() {
  local comp_name="$1"
  local label_selector="pipelinesascode.tekton.dev/event-type=push,pipelines.appstudio.openshift.io/type=build,appstudio.openshift.io/component=${comp_name}"
  local encoded_label
  encoded_label=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${label_selector}', safe=''))")

  local response
  response=$(curl -s -f -H "Authorization: Bearer ${TOKEN}" \
    "${KA_HOST}/apis/tekton.dev/v1/namespaces/${NAMESPACE}/pipelineruns?labelSelector=${encoded_label}&limit=20" 2>/dev/null \
    | tr -d '\000-\010\013\014\016-\037') || true

  if [[ -z "$response" ]]; then
    echo "${comp_name}	null	" > "$TMPDIR/result_${comp_name}"
    return
  fi

  local status
  status=$(echo "$response" | jq -r '
    if (.items | length) == 0 then "null\t\t"
    else
      ((.items | max_by(.metadata.creationTimestamp)) |
        (if (first(.status.conditions // [] | .[] | select(.type == "Succeeded")) | .status) == "False" then "true"
         elif (first(.status.conditions // [] | .[] | select(.type == "Succeeded")) | .status) == "True" then "false"
         else "null" end) + "\t" +
        (.metadata.creationTimestamp // "") + "\t" +
        (.metadata.name // ""))
    end
  ' 2>/dev/null) || status="null\t\t"

  echo "${comp_name}	${status}" > "$TMPDIR/result_${comp_name}"
}

export -f query_component urlencode
export TOKEN KA_HOST NAMESPACE TMPDIR

# Run queries in parallel
cut -f1 "$TMPDIR/components.tsv" | xargs -P "$CONCURRENCY" -I{} bash -c 'query_component "$@"' _ {}

# Merge results and build output
# result files: component_name\tbuild_failed\tlast_build_time
# components.tsv: component_name\tapplication\tsource\tbranch

if [[ "$TABLE_OUTPUT" == "true" ]]; then
  # Table output
  printf "\n%-8s  %-45s  %-25s  %-20s  %s\n" "STATUS" "COMPONENT" "APPLICATION" "LAST BUILD" "SOURCE"
  printf "%s\n" "$(printf '━%.0s' {1..140})"

  while IFS=$'\t' read -r comp_name app source branch; do
    if [[ -f "$TMPDIR/result_${comp_name}" ]]; then
      IFS=$'\t' read -r _ build_failed last_build plr_name < "$TMPDIR/result_${comp_name}"
    else
      build_failed="null"
      last_build=""
    fi

    if [[ "$FAILED_ONLY" == "true" && "$build_failed" != "true" ]]; then
      continue
    fi

    local_status="OK"
    if [[ "$build_failed" == "true" ]]; then
      local_status="FAIL"
    elif [[ "$build_failed" == "null" ]]; then
      local_status="N/A"
    fi

    # Truncate source for display
    short_source="${source##*/}"
    short_source="${short_source%.git}"
    [[ -n "$branch" ]] && short_source="${short_source}@${branch}"

    printf "%-8s  %-45s  %-25s  %-20s  %s\n" "$local_status" "$comp_name" "$app" "${last_build:0:19}" "$short_source"
  done < "$TMPDIR/components.tsv" | sort -t$'\t' -k1,1

  # Summary
  fail_count=$(grep -l $'\ttrue\t' "$TMPDIR"/result_* 2>/dev/null | wc -l | tr -d ' ')
  ok_count=$(grep -l $'\tfalse\t' "$TMPDIR"/result_* 2>/dev/null | wc -l | tr -d ' ')
  na_count=$(grep -l $'\tnull' "$TMPDIR"/result_* 2>/dev/null | wc -l | tr -d ' ')
  echo ""
  echo "Summary: ${TOTAL} components, ${fail_count} FAILED, ${ok_count} OK, ${na_count} N/A"

  if [[ "$fail_count" -gt 0 ]]; then
    exit 1
  fi
else
  # JSON output — build the full structure
  # First, create a merged TSV: component\tapp\tsource\tbranch\tbuild_failed\tlast_build
  while IFS=$'\t' read -r comp_name app source branch; do
    if [[ -f "$TMPDIR/result_${comp_name}" ]]; then
      IFS=$'\t' read -r _ build_failed last_build plr_name < "$TMPDIR/result_${comp_name}"
    else
      build_failed="null"
      last_build=""
      plr_name=""
    fi

    if [[ "$FAILED_ONLY" == "true" && "$build_failed" != "true" ]]; then
      continue
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$comp_name" "$app" "$source" "$branch" "$build_failed" "$last_build" "$plr_name"
  done < "$TMPDIR/components.tsv" > "$TMPDIR/merged.tsv"

  # Use jq to build the final JSON
  jq -Rsn '
    [inputs | split("\n") | .[] | select(length > 0) | split("\t") |
      {
        name: .[0],
        app: .[1],
        source: .[2],
        branch: .[3],
        build_failed: (.[4] | if . == "true" then true elif . == "false" then false else null end),
        last_build: .[5],
        pipelinerun: .[6]
      }
    ] | group_by(.app) | map({
      name: .[0].app,
      components: [.[] | {
        name: .name,
        build_failed: .build_failed,
        source: .source,
        branch: .branch,
        last_build: .last_build,
        pipelinerun: .pipelinerun
      }]
    }) | {applications: .}
  ' < "$TMPDIR/merged.tsv"
fi
