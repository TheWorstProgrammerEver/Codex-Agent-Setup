#!/usr/bin/env python3
import argparse
import dataclasses
import datetime as _dt
import getpass
import os
import pwd
import shutil
import socket
import subprocess
import sys
import tempfile
import ipaddress
from pathlib import Path


BEGIN = "# BEGIN CODEX HEADLESS SSH"
END = "# END CODEX HEADLESS SSH"
LEGACY_HEADER = "# Codex-managed headless SSH defaults for this dedicated Pi."
REMOTE_BEGIN = "<!-- BEGIN CODEX SSH ACCESS -->"
REMOTE_END = "<!-- END CODEX SSH ACCESS -->"
CODEX_SSH_KEYS = {
    "permitrootlogin",
    "pubkeyauthentication",
    "passwordauthentication",
    "kbdinteractiveauthentication",
    "allowusers",
}


@dataclasses.dataclass(frozen=True)
class AccessInfo:
    host: str
    fqdn: str
    ips: str
    mdns: str
    user: str
    password_auth: str
    auth_path: Path
    remote_note: Path


def run(cmd: list[str], *, dry_run: bool = False, check: bool = True) -> subprocess.CompletedProcess:
    print("+ " + " ".join(cmd))
    if dry_run:
        return subprocess.CompletedProcess(cmd, 0, "", "")
    return subprocess.run(cmd, check=check, text=True)


def capture(cmd: list[str]) -> str:
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""


def find_executable(name: str) -> str | None:
    found = shutil.which(name)
    if found:
        return found
    for prefix in ("/usr/local/sbin", "/usr/sbin", "/sbin"):
        candidate = Path(prefix) / name
        if candidate.exists() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def build_access_info(home: Path, user: str, password_auth: str) -> AccessInfo:
    host = socket.gethostname()
    fqdn = socket.getfqdn()
    raw_ips = capture(["hostname", "-I"])
    primary_ip = ""
    route_devices = set()
    route = capture(["ip", "-4", "route", "get", "1.1.1.1"])
    route_parts = route.split()
    if "dev" in route_parts:
        dev_index = route_parts.index("dev") + 1
        if dev_index < len(route_parts):
            route_devices.add(route_parts[dev_index])
    if "src" in route_parts:
        src_index = route_parts.index("src") + 1
        if src_index < len(route_parts):
            primary_ip = route_parts[src_index]
    interface_ips: list[tuple[str, str]] = []
    for line in capture(["ip", "-4", "-o", "addr", "show", "scope", "global"]).splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        device = parts[1]
        cidr = parts[3]
        ip_value = cidr.split("/", 1)[0]
        interface_ips.append((device, ip_value))
    filtered_ips: list[str] = []
    if primary_ip:
        filtered_ips.append(primary_ip)
    candidate_ips = [
        ip_value
        for device, ip_value in interface_ips
        if not route_devices or device in route_devices
    ]
    if not candidate_ips:
        candidate_ips = raw_ips.split()
    for value in candidate_ips:
        try:
            ip = ipaddress.ip_address(value)
        except ValueError:
            continue
        if ip.is_loopback or ip.is_link_local:
            continue
        if ip.version == 4 and value not in filtered_ips:
            filtered_ips.append(value)
    ips = " ".join(filtered_ips) or raw_ips
    return AccessInfo(
        host=host,
        fqdn=fqdn,
        ips=ips or "unknown",
        mdns=f"{host}.local",
        user=user,
        password_auth=password_auth,
        auth_path=home / ".ssh" / "authorized_keys",
        remote_note=home / "REMOTE_ACCESS.md",
    )


def install_root_text(target: Path, text: str, mode: str, dry_run: bool) -> None:
    if target.exists():
        try:
            if target.read_text(errors="ignore") == text:
                print(f"{target} already up to date")
                return
        except OSError:
            pass
    with tempfile.NamedTemporaryFile("w", delete=False) as tmp:
        tmp.write(text)
        tmp_path = tmp.name
    try:
        run(["sudo", "install", "-o", "root", "-g", "root", "-m", mode, tmp_path, str(target)], dry_run=dry_run)
    finally:
        Path(tmp_path).unlink(missing_ok=True)


