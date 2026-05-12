#!/usr/bin/env bash
# extract-failure-context.sh -- Extract detailed failure context from a PipelineRun.
#
# Usage: bash scripts/extract-failure-context.sh <pipelinerun-name>
#
# Retrieves:
#   - PipelineRun conditions and status
#   - Child TaskRun statuses
#   - Logs from failed TaskRun pods (truncated to 200 lines)
#   - TaskRun results (e.g., EC test output)
#
# Falls back to KubeArchive when live cluster data has been garbage collected.
#
# Output: JSON object with full diagnostic context to stdout.

set -euo pipefail

: "${KONFLUX_NAMESPACE:=quay-eng-tenant}"

PR_NAME="${1:?Usage: extract-failure-context.sh <pipelinerun-name>}"

HAS_KA=false
if kubectl ka version &>/dev/null 2>&1; then
  HAS_KA=true
fi

# Try live cluster first, then KubeArchive
PR_JSON=$(kubectl get pipelinerun "$PR_NAME" -n "$KONFLUX_NAMESPACE" -o json 2>/dev/null || true)
if [ -z "$PR_JSON" ] || [ "$PR_JSON" = "" ]; then
  if [ "$HAS_KA" = true ]; then
    echo "INFO: PipelineRun not on live cluster, trying KubeArchive..." >&2
    PR_JSON=$(kubectl ka get pipelinerun "$PR_NAME" -n "$KONFLUX_NAMESPACE" -o json 2>/dev/null || true)
  fi
fi

if [ -z "$PR_JSON" ] || [ "$PR_JSON" = "" ]; then
  echo '{"error": "PipelineRun not found on live cluster or KubeArchive", "pipelinerun": "'"$PR_NAME"'"}' >&2
  exit 1
fi

# Get all child TaskRun names
TASKRUN_NAMES=$(echo "$PR_JSON" | jq -r '
  [.status.childReferences[]? | select(.kind == "TaskRun") | .name] | .[]
')

TASK_DETAILS="[]"
for TR_NAME in $TASKRUN_NAMES; do
  [ -z "$TR_NAME" ] && continue

  TR_JSON=$(kubectl get taskrun "$TR_NAME" -n "$KONFLUX_NAMESPACE" -o json 2>/dev/null || true)
  if [ -z "$TR_JSON" ] || [ "$TR_JSON" = "{}" ]; then
    if [ "$HAS_KA" = true ]; then
      TR_JSON=$(kubectl ka get taskrun "$TR_NAME" -n "$KONFLUX_NAMESPACE" -o json 2>/dev/null || echo '{}')
    else
      TR_JSON='{}'
    fi
  fi

  IS_FAILED=$(echo "$TR_JSON" | jq -r '
    (.status.conditions[]? | select(.type == "Succeeded") | .status) // "Unknown"
  ' 2>/dev/null)

  TR_STATUS=$(echo "$TR_JSON" | jq '{
    name: .metadata.name,
    task: (.metadata.labels["tekton.dev/pipelineTask"] // .spec.taskRef.name // "unknown"),
    succeeded: ((.status.conditions[]? | select(.type == "Succeeded") | .status) // "Unknown"),
    reason: ((.status.conditions[]? | select(.type == "Succeeded") | .reason) // "Unknown"),
    message: ((.status.conditions[]? | select(.type == "Succeeded") | .message) // ""),
    results: [.status.results[]? | {name: .name, value: .value}]
  }' 2>/dev/null || echo '{}')

  LOGS=""
  if [ "$IS_FAILED" = "False" ]; then
    POD_NAME=$(echo "$TR_JSON" | jq -r '.status.podName // empty' 2>/dev/null)
    if [ -n "$POD_NAME" ]; then
      LOGS=$(kubectl logs "$POD_NAME" --all-containers --tail=200 -n "$KONFLUX_NAMESPACE" 2>/dev/null || true)

      # Fallback to KubeArchive for GC'd pod logs
      if [ -z "$LOGS" ] && [ "$HAS_KA" = true ]; then
        STEPS=$(echo "$TR_JSON" | jq -r '[.status.steps[]? | .name] | .[]' 2>/dev/null)
        KA_LOGS=""
        for STEP in $STEPS; do
          [ -z "$STEP" ] && continue
          STEP_LOG=$(kubectl ka logs "$POD_NAME" -c "$STEP" -n "$KONFLUX_NAMESPACE" 2>/dev/null || true)
          if [ -n "$STEP_LOG" ]; then
            KA_LOGS="${KA_LOGS}--- step: ${STEP} ---\n${STEP_LOG}\n"
          fi
        done
        if [ -n "$KA_LOGS" ]; then
          LOGS=$(echo -e "$KA_LOGS" | tail -200)
        fi
      fi

      if [ -z "$LOGS" ]; then
        LOGS="(logs unavailable — pod may have been garbage collected from both live cluster and KubeArchive)"
      fi
    fi
  fi

  TASK_ENTRY=$(echo "$TR_STATUS" | jq --arg logs "$LOGS" '. + {logs: $logs}')
  TASK_DETAILS=$(jq --argjson entry "$TASK_ENTRY" '. + [$entry]' <<< "$TASK_DETAILS")
done

echo "$PR_JSON" | jq --argjson tasks "$TASK_DETAILS" '{
  pipelinerun: .metadata.name,
  component: .metadata.labels["appstudio.openshift.io/component"],
  application: .metadata.labels["appstudio.openshift.io/application"],
  scenario: .metadata.labels["test.appstudio.openshift.io/scenario"],
  created: .metadata.creationTimestamp,
  completed: .status.completionTime,
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
  conditions: [.status.conditions[]? | {type, status, reason, message}],
  tasks: $tasks
}'
