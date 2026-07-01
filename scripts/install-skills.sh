#!/usr/bin/env bash
set -euo pipefail

repo_url="${SKILLS_REPO_URL:-https://github.com/TheWorstProgrammerEver/codex-skills.git}"
repo_ref="${SKILLS_REF:-}"
skills_dir="${AGENT_BOOTSTRAP_SKILLS_DIR:-$HOME/agent-bootstrap-skills}"
target="${SKILLS_INSTALL_TARGET:-$HOME/.codex/skills}"
skills=(
  agent-bootstrap-yolo-permissions
  manage-durable-notes
)

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  printf 'DRY would clone or update %s at %s\n' "$repo_url" "$skills_dir"
  if [[ -n "$repo_ref" ]]; then
    printf 'DRY would check out skills ref: %s\n' "$repo_ref"
  fi
  printf 'DRY would install skills to %s: %s\n' "$target" "${skills[*]}"
  exit 0
fi

if [[ -d "$skills_dir/.git" ]]; then
  git -C "$skills_dir" fetch --prune origin
elif [[ -e "$skills_dir" ]]; then
  printf 'Refusing to replace existing non-git path: %s\n' "$skills_dir" >&2
  exit 1
else
  git clone "$repo_url" "$skills_dir"
fi

if [[ -n "$repo_ref" ]]; then
  git -C "$skills_dir" checkout "$repo_ref"
else
  git -C "$skills_dir" checkout main
  git -C "$skills_dir" pull --ff-only origin main
fi

if [[ -f "$skills_dir/package.json" && -f "$skills_dir/scripts/install-skills.mjs" ]]; then
  npm --prefix "$skills_dir" run install:skills -- --target "$target" "${skills[@]}"
elif [[ -x "$skills_dir/install-skills.sh" ]]; then
  "$skills_dir/install-skills.sh" --target "$target" "${skills[@]}"
else
  printf 'No supported skill installer found in %s.\n' "$skills_dir" >&2
  exit 1
fi
