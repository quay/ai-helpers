#!/usr/bin/env bash
# discover-components.sh -- Query Konflux Components CRD and cache the mapping.
#
# Usage: bash scripts/discover-components.sh
#
# Queries all Component resources in the namespace and builds a JSON map:
#   component-name → { repo, branch, application }
#
# Output cached to .claude/triage-state/component-map.json

set -euo pipefail

: "${KONFLUX_NAMESPACE:=quay-eng-tenant}"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STATE_DIR="${REPO_ROOT}/.claude/triage-state"
OUTPUT="${STATE_DIR}/component-map.json"

mkdir -p "$STATE_DIR"

COMPONENTS=$(kubectl get components -n "$KONFLUX_NAMESPACE" -o json 2>/dev/null) || {
  echo "[discover-components] WARNING: Cannot query Components CRD — using empty map"
  echo '[]' > "$OUTPUT"
  exit 0
}

echo "$COMPONENTS" | jq '[.items[] | {
  name: .metadata.name,
  application: (.metadata.labels["appstudio.openshift.io/application"] // "unknown"),
  repo: (.spec.source.git.url // "unknown"),
  branch: (.spec.source.git.revision // "main"),
  context: (.spec.source.git.context // ".")
}]' > "$OUTPUT"

COUNT=$(jq 'length' "$OUTPUT")
echo "[discover-components] Discovered ${COUNT} components, cached to ${OUTPUT}"

if [ "$COUNT" -gt 0 ]; then
  jq -r '.[] | "  - \(.name) → \(.repo) (\(.branch))"' "$OUTPUT"
fi
