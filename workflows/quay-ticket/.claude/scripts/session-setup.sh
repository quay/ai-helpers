#!/usr/bin/env bash
# SessionStart hook: reads .lola-req and installs plugins via Lola.
#
# Parses .lola-req lines (URL + --module-content=<path>) and runs
# `lola mod add` + `lola install` for each entry. This is a shim for
# `lola sync` which does not yet parse --module-content from .lola-req.
#
# Must be committed directly in each workflow's .claude/scripts/
# directory — symlinks do not survive ACP's hydrate.sh subpath extraction.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CLAUDE_DIR="${REPO_ROOT}/.claude"
LOLA_REQ="${REPO_ROOT}/.lola-req"
LOLA="uvx --python 3.13 --from lola-ai lola"

if [ ! -f "$LOLA_REQ" ]; then
  echo "[session-setup] No .lola-req found, skipping"
  exit 0
fi

while IFS= read -r line || [ -n "$line" ]; do
  # Strip comments and whitespace
  line="${line%%#*}"
  line="$(echo "$line" | xargs)"
  [ -z "$line" ] && continue

  # Parse URL and --module-content flag
  url="${line%% --*}"
  content_dir=""
  if [[ "$line" == *"--module-content="* ]]; then
    content_dir="${line#*--module-content=}"
    content_dir="${content_dir%% *}"
  fi

  # Derive module name from content dir or URL
  name="$(basename "${content_dir:-$url}" | sed 's/\.git$//')"

  echo "[session-setup] Installing plugin: ${name}"
  if [ -n "$content_dir" ]; then
    $LOLA mod add "$url" --module-content="$content_dir" --name "$name" 2>&1 | tail -1
  else
    $LOLA mod add "$url" --name "$name" 2>&1 | tail -1
  fi
  $LOLA install "$name" -a claude-code --scope project --force "$REPO_ROOT" 2>&1
done < "$LOLA_REQ"

if [ -z "$(ls -A "${CLAUDE_DIR}/scripts" 2>/dev/null)" ]; then
  echo "ERROR: .claude/scripts/ is empty after plugin install — check .lola-req"
  exit 1
fi

echo "[session-setup] Scripts installed: $(ls "${CLAUDE_DIR}/scripts" | tr '\n' ' ')"
