#!/usr/bin/env bash
# SessionStart hook: installs Claude Code plugins via Lola.
#
# Parses .lola-req entries with pip-style URL fragments (#subdirectory=path)
# and registers/installs each plugin individually. Uses lola mod add +
# lola install rather than lola sync because lola sync derives module names
# from the URL, causing collisions when multiple subdirectories come from
# the same repository (tracked upstream).
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
  # Skip full-line comments and blank lines
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  line="$(echo "$line" | xargs)"
  [ -z "$line" ] && continue

  # Parse pip-style URL fragment (#subdirectory=path)
  url="$line"
  subdir=""
  if [[ "$line" == *"#"* ]]; then
    url="${line%%#*}"
    fragment="${line#*#}"
    if [[ "$fragment" == *"subdirectory="* ]]; then
      subdir="${fragment#*subdirectory=}"
      subdir="${subdir%%&*}"
    fi
  fi

  # Derive module name from subdirectory basename or URL
  name="$(basename "${subdir:-$url}" | sed 's/\.git$//')"

  echo "[session-setup] Installing plugin: ${name}"
  if [ -n "$subdir" ]; then
    $LOLA mod add "$url" --module-content="$subdir" --name "$name" 2>&1 | tail -1
  else
    $LOLA mod add "$url" --name "$name" 2>&1 | tail -1
  fi
  $LOLA install "$name" -a claude-code -s project --force "$REPO_ROOT" 2>&1
done < "$LOLA_REQ"

if [ -z "$(ls -A "${CLAUDE_DIR}/scripts" 2>/dev/null)" ]; then
  echo "ERROR: .claude/scripts/ is empty after plugin install — check .lola-req"
  exit 1
fi

echo "[session-setup] Scripts installed: $(ls "${CLAUDE_DIR}/scripts" | tr '\n' ' ')"