def backup_root_file(path: Path, dry_run: bool) -> None:
    if not path.exists():
        return
    suffix = _dt.datetime.now().strftime("%Y%m%d%H%M%S")
    backup = Path(str(path) + f".codex-bootstrap-{suffix}.bak")
    run(["sudo", "cp", "-n", str(path), str(backup)], dry_run=dry_run, check=False)


def remove_legacy_codex_block(text: str) -> str:
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    i = 0
    while i < len(lines):
        if lines[i].strip() == LEGACY_HEADER:
            i += 1
            while i < len(lines):
                stripped = lines[i].strip()
                if not stripped:
                    i += 1
                    break
                key = stripped.split()[0].lower() if stripped.split() else ""
                if key not in CODEX_SSH_KEYS:
                    break
                i += 1
            continue
        out.append(lines[i])
        i += 1
    return "".join(out)


def replace_marked_block(text: str, block: str) -> str:
    text = remove_legacy_codex_block(text)
    if BEGIN in text and END in text:
        before, rest = text.split(BEGIN, 1)
        _, after = rest.split(END, 1)
        tail = after.strip()
        if tail:
            return before.rstrip() + "\n\n" + block.rstrip() + "\n\n" + tail + "\n"
        return before.rstrip() + "\n\n" + block.rstrip() + "\n"
    if text and not text.endswith("\n"):
        text += "\n"
    return text + "\n" + block.rstrip() + "\n"


def detect_password_auth(dry_run: bool) -> str:
    for path in (Path("/etc/ssh/sshd_config.d/99-codex-headless.conf"), Path("/usr/local/etc/sshd_config"), Path("/etc/ssh/sshd_config")):
        if not path.exists():
            continue
        try:
            for line in path.read_text(errors="ignore").splitlines():
                parts = line.strip().split()
                if len(parts) >= 2 and parts[0].lower() == "passwordauthentication":
                    return parts[1].lower()
        except OSError:
            continue
    sshd = find_executable("sshd")
    if not dry_run and sshd:
        result = subprocess.run(["sudo", sshd, "-T"], text=True, capture_output=True)
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                parts = line.split()
                if len(parts) == 2 and parts[0] == "passwordauthentication":
                    return parts[1].lower()
    return "yes"


def ssh_block(user: str, password_auth: str) -> str:
    return (
        f"{BEGIN}\n"
        "PermitRootLogin no\n"
        "PubkeyAuthentication yes\n"
        f"PasswordAuthentication {password_auth}\n"
        "KbdInteractiveAuthentication no\n"
        f"AllowUsers {user}\n"
        f"{END}\n"
    )


def ensure_tmux(dry_run: bool) -> None:
    if shutil.which("tmux"):
        print("tmux is already installed.")
        return
    if shutil.which("apt-get"):
        run(["sudo", "apt-get", "install", "-y", "tmux"], dry_run=dry_run)
        return
    print("tmux is missing and no apt-get was found; install tmux manually.", file=sys.stderr)


def install_codex_attach(home: Path, dry_run: bool) -> None:
    target = home / ".local" / "bin" / "codex-attach"
    script = """#!/usr/bin/env bash
set -euo pipefail

session="${1:-codex}"

if [[ "$session" == "-h" || "$session" == "--help" ]]; then
  printf 'Usage: codex-attach [session-name]\\n'
  printf 'Attach to an existing tmux session, or start Codex in a new one.\\n'
  exit 0
fi

if tmux has-session -t "$session" 2>/dev/null; then
  exec tmux attach-session -t "$session"
fi

if command -v codex >/dev/null 2>&1; then
  exec tmux new-session -s "$session" codex
fi

exec tmux new-session -s "$session"
"""
    print(f"Installing {target}")
    if dry_run:
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(script)
    os.chmod(target, 0o755)


