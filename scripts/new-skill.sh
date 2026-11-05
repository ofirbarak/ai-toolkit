#!/usr/bin/env bash
# Scaffold a new skill from templates/skill.
# Usage: scripts/new-skill.sh <skill-name> [plugin]   (plugin defaults to "core")
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
name="${1:-}"
plugin="${2:-core}"

if [[ -z "$name" ]]; then
  echo "usage: $0 <skill-name> [plugin]" >&2
  exit 1
fi
if [[ ! "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || (( ${#name} > 64 )); then
  echo "error: skill name must be lowercase letters/digits/hyphens, ≤ 64 chars" >&2
  exit 1
fi

plugin_dir="$root/plugins/$plugin"
if [[ ! -d "$plugin_dir" ]]; then
  echo "error: plugin '$plugin' not found at $plugin_dir" >&2
  exit 1
fi

dest="$plugin_dir/skills/$name"
if [[ -e "$dest" ]]; then
  echo "error: $dest already exists" >&2
  exit 1
fi

# "my-cool-skill" -> "My cool skill"
title="$(echo "${name//-/ }" | awk '{ $1 = toupper(substr($1,1,1)) substr($1,2); print }')"

mkdir -p "$dest"
sed -e "s/__SKILL_NAME__/$name/g" -e "s/__SKILL_TITLE__/$title/g" \
  "$root/templates/skill/SKILL.md" > "$dest/SKILL.md"

echo "created ${dest#"$root"/}/SKILL.md"
echo "next: fill in the TODOs, then run scripts/validate.sh"
