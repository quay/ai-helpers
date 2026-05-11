#!/bin/bash
# resolve-github-user.sh -- Resolve an Ambient userId to a GitHub username
# via the explicit mapping in .claude/user-map.yaml.
#
# Usage:  bash .claude/scripts/resolve-github-user.sh <userId>
# Output: matched GitHub username (stdout), or nothing if no mapping found.

set -euo pipefail

USER_ID="${1:-}"
if [ -z "$USER_ID" ]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
MAP_FILE="${SCRIPT_DIR}/../user-map.yaml"

if [ ! -f "$MAP_FILE" ]; then
  exit 0
fi

if ! command -v python3 &>/dev/null; then
  exit 0
fi
if ! python3 -c 'import yaml' 2>/dev/null; then
  exit 0
fi

python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    m = yaml.safe_load(f) or {}
uid = sys.argv[2]
entry = m.get(uid) or m.get(uid.lower())
if isinstance(entry, dict):
    v = entry.get('github', '')
elif isinstance(entry, str):
    v = entry
else:
    v = ''
if v:
    print(v, end='')
" "$MAP_FILE" "$USER_ID"
