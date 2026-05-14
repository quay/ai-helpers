#!/usr/bin/env bash
# SessionStart hook: installs Claude Code plugins via Lola.
# Skipped automatically if no .lola-req exists in the workflow root.
#
# Must be committed as a plain copy in each workflow's .claude/scripts/
# directory — symlinks do not survive hydrate.sh's subpath extraction.
# CI validates workflow copies stay in sync with this canonical version.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
WORKFLOW_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"  # .claude/scripts → .claude → workflow root
CLAUDE_DIR="${WORKFLOW_ROOT}/.claude"

if [ ! -f "${WORKFLOW_ROOT}/.lola-req" ]; then
  exit 0
fi

echo "[session-setup] Running lola sync..."
uvx --python 3.13 --from lola-ai lola sync

if [ -z "$(ls -A "${CLAUDE_DIR}/skills" 2>/dev/null)" ]; then
  echo "ERROR: .claude/skills/ is empty after lola sync — check .lola-req" >&2
  exit 1
fi

for required in cluster-provision.sh remote-playwright.sh; do
  if [ ! -x "${CLAUDE_DIR}/scripts/${required}" ]; then
    echo "ERROR: missing required plugin script ${CLAUDE_DIR}/scripts/${required}" >&2
    exit 1
  fi
done

echo "[session-setup] Plugins installed: $(ls "${CLAUDE_DIR}/skills" | tr '\n' ' ')"
