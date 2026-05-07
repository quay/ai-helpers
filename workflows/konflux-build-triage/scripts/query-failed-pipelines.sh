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
# Output: JSON array of failure records to stdout.

set -euo pipefail

: "${KONFLUX_NAMESPACE:=quay-eng-tenant}"
: "${FAILURE_LOOKBACK_HOURS:=24}"

QUERY_TYPE="${1:?Usage: query-failed-pipelines.sh <builds|ec-tests|all>}"

# Calculate cutoff timestamp (GNU date)
CUTOFF=$(date -u -d "${FAILURE_LOOKBACK_HOURS} hours ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
         date -u -v-${FAILURE_LOOKBACK_HOURS}H +%Y-%m-%dT%H:%M:%SZ)

query_failed_builds() {
  local raw
  raw=$(kubectl get pipelineruns \
    -l "pipelines.appstudio.openshift.io/type=build,pipelinesascode.tekton.dev/event-type=push" \
    -o json \
    -n "$KONFLUX_NAMESPACE" 2>/dev/null) || { echo "[]"; return; }

  echo "$raw" | jq --arg cutoff "$CUTOFF" '
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
        reason: (.status.conditions[] | select(.type == "Succeeded") | .reason),
        message: (.status.conditions[] | select(.type == "Succeeded") | .message),
        child_references: [.status.childReferences[]? | {name: .name, kind: .kind}]
      }
    ] | sort_by(.created) | reverse'
}

query_failed_ec_tests() {
  local raw
  raw=$(kubectl get pipelineruns \
    -l "test.appstudio.openshift.io/scenario" \
    -o json \
    -n "$KONFLUX_NAMESPACE" 2>/dev/null) || { echo "[]"; return; }

  echo "$raw" | jq --arg cutoff "$CUTOFF" '
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
        reason: (.status.conditions[] | select(.type == "Succeeded") | .reason),
        message: (.status.conditions[] | select(.type == "Succeeded") | .message),
        child_references: [.status.childReferences[]? | {name: .name, kind: .kind}]
      }
    ] | sort_by(.created) | reverse'
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
