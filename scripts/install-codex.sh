#!/usr/bin/env bash
set -euo pipefail

package="${CODEX_NPM_PACKAGE:-@openai/codex}"
force="${CODEX_INSTALL_FORCE:-0}"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  printf 'DRY would install Codex package globally: %s\n' "$package"
  exit 0
fi

if command -v codex >/dev/null 2>&1 && [[ "$force" != "1" ]]; then
  codex --version
  exit 0
fi

sudo npm install -g "$package"
codex --version
