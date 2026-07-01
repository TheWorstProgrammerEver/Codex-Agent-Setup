# SSH Headless Access Setup

Purpose: make a Raspberry Pi or always-on Linux Codex agent reachable and recoverable without a keyboard or monitor.

The intended target is:

```text
AGENT_NAME@AGENT_NAME.local
```

Run this after the local user and network exist. The script assumes `sudo` works for the current operator, the target SSH user already exists, and any workstation public key is available as a public key line or file. Never provide or record private keys.

## Entrypoint

Preview:

```sh
AGENT_NAME=icarus ./ssh/setup-ssh.sh --dry-run
```

First supervised setup, keeping password SSH open until a workstation key is confirmed:

```sh
AGENT_NAME=icarus ./ssh/setup-ssh.sh \
  --authorized-key-file /path/to/workstation.pub \
  --enable-password-auth \
  --yes
```

After public-key-only login works from the workstation, disable password SSH:

```sh
AGENT_NAME=icarus ./ssh/setup-ssh.sh \
  --disable-password-auth \
  --yes
```

Useful flags:

- `--agent-name NAME`: defaults both hostname and SSH user to `NAME`.
- `--hostname NAME`: sets only the host name, producing `NAME.local`.
- `--user USER`: allows that local user over SSH.
- `--skip-package-install`: use when `agent-setup.sh` already installed packages.
- `--enable-passwordless-sudo`: installs an explicit Codex sudoers drop-in for the SSH user.

## Discovery

On the agent:

```sh
hostname
hostname -I
getent hosts "$(hostname -s).local" || true
systemctl is-active ssh || systemctl is-active sshd || true
systemctl is-active avahi-daemon || true
```

From the workstation:

```sh
ssh AGENT_NAME@AGENT_NAME.local
```

If `.local` resolution fails, use an IP from `hostname -I`:

```sh
ssh AGENT_NAME@LAN-IP
```

## What It Does

- Installs `openssh-server`, `tmux`, and `avahi-daemon` when `apt-get` is available.
- Enables and starts `ssh` or `sshd`, plus `avahi-daemon`.
- Sets the host name when `AGENT_NAME` or `--hostname` is provided.
- Creates or updates `~/.ssh/authorized_keys` for the target user.
- Installs `~/.local/bin/codex-attach`.
- Writes OpenSSH hardening in `/etc/ssh/sshd_config.d/99-codex-headless.conf`.
- Maintains `/usr/local/etc/sshd_config` too when that legacy path exists.
- Updates `~/REMOTE_ACCESS.md` with connection and validation commands.

The intended OpenSSH settings are:

```text
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication yes|no
KbdInteractiveAuthentication no
AllowUsers AGENT_NAME
```

## Validation

On the agent:

```sh
sudo sshd -t
sudo sshd -T | grep -E '^(permitrootlogin|pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|allowusers) '
```

From the workstation, confirm public-key-only login:

```sh
ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no AGENT_NAME@AGENT_NAME.local
```

Then attach to Codex:

```sh
codex-attach
```

## Recovery

If key login fails and password auth is still enabled, log in with the password and append the correct workstation public key:

```sh
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

If password auth was disabled too early, recover from a local console or an already trusted session:

```sh
sudo sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config.d/99-codex-headless.conf
sudo sshd -t
sudo systemctl reload ssh || sudo systemctl reload sshd
```

Backups from main config edits use paths like:

```text
/etc/ssh/sshd_config.codex-bootstrap-YYYYMMDDHHMMSS.bak
/usr/local/etc/sshd_config.codex-bootstrap-YYYYMMDDHHMMSS.bak
```

For `.local` failures, verify `avahi-daemon` is active, confirm the host name, check the workstation is on the same LAN, and fall back to `ssh AGENT_NAME@LAN-IP` while mDNS is fixed.

Durable notes belong in `~/REMOTE_ACCESS.md`. Record host/user/connection commands and validation state there, never private keys, tokens, passwords, or recovery codes.