def collect_keys(args: argparse.Namespace) -> list[str]:
    keys: list[str] = []
    if args.authorized_key:
        keys.append(args.authorized_key.strip())
    if args.authorized_key_file:
        keys.extend(Path(args.authorized_key_file).expanduser().read_text().splitlines())
    if args.authorized_key_stdin:
        keys.extend(sys.stdin.read().splitlines())
    clean = []
    for key in keys:
        key = key.strip()
        if not key or key.startswith("#"):
            continue
        if not (key.startswith("ssh-") or key.startswith("sk-")):
            raise ValueError(f"Refusing invalid public key line: {key[:32]}")
        clean.append(key)
    return clean


def ensure_authorized_keys(home: Path, keys: list[str], dry_run: bool) -> Path:
    ssh_dir = home / ".ssh"
    auth = ssh_dir / "authorized_keys"
    print(f"Ensuring {auth}")
    if dry_run:
        return auth
    ssh_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    auth.touch(mode=0o600, exist_ok=True)
    existing = auth.read_text().splitlines()
    for key in keys:
        if key not in existing:
            existing.append(key)
    auth.write_text("\n".join(existing).rstrip() + ("\n" if existing else ""))
    os.chmod(ssh_dir, 0o700)
    os.chmod(auth, 0o600)
    return auth


