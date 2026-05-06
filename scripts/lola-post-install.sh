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

# When --module-content is used, LOLA_MODULE_PATH points to the repo root
# but scripts live under the content subdirectory. Resolve via source.yml.
_source_yml="${mod}/.lola/source.yml"
if [ -f "$_source_yml" ]; then
  _content_dir=$(grep '^content_dirname:' "$_source_yml" | awk '{print $2}' || true)
  [ -n "$_content_dir" ] && [ -d "${mod}/${_content_dir}" ] && mod="${mod}/${_content_dir}"
fi

copy_dir() {
  local src="$mod/$1" dst="$proj/.claude/$1" glob="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dst"
  for f in "$src"/$glob; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    [ "$name" = "lola-post-install.sh" ] && continue
    [ "$name" = "session-setup.sh" ] && continue
    cp "$f" "$dst/$name"
    if [ "$1" = "scripts" ]; then chmod +x "$dst/$name"; fi
  done
}

copy_dir scripts "*.sh"
copy_dir templates "*"
copy_dir commands "*.md"
