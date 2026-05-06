#!/usr/bin/env bash
set -euo pipefail

mod="${LOLA_MODULE_PATH:?}"
proj="${LOLA_PROJECT_PATH:?}"

# Deploy scripts
if [ -d "$mod/scripts" ]; then
  mkdir -p "$proj/.claude/scripts"
  for f in "$mod"/scripts/*.sh; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    [ "$name" = "lola-post-install.sh" ] && continue
    cp "$f" "$proj/.claude/scripts/$name"
    chmod +x "$proj/.claude/scripts/$name"
  done
fi

# Deploy commands
if [ -d "$mod/commands" ]; then
  mkdir -p "$proj/.claude/commands"
  for f in "$mod"/commands/*.md; do
    [ -f "$f" ] || continue
    cp "$f" "$proj/.claude/commands/$(basename "$f")"
  done
fi
