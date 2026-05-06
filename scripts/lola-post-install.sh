#!/usr/bin/env bash
set -euo pipefail

# Universal Lola post-install hook for ai-helpers plugins.
# Copies scripts, templates, and commands from the module into the
# consuming project's .claude/ directory where Claude Code expects them.
#
# Lola provides these env vars automatically:
#   LOLA_MODULE_PATH  — path to the installed module in .lola/modules/
#   LOLA_PROJECT_PATH — root of the consuming project

mod="${LOLA_MODULE_PATH:?}"
proj="${LOLA_PROJECT_PATH:?}"

copy_dir() {
  local src="$mod/$1" dst="$proj/.claude/$1" glob="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dst"
  for f in "$src"/$glob; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    [ "$name" = "lola-post-install.sh" ] && continue
    cp "$f" "$dst/$name"
    if [ "$1" = "scripts" ]; then chmod +x "$dst/$name"; fi
  done
}

copy_dir scripts "*.sh"
copy_dir templates "*"
copy_dir commands "*.md"
