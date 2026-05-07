#!/usr/bin/env bash
# query-failed-pipelines.sh -- Query Konflux for failed PipelineRuns.
#
# Usage:
#   bash scripts/query-failed-pipelines.sh builds    # Failed push builds
#   bash scripts/query-failed-pipelines.sh ec-tests  # Failed EC/integration tests
#   bash scripts/query-failed-pipelines.sh all       # Both
#
# Environment:
#   KONFLUX_NAMESPACE       — Kubernetes namespace (default: quay-eng-tenant)
#   FAILURE_LOOKBACK_HOURS  — How far back to look (default: 24)
#
# Data sources: Queries both the live cluster and KubeArchive (if available)
# to catch PipelineRuns that have been garbage collected.
#
# Output: JSON array of failure records to stdout.
# Kubeconfig: Expects ~/.kube/config to be set up by session-setup.sh.

set -euo pipefail

: "${KONFLUX_NAMESPACE:=quay-eng-tenant}"
: "${FAILURE_LOOKBACK_HOURS:=24}"

QUERY_TYPE="${1:?Usage: query-failed-pipelines.sh <builds|ec-tests|all>}"

# Calculate cutoff timestamp (GNU date)
CUTOFF=$(date -u -d "${FAILURE_LOOKBACK_HOURS} hours ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
         date -u -v-${FAILURE_LOOKBACK_HOURS}H +%Y-%m-%dT%H:%M:%SZ)

HAS_KA=false
if kubectl ka version &>/dev/null 2>&1; then
  HAS_KA=true
fi

# kubectl wrapper: log warning and retry once on failure
kubectl_get_pipelineruns() {
  local labels="$1"
  local raw

  raw=$(kubectl get pipelineruns -l "$labels" -o json -n "$KONFLUX_NAMESPACE" 2>&1) && {
    echo "$raw"
    return 0
  }

  echo "WARNING: kubectl get pipelineruns failed (labels: ${labels}), retrying..." >&2
  sleep 5
  raw=$(kubectl get pipelineruns -l "$labels" -o json -n "$KONFLUX_NAMESPACE" 2>&1) && {
    echo "$raw"
    return 0
  }

  echo "WARNING: kubectl get pipelineruns failed after retry (labels: ${labels}), skipping." >&2
  echo '{"items":[]}'
}

# KubeArchive wrapper: query archived PipelineRuns
ka_get_pipelineruns() {
  local labels="$1"
  if [ "$HAS_KA" = true ]; then
    kubectl ka get pipelineruns -l "$labels" -o json -n "$KONFLUX_NAMESPACE" 2>/dev/null || echo '{"items":[]}'
  else
    echo '{"items":[]}'
  fi
}

# Merge live + archived results, deduplicating by PipelineRun name (live takes precedence)
merge_results() {
  local live="$1"
  local archived="$2"
  jq -s '
    (.[0] // []) as $live |
    (.[1] // []) as $archived |
    ($live | map({key: .name, value: .}) | from_entries) as $live_map |
    ($archived | [.[] | select(.name as $n | $live_map[$n] == null)]) as $new_from_archive |
    ($live + $new_from_archive) | sort_by(.created) | reverse
  ' <(echo "$live") <(echo "$archived")
}

JQ_FILTER_BUILDS='
  [.items[] |
    select(.metadata.creationTimestamp > $cutoff) |
    select(.status.conditions[]? | .type == "Succeeded" and .status == "False") |
    {
      name: .metadata.name,
      failure_type: "build",
      component: .metadata.labels["appstudio.openshift.io/component"],
      application: .metadata.labels["appstudio.openshift.io/application"],
      created: .metadata.creationTimestamp,
      commit_sha: (
        .metadata.annotations["build.appstudio.openshift.io/commit-sha"] //
        .metadata.labels["pipelinesascode.tekton.dev/sha"] //
        "unknown"
      ),
      branch: (
        .metadata.annotations["build.appstudio.openshift.io/target-branch"] //
        .metadata.labels["pipelinesascode.tekton.dev/branch"] //
        "unknown"
      ),
      repo_url: (
        .metadata.annotations["build.appstudio.openshift.io/repo"] //
        .metadata.labels["pipelinesascode.tekton.dev/url-repository"] //
        "unknown"
      ),
      reason: (first(.status.conditions[] | select(.type == "Succeeded")) | .reason),
      message: (first(.status.conditions[] | select(.type == "Succeeded")) | .message),
      child_references: [.status.childReferences[]? | {name: .name, kind: .kind}]
    }
  ] | sort_by(.created) | reverse'

JQ_FILTER_EC='
  [.items[] |
    select(.metadata.creationTimestamp > $cutoff) |
    select(.status.conditions[]? | .type == "Succeeded" and .status == "False") |
    {
      name: .metadata.name,
      failure_type: "ec_test",
      component: .metadata.labels["appstudio.openshift.io/component"],
      application: .metadata.labels["appstudio.openshift.io/application"],
      scenario: .metadata.labels["test.appstudio.openshift.io/scenario"],
      created: .metadata.creationTimestamp,
      commit_sha: (
        .metadata.labels["pipelinesascode.tekton.dev/sha"] //
        "unknown"
      ),
      branch: (
        .metadata.labels["pipelinesascode.tekton.dev/branch"] //
        "unknown"
      ),
      repo_url: (
        .metadata.labels["pipelinesascode.tekton.dev/url-repository"] //
        "unknown"
      ),
      reason: (first(.status.conditions[] | select(.type == "Succeeded")) | .reason),
      message: (first(.status.conditions[] | select(.type == "Succeeded")) | .message),
      child_references: [.status.childReferences[]? | {name: .name, kind: .kind}]
    }
  ] | sort_by(.created) | reverse'

query_failed_builds() {
  local labels="pipelines.appstudio.openshift.io/type=build,pipelinesascode.tekton.dev/event-type=push"
  local live archived
  live=$(kubectl_get_pipelineruns "$labels" | jq --arg cutoff "$CUTOFF" "$JQ_FILTER_BUILDS")
  archived=$(ka_get_pipelineruns "$labels" | jq --arg cutoff "$CUTOFF" "$JQ_FILTER_BUILDS")
  merge_results "$live" "$archived"
}

query_failed_ec_tests() {
  local labels="test.appstudio.openshift.io/scenario"
  local live archived
  live=$(kubectl_get_pipelineruns "$labels" | jq --arg cutoff "$CUTOFF" "$JQ_FILTER_EC")
  archived=$(ka_get_pipelineruns "$labels" | jq --arg cutoff "$CUTOFF" "$JQ_FILTER_EC")
  merge_results "$live" "$archived"
}

case "$QUERY_TYPE" in
  builds)   query_failed_builds ;;
  ec-tests) query_failed_ec_tests ;;
  all)
    BUILDS=$(query_failed_builds)
    EC_TESTS=$(query_failed_ec_tests)
    jq -s '.[0] + .[1] | sort_by(.created) | reverse' \
      <(echo "$BUILDS") <(echo "$EC_TESTS")
    ;;
  *) echo "Unknown query type: $QUERY_TYPE" >&2; exit 1 ;;
esac
