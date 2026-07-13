# Codex Agent Setup

Bootstrap scripts for a fresh Raspberry Pi or similar Linux host that will be dedicated to Codex.

The setup is intentionally split into six phases:

1. Shell scripts install the minimum system dependencies.
2. `scripts/install-node-lts.sh` installs the latest Node.js LTS from the official Node.js release index.
3. `ssh/setup-ssh.sh` configures hostname, SSH/tmux access, mDNS, workstation keys, and `~/REMOTE_ACCESS.md`.
4. `scripts/install-codex.sh` configures user-writable npm globals and installs or updates the Codex CLI as the target login user.
5. `codex/setup-codex-permissions.sh` configures Codex CLI autonomy, trusted workspace defaults, durable notes, and optional passwordless sudo.
6. The remaining reusable bootstrap skills are installed for future Codex sessions.

## Quick Start

```sh
cp examples/agent.env.example agent.env
$EDITOR agent.env
./agent-setup.sh
```

`agent.env` is ignored by git. Keep machine-local values there, such as `AGENT_NAME`, `AGENT_USER`, or a workstation public SSH key.

## What It Installs

- `git`, `python3`, `sudo`, `openssh-server`, `tmux`, `avahi-daemon`, `bubblewrap`, `curl`, and `ca-certificates`
- Latest Node.js LTS from `https://nodejs.org/dist/index.json`, installed under `/opt/node-lts` with `node`, `npm`, `npx`, and `corepack` symlinked into `/usr/local/bin`
- Headless SSH access under `ssh/`, targeting `AGENT_USER@AGENT_HOSTNAME.local`
- `@openai/codex` via `npm install -g` under the target user's npm global prefix, defaulting to `~/.local`
- High-autonomy Codex defaults under `codex/`:
  - `sandbox_mode = "danger-full-access"`
  - `approval_policy = "never"`
  - `web_search = "live"`
  - trusted workspace entry for the configured home/workspace
- Durable notes files: `~/AGENTS.md`, `~/CODEX_TODO.md`, and `~/codex-notes/`
- The remaining bootstrap skills from the skills repo:
  - `manage-durable-notes`

## Known Tested Environment

This bootstrap flow was first validated on:

- Raspberry Pi 5 Model B Rev 1.0
- Debian GNU/Linux 12 bookworm
- Linux `6.6.31+rpt-rpi-2712` on `aarch64`
- Node.js `v24.18.0`
- npm `11.16.0`
- Codex CLI `0.142.3`

Other Debian-like hosts should work if they provide `apt-get`, `systemd`, `sudo`, OpenSSH, tmux, and mDNS support through Avahi. Debian stable's packaged `nodejs` major version can lag behind modern app tooling such as Vite, Vitest, and Supabase. This bootstrap therefore installs a system-level Node.js LTS runtime directly from Node.js release metadata instead of relying on the distro `nodejs` package.

## Node.js LTS Runtime

`scripts/install-node-lts.sh` reads the official Node.js distribution index and chooses the first release whose `lts` field is set. That intentionally excludes Current releases until Node.js promotes them to LTS. As of 2026-07-04, this resolves Node 24 LTS (`Krypton`) rather than Node 26 Current.

The installer downloads the matching Linux binary tarball and `SHASUMS256.txt`, verifies the tarball checksum, installs the release under `/opt/node-lts/versions/<version>`, updates `/opt/node-lts/current`, and manages `/usr/local/bin/node`, `/usr/local/bin/npm`, `/usr/local/bin/npx`, and `/usr/local/bin/corepack`. This makes the runtime available to interactive shells and non-interactive/systemd-launched setup tasks without depending on shell profile files.

Maintenance is idempotent: rerun `./agent-setup.sh` or `./scripts/install-node-lts.sh` to move to the latest LTS release. Set `NODE_LTS_LINE=24` only when deliberately pinning a major LTS line; remove that override to resume latest-LTS tracking. Set `NODE_LTS_FORCE=1` to reinstall the resolved version.

## Codex npm Globals

`scripts/install-codex.sh` runs as the target login user, configures `npm config set prefix "$HOME/.local"` by default, and installs or updates `@openai/codex` without `sudo`. This keeps future Codex npm self-updates user-writable even when Node.js itself is installed under a root-owned prefix such as `/opt/node-lts`.

Set `CODEX_INSTALL_UPDATE=0` only when you want to validate an existing user-scoped Codex install without contacting npm during that run.

The installer writes managed PATH blocks to `~/.profile` and `~/.bashrc` so `~/.local/bin` is ahead of root-owned global binary directories after a new shell starts. It also validates:

```sh
npm config get prefix
command -v codex
codex --version
```

For non-login systemd services or timers that launch Codex, do not assume interactive shell startup files have run. Either give the service a PATH that starts with the user npm bin directory, or configure the service to call the Codex binary explicitly. For example:

```ini
[Service]
User=my-user
Environment=PATH=/home/my-user/.local/bin:/usr/local/bin:/usr/bin:/bin
Environment=CODEX_BIN=/home/my-user/.local/bin/codex
```

If an existing shell has cached an older root-owned `codex` path, clear the shell command cache and re-check resolution:

```sh
hash -r
command -v codex
codex --version
```

Starting a fresh login shell, reattaching after restarting a long-lived tmux session, or restarting a systemd user/service unit may also be necessary for PATH changes to take effect.

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
./agent-setup.sh --agent-name my-agent --ssh-user my-user
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

Run only the Node.js LTS installer:

```sh
./scripts/install-node-lts.sh
```

Run a Vite/Vitest/Supabase-style package smoke check:

```sh
./scripts/smoke-node-tooling.sh
```

Run the focused Codex npm prefix test with fake `npm`/`codex` commands:

```sh
./scripts/test-install-codex.sh
```

Run only the SSH setup entrypoint:

```sh
AGENT_NAME=my-agent AGENT_USER=my-user ./ssh/setup-ssh.sh --dry-run
```

See `ssh/README.md` for intent, prerequisites, validation, and recovery.

Run only the Codex permissions entrypoint:

```sh
./codex/setup-codex-permissions.sh --dedicated-host --dry-run
```

See `codex/README.md` for scope, risk posture, validation, rollback, and security notes.

## Notes

- Do not commit private SSH keys, Codex auth, GitHub App private keys, API keys, tokens, passwords, or recovery codes.
- Public SSH keys are acceptable in local `agent.env` when useful for unattended SSH setup.
- Password SSH should remain enabled only until public-key login has been confirmed, then disabled with `ssh/setup-ssh.sh --disable-password-auth --yes`.
