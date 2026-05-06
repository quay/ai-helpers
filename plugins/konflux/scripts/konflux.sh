#!/usr/bin/env bash
set -euo pipefail

# Interact with the Konflux build cluster.
#
# Usage: konflux.sh <command> [args...]
#
# Commands:
#   builds    [NAMESPACE] [COMPONENT]  — List recent PipelineRuns
#   status    <PIPELINERUN> [NAMESPACE] — Detailed PipelineRun status
#   logs      <PIPELINERUN> [NAMESPACE] — Logs from a PipelineRun's tasks
#   tasklog   <TASKRUN> [NAMESPACE]    — Logs from a specific TaskRun
#   components [NAMESPACE]             — List Components
#   apps      [NAMESPACE]              — List Applications
#   snapshots [NAMESPACE]              — List recent Snapshots
#
# Environment:
#   KONFLUX_KUBECONFIG — Path to decoded kubeconfig (default: /tmp/konflux-kubeconfig)

KUBECONFIG="${KONFLUX_KUBECONFIG:-/tmp/konflux-kubeconfig}"
DEFAULT_NS="${KONFLUX_DEFAULT_NS:-quay-eng-tenant}"
CMD="${1:-help}"
shift || true
OC_BIN=""

die() { echo "ERROR: $*" >&2; exit 1; }

check_prereqs() {
  [ -f "$KUBECONFIG" ] || die "Kubeconfig not found at ${KUBECONFIG}. Is KONFLUX_KUBECONFIG_DATA set?"
  if command -v oc >/dev/null 2>&1; then
    OC_BIN="$(command -v oc)"
  elif [ -x "${HOME}/.local/bin/oc" ]; then
    OC_BIN="${HOME}/.local/bin/oc"
  else
    die "'oc' not found on PATH or in ${HOME}/.local/bin."
  fi
}

oc_cmd() {
  "$OC_BIN" --kubeconfig="$KUBECONFIG" "$@"
}

cmd_builds() {
  local ns="${1:-$DEFAULT_NS}" component="${2:-}"
  check_prereqs
  echo "=== PipelineRuns in ${ns} ==="
  local selector=""
  if [ -n "$component" ]; then
    selector="-l appstudio.openshift.io/component=${component}"
  fi
  # shellcheck disable=SC2086
  oc_cmd get pipelineruns -n "$ns" $selector \
    --sort-by='.metadata.creationTimestamp' \
    -o custom-columns='\
NAME:.metadata.name,\
COMPONENT:.metadata.labels.appstudio\.openshift\.io/component,\
STATUS:.status.conditions[0].reason,\
STARTED:.metadata.creationTimestamp,\
DURATION:.status.completionTime' \
    | tail -20
}

cmd_status() {
  local pr="${1:-}" ns="${2:-$DEFAULT_NS}"
  [ -n "$pr" ] || die "Usage: konflux.sh status <PIPELINERUN> [NAMESPACE]"
  check_prereqs
  echo "=== PipelineRun: ${pr} ==="
  oc_cmd get pipelinerun "$pr" -n "$ns" \
    -o jsonpath='{.status.conditions[0].reason}{"\t"}{.status.conditions[0].message}{"\n"}'
  echo ""
  echo "--- TaskRuns ---"
  oc_cmd get taskruns -n "$ns" \
    -l tekton.dev/pipelineRun="$pr" \
    -o custom-columns='\
TASK:.metadata.labels.tekton\.dev/pipelineTask,\
STATUS:.status.conditions[0].reason,\
STARTED:.status.startTime,\
COMPLETED:.status.completionTime' \
    --sort-by='.status.startTime'
}

