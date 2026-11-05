#!/usr/bin/env bash
# Link (or copy) every skill in plugins/*/skills/ into Claude Code and Codex skill folders.
#
# Usage:
#   scripts/install.sh                     symlink into ~/.claude/skills and ~/.agents/skills
#   scripts/install.sh --project DIR       symlink into DIR/.claude/skills and DIR/.agents/skills
#   scripts/install.sh --project DIR --copy   copy instead of symlink (to commit skills into DIR)
#   scripts/install.sh --only claude|codex    install for one tool only
#   scripts/install.sh --skill NAME           install one skill only (repeatable)
#   scripts/install.sh --uninstall [--project DIR]  remove links that point into this repo
#
# Codex reads ~/.agents/skills (user) and <repo>/.agents/skills (project).
# Claude Code reads ~/.claude/skills (user) and <repo>/.claude/skills (project).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
base="$HOME"
mode=link
only=""
uninstall=false
skills_filter=()

while (( $# )); do
  case "$1" in
    --project) base="$(cd "${2:?--project needs a directory}" && pwd)"; shift 2 ;;
    --copy) mode=copy; shift ;;
    --only) only="${2:?--only needs claude or codex}"; shift 2 ;;
    --skill) skills_filter+=("${2:?--skill needs a name}"); shift 2 ;;
    --uninstall) uninstall=true; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

targets=()
[[ "$only" != codex ]] && targets+=("$base/.claude/skills")
[[ "$only" != claude ]] && targets+=("$base/.agents/skills")

wanted() {
  (( ${#skills_filter[@]} == 0 )) && return 0
  local s; for s in "${skills_filter[@]}"; do [[ "$s" == "$1" ]] && return 0; done
  return 1
}

for target in "${targets[@]}"; do
  mkdir -p "$target"

  if $uninstall; then
    for entry in "$target"/*; do
      [[ -L "$entry" ]] || continue
      case "$(readlink "$entry")" in
        "$root"/*) rm "$entry"; echo "removed  $entry" ;;
      esac
    done
    continue
  fi

  for skill_dir in "$root"/plugins/*/skills/*/; do
    skill_dir="${skill_dir%/}"
    name="$(basename "$skill_dir")"
    wanted "$name" || continue
    dest="$target/$name"

    if [[ -e "$dest" || -L "$dest" ]]; then
      if [[ -L "$dest" && "$(readlink "$dest")" == "$root"/* ]]; then
        rm "$dest"                                   # our own old link: refresh it
      elif [[ "$mode" == copy && -f "$dest/.ai-toolkit" ]]; then
        rm -rf "$dest"                               # our own old copy: refresh it
      else
        echo "skip     $dest (exists and is not managed by ai-toolkit)" >&2
        continue
      fi
    fi

    if [[ "$mode" == copy ]]; then
      cp -R "$skill_dir" "$dest"
      echo "source: ai-toolkit/${skill_dir#"$root"/}" > "$dest/.ai-toolkit"
      echo "copied   $dest"
    else
      ln -s "$skill_dir" "$dest"
      echo "linked   $dest -> $skill_dir"
    fi
  done
done
