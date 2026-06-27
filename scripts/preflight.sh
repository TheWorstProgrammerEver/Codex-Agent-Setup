#!/usr/bin/env bash
set -euo pipefail

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

case "$(uname -s)" in
  Linux) ;;
  *)
    printf 'This setup script expects Linux; got %s.\n' "$(uname -s)" >&2
    exit 1
    ;;
esac

if [[ "$(id -u)" -eq 0 ]]; then
  printf 'Run this as the target login user, not root. The scripts use sudo where needed.\n' >&2
  exit 1
fi

need_command sudo
need_command bash
need_command uname
need_command id

if ! command -v apt-get >/dev/null 2>&1; then
  printf 'apt-get is required by this bootstrap path.\n' >&2
  exit 1
fi

if sudo -n true >/dev/null 2>&1; then
  printf 'sudo: noninteractive access available.\n'
else
  printf 'sudo: password may be requested for package and service setup.\n'
fi
