# Codex Permissions Setup

Purpose: define how much autonomy Codex should have on a dedicated agent host.

This setup is only for machines dedicated to Codex-managed work, such as a Raspberry Pi or always-on Linux box provisioned for agent execution. Do not run it on laptops, shared machines, production servers, or hosts with unrelated private data.

## Entrypoint

Preview:

```sh
./codex/setup-codex-permissions.sh --dedicated-host --dry-run
```

Apply the default dedicated-host posture:

```sh
./codex/setup-codex-permissions.sh --dedicated-host --yes
```

Allow root-owned system changes without sudo prompts only when that is intentional:

```sh
./codex/setup-codex-permissions.sh \
  --dedicated-host \
  --enable-passwordless-sudo \
  --yes
```

Useful flags:

- `--home PATH`: home directory to configure. Defaults to the current user's home.
- `--workspace PATH`: workspace to mark trusted in Codex config. Defaults to `--home`.
- `--sudo-user USER`: user for the optional sudoers drop-in. Defaults to the current user.
- `--dry-run`: print planned file and sudoers changes without writing them.

## Prerequisites

- Run as the target Codex login user, not root.
- Use a Linux host that is dedicated to Codex-managed work.
- Make sure the home directory exists and is owned by the target user.
- Install the Codex CLI first when you want the script to run strict config validation. `agent-setup.sh` handles this order.
- Make sure `sudo` works for the current operator before using `--enable-passwordless-sudo`.

## Risk Posture

The script configures Codex for maximum local autonomy:

```toml
sandbox_mode = "danger-full-access"
approval_policy = "never"
web_search = "live"

# Note: my-user is the local username on the agent host. It can differ from
# the durable agent identity, such as my-agent.
[projects."/home/my-user"]
trust_level = "trusted"
```

This means a fresh Codex session can read and write local files without sandbox prompts, use live web/search tools when available, and run commands from the trusted workspace without approval gates. If `--enable-passwordless-sudo` is used, Codex can also perform root-owned system changes through `sudo` as the configured user.

## Files Managed

- `~/.codex/config.toml`: Codex sandbox, approval, web/search, and trusted workspace defaults.
- `~/.codex/config-backups/`: timestamped backups of existing `config.toml` before changes.
- `~/AGENTS.md`: durable instructions future agents should read at session start.
- `~/CODEX_TODO.md`: durable setup tasks and parked work.
- `~/codex-notes/`: durable notes index, tasks, decisions, state, and credential metadata.
- `/etc/sudoers.d/90-codex-USER`: optional passwordless sudo drop-in.

## Setup Sequence

`agent-setup.sh` runs this after installing the Codex CLI and after SSH/headless access is configured. That order makes the host reachable first, then applies Codex's high-autonomy defaults before installing remaining reusable skills or starting a Codex login.

The script backs up an existing `~/.codex/config.toml` only when the generated config would change it. Repeated runs are intended to be safe and idempotent.

## Validation

After applying changes, start a fresh Codex session. The current process keeps the sandbox and approval policy it was launched with.

Validate the setup:

```sh
sed -n '1,120p' ~/.codex/config.toml
codex exec --strict-config --version
codex exec --sandbox danger-full-access --skip-git-repo-check "pwd"
```

If passwordless sudo was intentionally enabled, validate it separately:

```sh
sudo -n true
```

## Rollback

Restore the previous Codex config:

```sh
cp ~/.codex/config-backups/config.toml.YYYYMMDDTHHMMSSZ.bak ~/.codex/config.toml
chmod 600 ~/.codex/config.toml
```

Remove the optional sudoers drop-in:

```sh
sudo rm -f /etc/sudoers.d/90-codex-"$(id -un)"
sudo visudo -c
```

Then restart Codex or start a new session so the restored config is used.

## Security Notes

Do not put private SSH keys, Codex auth, GitHub App private keys, API keys, tokens, passwords, recovery codes, or seed phrases in durable notes. Prefer scoped and revocable credentials, especially GitHub Apps over personal access tokens. Record credential locations, owners, scopes, and revocation steps in `~/codex-notes/credentials/NOTES.md`, not secret values.
