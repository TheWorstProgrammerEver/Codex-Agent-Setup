# Codex Agent Setup

Bootstrap scripts for a fresh Raspberry Pi or similar Linux host that will be dedicated to Codex.

The setup is intentionally split into three phases:

1. Shell scripts install the minimum system dependencies.
2. `ssh/setup-ssh.sh` configures hostname, SSH/tmux access, mDNS, workstation keys, and `~/REMOTE_ACCESS.md`.
3. Codex CLI and the remaining bootstrap skills configure durable notes and autonomous local defaults.

## Quick Start

```sh
cp examples/agent.env.example agent.env
$EDITOR agent.env
./agent-setup.sh
```

`agent.env` is ignored by git. Keep machine-local values there, such as `AGENT_NAME` or a workstation public SSH key.

## What It Installs

- `git`, `nodejs`, `npm`, `python3`, `sudo`, `openssh-server`, `tmux`, `avahi-daemon`, `bubblewrap`, `curl`, and `ca-certificates`
- Headless SSH access under `ssh/`, targeting `AGENT_NAME@AGENT_NAME.local`
- `@openai/codex` via `npm install -g`
- The bootstrap skills from the skills repo:
  - `agent-bootstrap-yolo-permissions`
  - `manage-durable-notes`

## Known Tested Environment

This bootstrap flow was first validated on:

- Raspberry Pi 5 Model B Rev 1.0
- Debian GNU/Linux 12 bookworm
- Linux `6.6.31+rpt-rpi-2712` on `aarch64`
- Node.js `v18.20.4`
- npm `9.2.0`
- Codex CLI `0.142.3`

Other Debian-like hosts should work if they provide `apt-get`, `systemd`, `sudo`, Node.js/npm, OpenSSH, tmux, and mDNS support through Avahi.

## Common Usage

Use defaults:

```sh
./agent-setup.sh
```

Preview shell actions:

```sh
./agent-setup.sh --dry-run
```

Set the intended host/user/mDNS target:

```sh
./agent-setup.sh --agent-name icarus
```

Use a specific skills repo ref:

```sh
./agent-setup.sh \
  --skills-repo-url https://github.com/TheWorstProgrammerEver/codex-skills.git \
  --skills-ref main
```

Install only shell dependencies and skills, then stop before Codex login/bootstrap:

```sh
./agent-setup.sh --skip-codex-login --skip-codex-bootstrap
```

Run only the SSH setup entrypoint:

```sh
AGENT_NAME=icarus ./ssh/setup-ssh.sh --dry-run
```

See `ssh/README.md` for intent, prerequisites, validation, and recovery.

## Notes

- Do not commit private SSH keys, Codex auth, GitHub App private keys, API keys, tokens, passwords, or recovery codes.
- Public SSH keys are acceptable in local `agent.env` when useful for unattended SSH setup.
- Password SSH should remain enabled only until public-key login has been confirmed, then disabled with `ssh/setup-ssh.sh --disable-password-auth --yes`.
