#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: ./agent-setup.sh [options]

Options:
  --env PATH                    Source an environment file before running.
  --skills-repo-url URL         Skills repository to clone.
  --skills-ref REF              Optional branch, tag, or SHA for the skills repo.
  --agent-name NAME             Set host name and SSH user defaults to NAME.
  --hostname NAME               Set the host name before Codex bootstrap.
  --ssh-user USER               Local SSH login user to allow.
  --ssh-public-key KEY          Public SSH key line to install for workstation access.
  --ssh-public-key-file PATH    File containing public SSH key lines.
  --enable-passwordless-sudo    Enable passwordless sudo for a dedicated host.
  --disable-password-auth       Disable SSH password auth after key login is ready.
  --skip-codex-login            Do not run `codex login --device-auth`.
  --skip-codex-bootstrap        Do not configure Codex permissions and durable notes.
  --codex-workspace PATH        Workspace to mark trusted. Defaults to $HOME.
  --dry-run                     Print shell actions without changing the host.
  -h, --help                    Show this help.
EOF
}

default_env="$repo_root/agent.env"
agent_env="${AGENT_ENV:-}"
if [[ -z "$agent_env" && -f "$default_env" ]]; then
  agent_env="$default_env"
fi

if [[ -n "$agent_env" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$agent_env"
  set +a
fi

SKILLS_REPO_URL="${SKILLS_REPO_URL:-https://github.com/TheWorstProgrammerEver/codex-skills.git}"
SKILLS_REF="${SKILLS_REF:-}"
AGENT_NAME="${AGENT_NAME:-}"
AGENT_HOSTNAME="${AGENT_HOSTNAME:-$AGENT_NAME}"
AGENT_USER="${AGENT_USER:-${AGENT_SSH_USER:-$AGENT_NAME}}"
WORKSTATION_PUBLIC_KEY="${WORKSTATION_PUBLIC_KEY:-}"
WORKSTATION_PUBLIC_KEY_FILE="${WORKSTATION_PUBLIC_KEY_FILE:-}"
ENABLE_PASSWORDLESS_SUDO="${ENABLE_PASSWORDLESS_SUDO:-0}"
DISABLE_PASSWORD_AUTH="${DISABLE_PASSWORD_AUTH:-0}"
SKIP_CODEX_LOGIN="${SKIP_CODEX_LOGIN:-0}"
RUN_CODEX_BOOTSTRAP="${RUN_CODEX_BOOTSTRAP:-1}"
CODEX_WORKSPACE="${CODEX_WORKSPACE:-$HOME}"
DRY_RUN="${DRY_RUN:-0}"

while (($#)); do
  case "$1" in
    --env)
      agent_env="${2:?missing path after --env}"
      set -a
      # shellcheck disable=SC1090
      . "$agent_env"
      set +a
      shift 2
      ;;
    --skills-repo-url)
      SKILLS_REPO_URL="${2:?missing URL after --skills-repo-url}"
      shift 2
      ;;
    --skills-ref)
      SKILLS_REF="${2:?missing ref after --skills-ref}"
      shift 2
      ;;
    --agent-name)
      AGENT_NAME="${2:?missing name after --agent-name}"
      AGENT_HOSTNAME="$AGENT_NAME"
      AGENT_USER="$AGENT_NAME"
      shift 2
      ;;
    --hostname)
      AGENT_HOSTNAME="${2:?missing name after --hostname}"
      shift 2
      ;;
    --ssh-user)
      AGENT_USER="${2:?missing user after --ssh-user}"
      shift 2
      ;;
    --ssh-public-key)
      WORKSTATION_PUBLIC_KEY="${2:?missing key after --ssh-public-key}"
      shift 2
      ;;
    --ssh-public-key-file)
      WORKSTATION_PUBLIC_KEY_FILE="${2:?missing path after --ssh-public-key-file}"
      shift 2
      ;;
    --enable-passwordless-sudo)
      ENABLE_PASSWORDLESS_SUDO=1
      shift
      ;;
    --disable-password-auth)
      DISABLE_PASSWORD_AUTH=1
      shift
      ;;
    --skip-codex-login)
      SKIP_CODEX_LOGIN=1
      shift
      ;;
    --skip-codex-bootstrap)
      RUN_CODEX_BOOTSTRAP=0
      shift
      ;;
    --codex-workspace)
      CODEX_WORKSPACE="${2:?missing path after --codex-workspace}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
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

if [[ -z "$AGENT_HOSTNAME" && -n "$AGENT_NAME" ]]; then
  AGENT_HOSTNAME="$AGENT_NAME"
fi

if [[ -z "$AGENT_USER" && -n "${AGENT_SSH_USER:-}" ]]; then
  AGENT_USER="$AGENT_SSH_USER"
fi

if [[ -z "$AGENT_USER" && -n "$AGENT_NAME" ]]; then
  AGENT_USER="$AGENT_NAME"
fi

export SKILLS_REPO_URL
export SKILLS_REF
export DRY_RUN

"$repo_root/scripts/preflight.sh"

ssh_setup_args=(--yes --skip-package-install)

if [[ -n "$AGENT_HOSTNAME" ]]; then
  ssh_setup_args+=(--hostname "$AGENT_HOSTNAME")
fi

if [[ -n "$AGENT_USER" ]]; then
  ssh_setup_args+=(--user "$AGENT_USER")
fi

if [[ "$DISABLE_PASSWORD_AUTH" == "1" ]]; then
  ssh_setup_args+=(--disable-password-auth)
else
  ssh_setup_args+=(--enable-password-auth)
fi

if [[ -n "$WORKSTATION_PUBLIC_KEY_FILE" ]]; then
  ssh_setup_args+=(--authorized-key-file "$WORKSTATION_PUBLIC_KEY_FILE")
fi

if [[ -n "$WORKSTATION_PUBLIC_KEY" ]]; then
  ssh_setup_args+=(--authorized-key "$WORKSTATION_PUBLIC_KEY")
fi

if [[ "$DRY_RUN" == "1" ]]; then
  ssh_setup_args+=(--dry-run)
fi

"$repo_root/scripts/install-packages.sh"
"$repo_root/scripts/install-node-lts.sh"
"$repo_root/ssh/setup-ssh.sh" "${ssh_setup_args[@]}"
"$repo_root/scripts/install-codex.sh"

if [[ "$RUN_CODEX_BOOTSTRAP" == "1" ]]; then
  codex_setup_args=(--dedicated-host --yes --home "$HOME" --workspace "$CODEX_WORKSPACE")

  if [[ "$ENABLE_PASSWORDLESS_SUDO" == "1" ]]; then
    codex_setup_args+=(--enable-passwordless-sudo)
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    codex_setup_args+=(--dry-run)
  fi

  "$repo_root/codex/setup-codex-permissions.sh" "${codex_setup_args[@]}"
fi

"$repo_root/scripts/install-skills.sh"

if [[ "$SKIP_CODEX_LOGIN" != "1" ]]; then
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'DRY would run codex login --device-auth\n'
  else
    codex login --device-auth
  fi
fi
