#!/usr/bin/env bash
set -euo pipefail

package="${CODEX_NPM_PACKAGE:-@openai/codex}"
force="${CODEX_INSTALL_FORCE:-0}"
npm_prefix="${CODEX_NPM_PREFIX:-$HOME/.local}"
npm_bin="$npm_prefix/bin"
install_update="${CODEX_INSTALL_UPDATE:-1}"
service_base_path="${CODEX_SERVICE_BASE_PATH:-/usr/local/bin:/usr/bin:/bin}"
profile_block_begin="# BEGIN CODEX NPM GLOBAL PATH"
profile_block_end="# END CODEX NPM GLOBAL PATH"

shell_path_for() {
  local path="$1"

  if [[ "$path" == "$HOME"/* ]]; then
    printf '$HOME/%s\n' "${path#"$HOME/"}"
  else
    printf '%s\n' "$path"
  fi
}

ensure_path_first() {
  local bin_dir="$1"

  case ":$PATH:" in
    :"$bin_dir":*) ;;
    *) export PATH="$bin_dir:$PATH" ;;
  esac
}

write_shell_path_block() {
  local target="$1"
  local shell_bin="$2"

  python3 - "$target" "$shell_bin" "$profile_block_begin" "$profile_block_end" <<'PY'
import sys
from pathlib import Path

target = Path(sys.argv[1])
shell_bin = sys.argv[2]
begin = sys.argv[3]
end = sys.argv[4]

block = f"""{begin}
codex_npm_bin=\"{shell_bin}\"
if [ -d \"$codex_npm_bin\" ]; then
  case \":$PATH:\" in
    :\"$codex_npm_bin\":*) ;;
    *) PATH=\"$codex_npm_bin:$PATH\" ;;
  esac
  export PATH
fi
unset codex_npm_bin
{end}
"""

text = target.read_text() if target.exists() else ""
if begin in text and end in text:
    before, rest = text.split(begin, 1)
    _, after = rest.split(end, 1)
    updated = before.rstrip() + "\n\n" + block.rstrip() + "\n" + after
else:
    updated = text.rstrip() + "\n\n" + block.rstrip() + "\n"

target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(updated)
PY
}

configure_npm_prefix() {
  local shell_bin

  mkdir -p "$npm_bin"
  npm config set prefix "$npm_prefix"

  shell_bin="$(shell_path_for "$npm_bin")"
  write_shell_path_block "$HOME/.profile" "$shell_bin"
  write_shell_path_block "$HOME/.bashrc" "$shell_bin"
  ensure_path_first "$npm_bin"
}

validate_codex_install() {
  local configured_prefix
  local resolved_codex
  local expected_codex="$npm_bin/codex"
  local service_path="$npm_bin:$service_base_path"

  configured_prefix="$(npm config get prefix)"
  if [[ "$configured_prefix" != "$npm_prefix" ]]; then
    printf 'npm prefix mismatch: expected %s, got %s\n' "$npm_prefix" "$configured_prefix" >&2
    exit 1
  fi

  if [[ ! -w "$configured_prefix" ]]; then
    printf 'npm prefix is not writable by %s: %s\n' "$(id -un)" "$configured_prefix" >&2
    exit 1
  fi

  resolved_codex="$(command -v codex || true)"
  if [[ "$resolved_codex" != "$expected_codex" ]]; then
    printf 'codex path mismatch: expected %s, got %s\n' "$expected_codex" "${resolved_codex:-not found}" >&2
    exit 1
  fi

  codex --version

  env -i HOME="$HOME" PATH="$service_path" bash -c '
set -euo pipefail
expected_codex="$1"
expected_prefix="$2"
actual_prefix="$(npm config get prefix)"
if [[ "$actual_prefix" != "$expected_prefix" ]]; then
  printf "service-like npm prefix mismatch: expected %s, got %s\n" "$expected_prefix" "$actual_prefix" >&2
  exit 1
fi
actual_codex="$(command -v codex || true)"
if [[ "$actual_codex" != "$expected_codex" ]]; then
  printf "service-like codex path mismatch: expected %s, got %s\n" "$expected_codex" "${actual_codex:-not found}" >&2
  exit 1
fi
codex --version
' bash "$expected_codex" "$npm_prefix"

  env -i HOME="$HOME" PATH="$service_base_path" CODEX_BIN="$expected_codex" bash -c '
set -euo pipefail
if [[ ! -x "$CODEX_BIN" ]]; then
  printf "CODEX_BIN is not executable: %s\n" "$CODEX_BIN" >&2
  exit 1
fi
"$CODEX_BIN" --version
'
}

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  printf 'DRY would configure npm global prefix: %s\n' "$npm_prefix"
  printf 'DRY would add %s ahead of root-owned global bins in %s and %s\n' "$npm_bin" "$HOME/.profile" "$HOME/.bashrc"
  printf 'DRY would install or update Codex package as %s: %s\n' "$(id -un)" "$package"
  printf 'DRY would validate: npm config get prefix, command -v codex, codex --version, and service-like PATH/CODEX_BIN execution\n'
  exit 0
fi

configure_npm_prefix

if [[ "$install_update" == "1" || "$force" == "1" || ! -x "$npm_bin/codex" ]]; then
  npm install -g "$package"
fi

validate_codex_install
