# Codex Agent Setup

Bootstrap scripts for a fresh Raspberry Pi or similar Linux host that will be dedicated to Codex.

The setup is intentionally split into two phases:

1. Shell scripts install the minimum system dependencies, Codex CLI, and bootstrap skills.
2. Codex runs the installed bootstrap skills to configure durable notes, SSH/tmux access, and autonomous local defaults.

## Quick Start

```sh
cp examples/agent.env.example agent.env
$EDITOR agent.env
./agent-setup.sh
```

`agent.env` is ignored by git. Keep machine-local values there, such as a hostname override or workstation public SSH key.

## What It Installs

- `git`, `nodejs`, `npm`, `python3`, `sudo`, `openssh-server`, `tmux`, `avahi-daemon`, `bubblewrap`, `curl`, and `ca-certificates`
- `@openai/codex` via `npm install -g`
- The bootstrap skills from the skills repo:
  - `agent-bootstrap-yolo-permissions`
  - `agent-bootstrap-ssh`
  - `manage-durable-notes`

## Common Usage

Use defaults:

```sh
./agent-setup.sh
```

Preview shell actions:

```sh
./agent-setup.sh --dry-run
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

## Notes

- Do not commit private SSH keys, Codex auth, GitHub App private keys, API keys, tokens, passwords, or recovery codes.
- Public SSH keys are acceptable in local `agent.env` when useful for unattended SSH setup.
- Password SSH should remain enabled only until public-key login has been confirmed, then disabled through the SSH bootstrap skill.
