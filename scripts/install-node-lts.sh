#!/usr/bin/env bash
set -euo pipefail

NODE_DIST_INDEX_URL="${NODE_DIST_INDEX_URL:-https://nodejs.org/dist/index.json}"
NODE_DIST_BASE_URL="${NODE_DIST_BASE_URL:-https://nodejs.org/dist}"
NODE_LTS_PREFIX="${NODE_LTS_PREFIX:-/opt/node-lts}"
NODE_LTS_LINE="${NODE_LTS_LINE:-}"
NODE_LTS_FORCE="${NODE_LTS_FORCE:-0}"

node_arch() {
  case "$(uname -m)" in
    aarch64|arm64) printf 'arm64\n' ;;
    x86_64|amd64) printf 'x64\n' ;;
    armv7l) printf 'armv7l\n' ;;
    *)
      printf 'Unsupported Node.js binary architecture: %s\n' "$(uname -m)" >&2
      return 1
      ;;
  esac
}

resolve_latest_lts() {
  python3 - "$NODE_DIST_INDEX_URL" "$NODE_LTS_LINE" <<'PY'
import json
import sys
import urllib.request

index_url = sys.argv[1]
wanted_line = sys.argv[2]

with urllib.request.urlopen(index_url, timeout=30) as response:
    releases = json.load(response)

for release in releases:
    lts = release.get("lts")
    version = release.get("version", "")
    if not lts or not version.startswith("v"):
        continue
    if wanted_line and version.split(".", 1)[0] != f"v{wanted_line}":
        continue
    print(version)
    break
else:
    line_message = f" for major line {wanted_line}" if wanted_line else ""
    raise SystemExit(f"No Node.js LTS release found{line_message} in {index_url}")
PY
}

install_symlink() {
  local target="$1"
  local link="$2"

  sudo ln -sfn "$target" "$link"
}

version="$(resolve_latest_lts)"
arch="$(node_arch)"
platform="linux-$arch"
tarball="node-$version-$platform.tar.xz"
version_dir="$NODE_LTS_PREFIX/versions/$version"
current_link="$NODE_LTS_PREFIX/current"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  printf 'DRY would install Node.js %s LTS for %s from %s\n' "$version" "$platform" "$NODE_DIST_INDEX_URL"
  printf 'DRY would manage prefix: %s\n' "$NODE_LTS_PREFIX"
  printf 'DRY would update symlinks: /usr/local/bin/{node,npm,npx,corepack}\n'
  exit 0
fi

if [[ -x "$version_dir/bin/node" && "$NODE_LTS_FORCE" != "1" ]]; then
  installed_version="$("$version_dir/bin/node" --version)"
  if [[ "$installed_version" == "$version" ]]; then
    printf 'Node.js %s LTS is already installed at %s\n' "$version" "$version_dir"
  else
    printf 'Existing Node.js install at %s reported %s, reinstalling %s\n' "$version_dir" "$installed_version" "$version"
    sudo rm -rf "$version_dir"
  fi
fi

if [[ ! -x "$version_dir/bin/node" ]]; then
  base_url="$NODE_DIST_BASE_URL/$version"
  curl --fail --location --show-error --output "$tmp_dir/$tarball" "$base_url/$tarball"
  curl --fail --location --show-error --output "$tmp_dir/SHASUMS256.txt" "$base_url/SHASUMS256.txt"

  (cd "$tmp_dir" && sha256sum --check --ignore-missing SHASUMS256.txt)

  sudo mkdir -p "$NODE_LTS_PREFIX/versions"
  sudo rm -rf "$version_dir"
  sudo tar -xJf "$tmp_dir/$tarball" -C "$NODE_LTS_PREFIX/versions"
  sudo mv "$NODE_LTS_PREFIX/versions/node-$version-$platform" "$version_dir"
fi

install_symlink "$version_dir" "$current_link"
install_symlink "$current_link/bin/node" /usr/local/bin/node
install_symlink "$current_link/bin/npm" /usr/local/bin/npm
install_symlink "$current_link/bin/npx" /usr/local/bin/npx
install_symlink "$current_link/bin/corepack" /usr/local/bin/corepack

node --version
npm --version
npx --version