def configure_sshd(user: str, password_auth: str, dry_run: bool) -> None:
    block = ssh_block(user, password_auth)

    etc_main = Path("/etc/ssh/sshd_config")
    etc_drop_dir = Path("/etc/ssh/sshd_config.d")
    if etc_main.exists() or etc_drop_dir.exists():
        run(["sudo", "mkdir", "-p", str(etc_drop_dir)], dry_run=dry_run)
        install_root_text(etc_drop_dir / "99-codex-headless.conf", block, "0644", dry_run)
        if etc_main.exists():
            text = etc_main.read_text(errors="ignore")
            include = "Include /etc/ssh/sshd_config.d/*.conf"
            if include not in text:
                backup_root_file(etc_main, dry_run)
                updated = text.rstrip() + "\n\n# Codex-managed include for sshd drop-ins.\n" + include + "\n"
                install_root_text(etc_main, updated, "0644", dry_run)

    local_main = Path("/usr/local/etc/sshd_config")
    if local_main.exists():
        updated = replace_marked_block(local_main.read_text(errors="ignore"), block)
        if updated == local_main.read_text(errors="ignore"):
            print(f"{local_main} already up to date")
        else:
            backup_root_file(local_main, dry_run)
            install_root_text(local_main, updated, "0644", dry_run)

    sshd = find_executable("sshd")
    if sshd:
        run(["sudo", sshd, "-t"], dry_run=dry_run)
    reloaded = False
    if shutil.which("systemctl"):
        for service in ("ssh", "sshd"):
            active = subprocess.run(["systemctl", "is-active", service], text=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if active.returncode == 0:
                run(["sudo", "systemctl", "reload", service], dry_run=dry_run, check=False)
                reloaded = True
    if not reloaded:
        print("SSH config validated, but no active systemd ssh service was reloaded.")


def install_passwordless_sudo(user: str, dry_run: bool) -> None:
    target = Path(f"/etc/sudoers.d/90-codex-{user}")
    text = f"{user} ALL=(ALL) NOPASSWD:ALL\n"
    if target.exists():
        try:
            if target.read_text(errors="ignore") == text:
                print(f"{target} already up to date")
                return
        except OSError:
            pass
    existing = subprocess.run(["sudo", "-n", "-l", "-U", user], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if existing.returncode == 0 and not target.exists():
        print(f"sudo reports privileges for {user}; installing explicit Codex sudoers drop-in for repeatability.")
    with tempfile.NamedTemporaryFile("w", delete=False) as tmp:
        tmp.write(text)
        tmp_path = tmp.name
    try:
        run(["sudo", "visudo", "-cf", tmp_path], dry_run=dry_run)
        run(["sudo", "install", "-o", "root", "-g", "root", "-m", "0440", tmp_path, str(target)], dry_run=dry_run)
    finally:
        Path(tmp_path).unlink(missing_ok=True)


def render_remote_block(info: AccessInfo) -> str:
    password_line = f"PasswordAuthentication {info.password_auth}"
    password_status = "disabled" if info.password_auth == "no" else "enabled"
    key_install = (
        f"ssh {info.user}@{info.mdns} "
        "'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys' "
        "< ~/.ssh/id_ed25519.pub"
    )
    return (
        f"{REMOTE_BEGIN}\n"
        "## Codex SSH Access\n\n"
        f"Host: `{info.host}`\n"
        f"mDNS name: `{info.mdns}`\n"
        f"FQDN: `{info.fqdn}`\n"
        f"LAN addresses: `{info.ips}`\n"
        f"SSH user: `{info.user}`\n\n"
        f"Primary connection target: `{info.user}@{info.mdns}`\n\n"
        "## Current Setup\n\n"
        "- SSH is configured for headless Codex access.\n"
        "- `tmux` is installed or expected to be installed.\n"
        "- `~/.local/bin/codex-attach` starts or attaches to the persistent `codex` tmux session.\n"
        "- Effective intended SSH settings:\n"
        "  - `PermitRootLogin no`\n"
        "  - `PubkeyAuthentication yes`\n"
        f"  - `{password_line}`\n"
        "  - `KbdInteractiveAuthentication no`\n"
        f"  - `AllowUsers {info.user}`\n\n"
        "## Connect\n\n"
        "Prefer mDNS from macOS on the same LAN:\n\n"
        "```bash\n"
        f"ssh {info.user}@{info.mdns}\n"
        "codex-attach\n"
        "```\n\n"
        "If mDNS does not resolve, use one of the LAN addresses shown above:\n\n"
        "```bash\n"
        f"ssh {info.user}@<LAN-IP>\n"
        "codex-attach\n"
        "```\n\n"
        "## Key Setup\n\n"
        "Install a MacBook public key using password login while password auth is still enabled:\n\n"
        "```bash\n"
        f"{key_install}\n"
        "```\n\n"
        "Public-key-only test from the workstation:\n\n"
        "```bash\n"
        f"ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no {info.user}@{info.mdns}\n"
        "```\n\n"
        f"SSH password authentication is currently {password_status}.\n"
        f"{REMOTE_END}\n"
    )


def render_remote_note(info: AccessInfo) -> str:
    return "# Remote Access\n\n" + render_remote_block(info)


def replace_remote_block(existing: str, block: str) -> str:
    if REMOTE_BEGIN in existing and REMOTE_END in existing:
        before, rest = existing.split(REMOTE_BEGIN, 1)
        _, after = rest.split(REMOTE_END, 1)
        return before.rstrip() + "\n\n" + block.rstrip() + "\n" + after.lstrip()
    if existing.strip():
        return existing.rstrip() + "\n\n" + block
    return "# Remote Access\n\n" + block


def print_access_summary(info: AccessInfo) -> None:
    print("\n== Codex SSH Access ==")
    print(f"Host: {info.host}")
    print(f"mDNS: {info.mdns}")
    print(f"LAN addresses: {info.ips}")
    print(f"SSH user: {info.user}")
    print(f"Connection target: {info.user}@{info.mdns}")
    print(f"PasswordAuthentication: {info.password_auth}")
    print(f"Authorized keys: {info.auth_path}")
    print("")
    print("Connect from macOS on the same LAN:")
    print(f"  ssh {info.user}@{info.mdns}")
    print("  codex-attach")
    print("")
    print("If mDNS fails, use one LAN IP:")
    print(f"  ssh {info.user}@<LAN-IP>")
    print("")
    if info.password_auth != "no":
        print("Install a MacBook key before disabling password auth:")
        print(
            f"  ssh {info.user}@{info.mdns} "
            "'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys' "
            "< ~/.ssh/id_ed25519.pub"
        )
        print("")
    print("Public-key-only test:")
    print(f"  ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no {info.user}@{info.mdns}")
    print("")
    print(f"Durable note: {info.remote_note}")


def update_notes(home: Path, info: AccessInfo, dry_run: bool) -> None:
    remote = info.remote_note
    agents = home / "AGENTS.md"
    todo = home / "CODEX_TODO.md"
    block = render_remote_block(info)
    print(f"Updating {remote}")
    if not dry_run:
        if not remote.exists():
            remote.write_text(render_remote_note(info))
        else:
            current = remote.read_text(errors="ignore")
            updated = replace_remote_block(current, block)
            if updated == current:
                print(f"{remote} already up to date")
            else:
                remote.write_text(updated)
        if not agents.exists():
            agents.write_text("# Codex Home Notes\n\n")
        if "REMOTE_ACCESS.md" not in agents.read_text():
            with agents.open("a") as handle:
                handle.write("- For headless access details, check `REMOTE_ACCESS.md` before changing SSH or tmux behavior.\n")
        if not todo.exists():
            todo.write_text("# Codex TODO\n\n## Active\n\n- No active durable tasks.\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Bootstrap SSH and tmux access for a dedicated Codex host.")
    parser.add_argument("--user", default=getpass.getuser(), help="Login user to allow over SSH.")
    parser.add_argument("--home", default=None, help="Home directory for the login user.")
    parser.add_argument("--authorized-key", help="Public key line to append to authorized_keys.")
    parser.add_argument("--authorized-key-file", help="File containing public key lines to append.")
    parser.add_argument("--authorized-key-stdin", action="store_true", help="Read public key lines from stdin.")
    parser.add_argument("--enable-password-auth", action="store_true", help="Set PasswordAuthentication yes for the initial key-install phase.")
    parser.add_argument("--disable-password-auth", action="store_true", help="Set PasswordAuthentication no. Requires at least one authorized key.")
    parser.add_argument("--enable-passwordless-sudo", action="store_true", help="Install a NOPASSWD sudoers drop-in for the SSH user.")
    parser.add_argument("--yes", action="store_true", help="Do not ask for confirmation.")
    parser.add_argument("--dry-run", action="store_true", help="Print planned changes without writing files.")
    args = parser.parse_args()

    try:
        pw = pwd.getpwnam(args.user)
    except KeyError:
        print(f"SSH user does not exist locally: {args.user}", file=sys.stderr)
        return 2
    home = Path(args.home).expanduser().resolve() if args.home else Path(pw.pw_dir)
    keys = collect_keys(args)

    auth_path = home / ".ssh" / "authorized_keys"
    existing_key_count = 0
    if auth_path.exists():
        existing_key_count = len([line for line in auth_path.read_text().splitlines() if line.strip() and not line.startswith("#")])
    if args.enable_password_auth and args.disable_password_auth:
        print("Choose only one of --enable-password-auth or --disable-password-auth.", file=sys.stderr)
        return 2
    if args.disable_password_auth and existing_key_count + len(keys) == 0:
        print("Refusing to disable password auth without at least one authorized public key.", file=sys.stderr)
        return 2
    if args.disable_password_auth and not args.yes and not args.dry_run:
        answer = input("Disable SSH password authentication now? Type 'yes': ")
        if answer != "yes":
            print("Aborted.", file=sys.stderr)
            return 3

    if args.disable_password_auth:
        password_auth = "no"
    elif args.enable_password_auth:
        password_auth = "yes"
    else:
        password_auth = detect_password_auth(args.dry_run)
    access_info = build_access_info(home, args.user, password_auth)

    ensure_tmux(args.dry_run)
    ensure_authorized_keys(home, keys, args.dry_run)
    install_codex_attach(home, args.dry_run)
    configure_sshd(args.user, password_auth, args.dry_run)
    if args.enable_passwordless_sudo:
        install_passwordless_sudo(args.user, args.dry_run)
    update_notes(home, access_info, args.dry_run)

    sshd = find_executable("sshd")
    if not args.dry_run and sshd:
        result = subprocess.run(["sudo", sshd, "-T"], text=True, capture_output=True)
        if result.returncode == 0:
            for key in ("permitrootlogin", "pubkeyauthentication", "passwordauthentication", "kbdinteractiveauthentication", "allowusers"):
                for line in result.stdout.splitlines():
                    if line.startswith(key + " "):
                        print(line)
    print_access_summary(access_info)
    print("SSH bootstrap complete. Use codex-attach after logging in.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
