#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

fake_bin="$tmp_dir/fake-bin"
home_dir="$tmp_dir/home"
mkdir -p "$fake_bin" "$home_dir"

cat >"$fake_bin/npm" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

config_file="$HOME/.npmrc"

get_prefix() {
  if [[ -f "$config_file" ]]; then
    sed -n 's/^prefix=//p' "$config_file" | tail -n 1
  fi
}

case "${1:-} ${2:-}" in
  "config set")
    if [[ "${3:-}" != "prefix" ]]; then
      printf 'unexpected npm config key: %s\n' "${3:-}" >&2
      exit 1
    fi
    mkdir -p "$(dirname -- "$config_file")"
    printf 'prefix=%s\n' "${4:?missing prefix}" >"$config_file"
    ;;
  "config get")
    if [[ "${3:-}" != "prefix" ]]; then
      printf 'unexpected npm config key: %s\n' "${3:-}" >&2
      exit 1
    fi
    get_prefix
    ;;
  "install -g")
    prefix="$(get_prefix)"
    if [[ -z "$prefix" ]]; then
      printf 'npm prefix was not configured before install\n' >&2
      exit 1
    fi
    mkdir -p "$prefix/bin"
    cat >"$prefix/bin/codex" <<'CODEX'
#!/usr/bin/env bash
set -euo pipefail
printf 'codex-cli-test 1.2.3\n'
CODEX
    chmod 0755 "$prefix/bin/codex"
    ;;
  *)
    printf 'unexpected npm command: %s\n' "$*" >&2
    exit 1
    ;;
esac
SH
chmod 0755 "$fake_bin/npm"

PATH="$fake_bin:/usr/bin:/bin" \
HOME="$home_dir" \
CODEX_NPM_PREFIX="$home_dir/.local" \
CODEX_SERVICE_BASE_PATH="$fake_bin:/usr/bin:/bin" \
"$repo_root/scripts/install-codex.sh"

if [[ "$(sed -n 's/^prefix=//p' "$home_dir/.npmrc")" != "$home_dir/.local" ]]; then
  printf 'expected npm prefix to be written to .npmrc\n' >&2
  exit 1
fi

for shell_file in "$home_dir/.profile" "$home_dir/.bashrc"; do
  if ! grep -Fq '# BEGIN CODEX NPM GLOBAL PATH' "$shell_file"; then
    printf 'expected Codex npm PATH block in %s\n' "$shell_file" >&2
    exit 1
  fi
done

resolved="$(
  PATH="/usr/local/bin:/usr/bin:/bin" HOME="$home_dir" bash -c '
set -euo pipefail
. "$HOME/.profile"
command -v codex
'
)"

if [[ "$resolved" != "$home_dir/.local/bin/codex" ]]; then
  printf 'expected shell startup to resolve user-scoped codex, got %s\n' "$resolved" >&2
  exit 1
fi

printf 'install-codex user npm prefix test passed\n'
