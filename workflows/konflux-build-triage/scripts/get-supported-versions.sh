#!/usr/bin/env bash
# get-supported-versions.sh — Query Red Hat product lifecycle API for Quay version status
#
# By default, returns currently supported Red Hat Quay minor versions
# (versions NOT marked "End of life"). Use --eol to return EOL versions
# instead (useful for building exclusion filters).
#
# Output: one version per line (e.g. "3.17"), or JSON with --json flag.
# Source: https://access.redhat.com/support/policy/updates/rhquay

set -euo pipefail

JSON_OUTPUT=false
EOL_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUTPUT=true; shift ;;
    --eol) EOL_MODE=true; shift ;;
    -h|--help)
      echo "Usage: get-supported-versions.sh [--eol] [--json]"
      echo "  --eol    Return end-of-life versions instead of supported ones"
      echo "  --json   Output as JSON array instead of one version per line"
      echo ""
      echo "Queries the Red Hat product lifecycle API and returns Quay versions."
      echo "Default: versions NOT end-of-life (Full Support, Maintenance, Extended Support)."
      echo "With --eol: versions that ARE end-of-life."
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

for cmd in curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is required but not found" >&2
    exit 1
  fi
done

API_URL="https://access.redhat.com/product-life-cycles/api/v1/products?name=Red+Hat+Quay"

RESPONSE=$(curl -s -f "$API_URL" 2>/dev/null) || {
  echo "Error: Failed to query Red Hat product lifecycle API" >&2
  exit 1
}

if [[ "$EOL_MODE" == "true" ]]; then
  TYPE_FILTER='select(.type == "End of life")'
else
  TYPE_FILTER='select(.type != "End of life")'
fi

VERSIONS=$(echo "$RESPONSE" | jq -r "
  .data[0].versions[]
  | ${TYPE_FILTER}
  | .name
" | sort -t. -k1,1n -k2,2n)

if [[ -z "$VERSIONS" ]]; then
  if [[ "$EOL_MODE" == "true" ]]; then
    echo "No end-of-life versions found" >&2
  else
    echo "Error: No supported versions found" >&2
    exit 1
  fi
fi

if [[ "$JSON_OUTPUT" == "true" ]]; then
  echo "$VERSIONS" | jq -Rn '[inputs | select(length > 0)]'
else
  echo "$VERSIONS"
fi
