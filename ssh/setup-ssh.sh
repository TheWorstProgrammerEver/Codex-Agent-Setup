#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: ./ssh/setup-ssh.sh [options]

Options:
  --agent-name NAME             Set hostname and SSH user defaults to NAME.
  --hostname NAME               Set the host name used for NAME.local.
  --user USER                   Local SSH login user to allow.
  --home PATH                   Home directory for the SSH login user.
  --authorized-key KEY          Public SSH key line to append to authorized_keys.
  --authorized-key-file PATH    File containing public SSH key lines.
  --authorized-key-stdin        Read public SSH key lines from stdin.
  --enable-password-auth        Keep SSH password auth enabled for first access.
  --disable-password-auth       Disable SSH password auth after key login is ready.
  --enable-passwordless-sudo    Install a NOPASSWD sudoers drop-in for the SSH user.
  --skip-package-install        Do not install openssh-server, tmux, or avahi-daemon.
  --yes                         Do not ask for confirmation.
  --dry-run                     Print planned actions without changing the host.
  -h, --help                    Show this help.
EOF
}

truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

valid_hostname() {
  [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
}

agent_name="${AGENT_NAME:-}"
hostname_value="${AGENT_HOSTNAME:-$agent_name}"
ssh_user="${AGENT_USER:-${AGENT_SSH_USER:-$agent_name}}"
home_value="${AGENT_HOME:-}"
authorized_key="${WORKSTATION_PUBLIC_KEY:-}"
authorized_key_file="${WORKSTATION_PUBLIC_KEY_FILE:-}"
authorized_key_stdin=0
password_auth_mode="${SSH_PASSWORD_AUTH_MODE:-}"
enable_passwordless_sudo="${ENABLE_PASSWORDLESS_SUDO:-0}"
skip_package_install="${SKIP_SSH_PACKAGE_INSTALL:-0}"
yes="${YES:-0}"
dry_run="${DRY_RUN:-0}"

if truthy "${DISABLE_PASSWORD_AUTH:-0}"; then
  password_auth_mode="disable"
elif truthy "${ENABLE_PASSWORD_AUTH:-0}"; then
  password_auth_mode="enable"
fi

while (($#)); do
  case "$1" in
    --agent-name)
      agent_name="${2:?missing name after --agent-name}"
      hostname_value="$agent_name"
      ssh_user="$agent_name"
      shift 2
      ;;
    --hostname)
      hostname_value="${2:?missing name after --hostname}"
      shift 2
      ;;
    --user)
      ssh_user="${2:?missing user after --user}"
      shift 2
      ;;
    --home)
      home_value="${2:?missing path after --home}"
      shift 2
      ;;
    --authorized-key|--ssh-public-key)
      authorized_key="${2:?missing key after $1}"
      shift 2
      ;;
    --authorized-key-file|--ssh-public-key-file)
      authorized_key_file="${2:?missing path after $1}"
      shift 2
      ;;
    --authorized-key-stdin)
      authorized_key_stdin=1
      shift
      ;;
    --enable-password-auth)
      password_auth_mode="enable"
      shift
      ;;
    --disable-password-auth)
      password_auth_mode="disable"
      shift
      ;;
    --enable-passwordless-sudo)
      enable_passwordless_sudo=1
      shift
      ;;
    --skip-package-install)
      skip_package_install=1
      shift
      ;;
    --yes)
      yes=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$ssh_user" ]]; then
  ssh_user="$(id -un)"
fi

if ! id "$ssh_user" >/dev/null 2>&1; then
  printf 'SSH user does not exist locally: %s\n' "$ssh_user" >&2
  exit 2
fi

if [[ -n "$hostname_value" ]] && ! valid_hostname "$hostname_value"; then
  printf 'Invalid hostname for mDNS target: %s\n' "$hostname_value" >&2
  exit 2
fi

if [[ "$password_auth_mode" != "" && "$password_auth_mode" != "enable" && "$password_auth_mode" != "disable" ]]; then
  printf 'SSH_PASSWORD_AUTH_MODE must be enable, disable, or empty; got %s\n' "$password_auth_mode" >&2
  exit 2
fi

if ! truthy "$skip_package_install"; then
  if command -v apt-get >/dev/null 2>&1; then
    if truthy "$dry_run"; then
      printf 'DRY would run sudo apt-get update\n'
      printf 'DRY would install packages: openssh-server tmux avahi-daemon\n'
    else
      export DEBIAN_FRONTEND=noninteractive
      sudo apt-get update
      sudo apt-get install -y openssh-server tmux avahi-daemon
    fi
  else
    printf 'apt-get not found; install openssh-server, tmux, and mDNS support manually if missing.\n' >&2
  fi
fi

if [[ -n "$hostname_value" ]]; then
  current_hostname="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
  if [[ "$current_hostname" != "$hostname_value" ]]; then
    if truthy "$dry_run"; then
      printf 'DRY would set hostname to %s\n' "$hostname_value"
    elif command -v hostnamectl >/dev/null 2>&1; then
      sudo hostnamectl set-hostname "$hostname_value"
    else
      sudo hostname "$hostname_value"
    fi
  fi
fi

if command -v systemctl >/dev/null 2>&1; then
  if truthy "$dry_run"; then
    printf 'DRY would enable and start ssh or sshd\n'
    printf 'DRY would enable and start avahi-daemon\n'
  else
    sudo systemctl enable --now ssh >/dev/null 2>&1 || sudo systemctl enable --now sshd >/dev/null 2>&1 || true
    sudo systemctl enable --now avahi-daemon >/dev/null 2>&1 || true
  fi
fi

python_args=(--user "$ssh_user")

if [[ -n "$home_value" ]]; then
  python_args+=(--home "$home_value")
fi

if [[ -n "$authorized_key_file" ]]; then
  python_args+=(--authorized-key-file "$authorized_key_file")
fi

if [[ -n "$authorized_key" ]]; then
  python_args+=(--authorized-key "$authorized_key")
fi

if truthy "$authorized_key_stdin"; then
  python_args+=(--authorized-key-stdin)
fi

case "$password_auth_mode" in
  enable) python_args+=(--enable-password-auth) ;;
  disable) python_args+=(--disable-password-auth) ;;
esac

if truthy "$enable_passwordless_sudo"; then
  python_args+=(--enable-passwordless-sudo)
fi

if truthy "$yes"; then
  python_args+=(--yes)
fi

if truthy "$dry_run"; then
  python_args+=(--dry-run)
fi

if [[ -n "$hostname_value" ]]; then
  printf 'Expected SSH target: %s@%s.local\n' "$ssh_user" "$hostname_value"
else
  host_now="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf unknown)"
  printf 'Expected SSH target: %s@%s.local\n' "$ssh_user" "$host_now"
fi

exec python3 "$script_dir/bootstrap_ssh.py" "${python_args[@]}"
