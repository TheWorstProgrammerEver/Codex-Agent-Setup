#!/usr/bin/env bash
set -euo pipefail

packages=(
  git
  gh
  openssl
  python3
  sudo
  openssh-server
  tmux
  avahi-daemon
  bubblewrap
  curl
  ca-certificates
)

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  printf 'DRY would run sudo apt-get update\n'
  printf 'DRY would install packages: %s\n' "${packages[*]}"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y "${packages[@]}"

sudo systemctl enable --now ssh >/dev/null 2>&1 || sudo systemctl enable --now sshd >/dev/null 2>&1 || true
sudo systemctl enable --now avahi-daemon >/dev/null 2>&1 || true
