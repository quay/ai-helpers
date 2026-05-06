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

# Deploy templates
if [ -d "$mod/templates" ]; then
  mkdir -p "$proj/.claude/templates"
  for f in "$mod"/templates/*; do
    [ -f "$f" ] || continue
    cp "$f" "$proj/.claude/templates/$(basename "$f")"
  done
fi