cmd_logs() {
  local pr="${1:-}" ns="${2:-$DEFAULT_NS}"
  [ -n "$pr" ] || die "Usage: konflux.sh logs <PIPELINERUN> [NAMESPACE]"
  check_prereqs

  local failed_trs
  failed_trs=$(oc_cmd get taskruns -n "$ns" \
    -l tekton.dev/pipelineRun="$pr" \
    -o jsonpath='{range .items[?(@.status.conditions[0].reason!="Succeeded")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

  if [ -n "$failed_trs" ]; then
    echo "=== Logs from failed/incomplete TaskRuns ==="
    while IFS= read -r tr; do
      [ -z "$tr" ] && continue
      echo "--- TaskRun: ${tr} ---"
      local pod
      pod=$(oc_cmd get taskrun "$tr" -n "$ns" -o jsonpath='{.status.podName}' 2>/dev/null || true)
      if [ -n "$pod" ]; then
        oc_cmd logs -n "$ns" "$pod" --all-containers=true --tail=100 2>/dev/null || echo "(no logs available)"
      else
        echo "(no pod found)"
      fi
      echo ""
    done <<< "$failed_trs"
  else
    echo "All TaskRuns succeeded. Showing last TaskRun logs:"
    local last_tr
    last_tr=$(oc_cmd get taskruns -n "$ns" \
      -l tekton.dev/pipelineRun="$pr" \
      --sort-by='.status.completionTime' \
      -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || true)
    if [ -n "$last_tr" ]; then
      local pod
      pod=$(oc_cmd get taskrun "$last_tr" -n "$ns" -o jsonpath='{.status.podName}' 2>/dev/null || true)
      if [ -n "$pod" ]; then
        oc_cmd logs -n "$ns" "$pod" --all-containers=true --tail=50 2>/dev/null || echo "(no logs available)"
      fi
    fi
  fi
}

cmd_tasklog() {
  local tr="${1:-}" ns="${2:-$DEFAULT_NS}"
  [ -n "$tr" ] || die "Usage: konflux.sh tasklog <TASKRUN> [NAMESPACE]"
  check_prereqs
  local pod
  pod=$(oc_cmd get taskrun "$tr" -n "$ns" -o jsonpath='{.status.podName}' 2>/dev/null || true)
  [ -n "$pod" ] || die "No pod found for TaskRun ${tr}"
  echo "=== Logs: TaskRun ${tr} (pod: ${pod}) ==="
  oc_cmd logs -n "$ns" "$pod" --all-containers=true 2>/dev/null
}

cmd_components() {
  local ns="${1:-$DEFAULT_NS}"
  check_prereqs
  echo "=== Components in ${ns} ==="
  oc_cmd get components -n "$ns" \
    -o custom-columns='\
NAME:.metadata.name,\
APPLICATION:.spec.application,\
GIT_REPO:.spec.source.git.url,\
REVISION:.spec.source.git.revision' \
}

cmd_apps() {
  local ns="${1:-$DEFAULT_NS}"
  check_prereqs
  echo "=== Applications in ${ns} ==="
  oc_cmd get applications -n "$ns" \
    -o custom-columns='NAME:.metadata.name,CREATED:.metadata.creationTimestamp'
}

cmd_snapshots() {
  local ns="${1:-$DEFAULT_NS}"
  check_prereqs
  echo "=== Recent Snapshots in ${ns} ==="
  oc_cmd get snapshots -n "$ns" \
    --sort-by='.metadata.creationTimestamp' \
    -o custom-columns='\
NAME:.metadata.name,\
APPLICATION:.spec.application,\
CREATED:.metadata.creationTimestamp' \
    | tail -15
}

cmd_help() {
  echo "Usage: konflux.sh <command> [args...]"
  echo ""
  echo "Commands:"
  echo "  builds    [NAMESPACE] [COMPONENT]   List recent PipelineRuns"
  echo "  status    <PIPELINERUN> [NAMESPACE]  Detailed PipelineRun status"
  echo "  logs      <PIPELINERUN> [NAMESPACE]  Logs from PipelineRun tasks"
  echo "  tasklog   <TASKRUN> [NAMESPACE]      Logs from a specific TaskRun"
  echo "  components [NAMESPACE]               List Components"
  echo "  apps      [NAMESPACE]                List Applications"
  echo "  snapshots [NAMESPACE]                List recent Snapshots"
  echo ""
  echo "Default namespace: ${DEFAULT_NS} (override with KONFLUX_DEFAULT_NS)"
  echo "Kubeconfig: ${KUBECONFIG}"
}

case "$CMD" in
  builds)     cmd_builds "$@" ;;
  status)     cmd_status "$@" ;;
  logs)       cmd_logs "$@" ;;
  tasklog)    cmd_tasklog "$@" ;;
  components) cmd_components "$@" ;;
  apps)       cmd_apps "$@" ;;
  snapshots)  cmd_snapshots "$@" ;;
  help|--help|-h) cmd_help ;;
  *) die "Unknown command: ${CMD}. Run 'konflux.sh help' for usage." ;;
esac
