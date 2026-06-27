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
  --hostname NAME               Set the host name before Codex bootstrap.
  --ssh-public-key KEY          Public SSH key line to pass to the SSH bootstrap skill.
  --ssh-public-key-file PATH    File containing public SSH key lines.
  --enable-passwordless-sudo    Ask the bootstrap skills to enable passwordless sudo.
  --disable-password-auth       Ask the SSH bootstrap skill to disable password auth.
  --skip-codex-login            Do not run `codex login --device-auth`.
  --skip-codex-bootstrap        Do not run `codex exec` after installing skills.
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
AGENT_HOSTNAME="${AGENT_HOSTNAME:-}"
WORKSTATION_PUBLIC_KEY="${WORKSTATION_PUBLIC_KEY:-}"
WORKSTATION_PUBLIC_KEY_FILE="${WORKSTATION_PUBLIC_KEY_FILE:-}"
ENABLE_PASSWORDLESS_SUDO="${ENABLE_PASSWORDLESS_SUDO:-0}"
DISABLE_PASSWORD_AUTH="${DISABLE_PASSWORD_AUTH:-0}"
SKIP_CODEX_LOGIN="${SKIP_CODEX_LOGIN:-0}"
RUN_CODEX_BOOTSTRAP="${RUN_CODEX_BOOTSTRAP:-1}"
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
    --hostname)
      AGENT_HOSTNAME="${2:?missing name after --hostname}"
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

export SKILLS_REPO_URL
export SKILLS_REF
export DRY_RUN

"$repo_root/scripts/preflight.sh"

if [[ -n "$AGENT_HOSTNAME" ]]; then
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'DRY would set hostname to %s\n' "$AGENT_HOSTNAME"
  else
    sudo hostnamectl set-hostname "$AGENT_HOSTNAME"
  fi
fi

"$repo_root/scripts/install-packages.sh"
"$repo_root/scripts/install-codex.sh"
"$repo_root/scripts/install-skills.sh"

if [[ "$SKIP_CODEX_LOGIN" != "1" ]]; then
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'DRY would run codex login --device-auth\n'
  else
    codex login --device-auth
  fi
fi

if [[ "$RUN_CODEX_BOOTSTRAP" == "1" ]]; then
  ssh_args="--yes"
  yolo_args="--dedicated-host --yes"

  if [[ "$ENABLE_PASSWORDLESS_SUDO" == "1" ]]; then
    ssh_args="$ssh_args --enable-passwordless-sudo"
    yolo_args="$yolo_args --enable-passwordless-sudo"
  fi

  if [[ "$DISABLE_PASSWORD_AUTH" == "1" ]]; then
    ssh_args="$ssh_args --disable-password-auth"
  else
    ssh_args="$ssh_args --enable-password-auth"
  fi

  if [[ -n "$WORKSTATION_PUBLIC_KEY_FILE" ]]; then
    ssh_args="$ssh_args --authorized-key-file $WORKSTATION_PUBLIC_KEY_FILE"
  elif [[ -n "$WORKSTATION_PUBLIC_KEY" ]]; then
    ssh_args="$ssh_args --authorized-key '$WORKSTATION_PUBLIC_KEY'"
  fi

  prompt="Use \$agent-bootstrap-yolo-permissions, \$manage-durable-notes, and \$agent-bootstrap-ssh to configure this dedicated Codex host. Run each applicable script in dry-run mode first, then apply. Use these arguments when applying: yolo permissions: $yolo_args; durable notes: --home \$HOME; ssh: $ssh_args. Preserve credentials hygiene: do not store private keys, tokens, passwords, or recovery codes in durable notes."

  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'DRY would run codex exec with prompt:\n%s\n' "$prompt"
  else
    codex exec --sandbox danger-full-access --skip-git-repo-check "$prompt"
  fi
fi
