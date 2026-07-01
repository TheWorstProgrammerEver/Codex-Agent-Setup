#!/usr/bin/env python3
import argparse
import datetime as dt
import getpass
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def toml_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def run(
    cmd: list[str],
    *,
    dry_run: bool = False,
    check: bool = True,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess:
    print("+ " + " ".join(cmd))
    if dry_run:
        return subprocess.CompletedProcess(cmd, 0, "", "")
    return subprocess.run(cmd, check=check, text=True, env=env)


def set_top_level(lines: list[str], key: str, value: str) -> list[str]:
    out: list[str] = []
    replaced = False
    first_table = None
    key_pattern = re.compile(rf"^{re.escape(key)}\s*=")

    for index, line in enumerate(lines):
        stripped = line.strip()
        if first_table is None and stripped.startswith("["):
            first_table = index

        if first_table is None and key_pattern.match(stripped):
            if not replaced:
                out.append(f"{key} = {value}\n")
                replaced = True
            continue

        out.append(line)

    if not replaced:
        insert_at = first_table if first_table is not None else len(out)
        out.insert(insert_at, f"{key} = {value}\n")

    return out


def set_project_trust(lines: list[str], workspace: str) -> list[str]:
    header = f"[projects.{toml_string(workspace)}]"
    out: list[str] = []
    found = False
    index = 0

    while index < len(lines):
        if lines[index].strip() == header:
            found = True
            out.append(lines[index])
            index += 1
            section: list[str] = []

            while index < len(lines) and not lines[index].lstrip().startswith("["):
                section.append(lines[index])
                index += 1

            if any(line.strip().startswith("trust_level ") for line in section):
                section = [
                    "trust_level = \"trusted\"\n" if line.strip().startswith("trust_level ") else line
                    for line in section
                ]
            else:
                section.append("trust_level = \"trusted\"\n")

            out.extend(section)
            continue

        out.append(lines[index])
        index += 1

    if not found:
        if out and out[-1].strip():
            out.append("\n")
        out.append(header + "\n")
        out.append("trust_level = \"trusted\"\n")

    return out


def backup_path(config_path: Path) -> Path:
    backup_dir = config_path.parent / "config-backups"
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    candidate = backup_dir / f"{config_path.name}.{stamp}.bak"
    counter = 1

    while candidate.exists():
        candidate = backup_dir / f"{config_path.name}.{stamp}.{counter}.bak"
        counter += 1

    return candidate


def update_codex_config(home: Path, workspace: Path, dry_run: bool) -> None:
    config_dir = home / ".codex"
    config_path = config_dir / "config.toml"
    old_text = config_path.read_text() if config_path.exists() else ""
    lines = old_text.splitlines(keepends=True)
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"

    lines = set_top_level(lines, "sandbox_mode", toml_string("danger-full-access"))
    lines = set_top_level(lines, "approval_policy", toml_string("never"))
    lines = set_top_level(lines, "web_search", toml_string("live"))
    lines = set_project_trust(lines, str(workspace))
    new_text = "".join(lines)

    if old_text == new_text:
        print(f"Codex config already matches target posture: {config_path}")
        return

    print(f"Updating {config_path}")
    target_backup = backup_path(config_path) if config_path.exists() else None
    if config_path.exists():
        print(f"Backing up existing Codex config to {target_backup}")

    if dry_run:
        print("Would write Codex config:")
        print(new_text)
        return

    config_dir.mkdir(mode=0o700, parents=True, exist_ok=True)

    if target_backup:
        target_backup.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        shutil.copy2(config_path, target_backup)
        os.chmod(target_backup, 0o600)

    config_path.write_text(new_text)
    os.chmod(config_path, 0o600)


def ensure_dir(path: Path, dry_run: bool) -> None:
    if path.exists():
        return
    print(f"Creating directory {path}")
    if not dry_run:
        path.mkdir(mode=0o700, parents=True, exist_ok=True)


def write_if_missing(path: Path, text: str, dry_run: bool) -> None:
    if path.exists():
        return
    print(f"Creating {path}")
    if not dry_run:
        path.write_text(text)


def ensure_line(path: Path, line: str, dry_run: bool, marker: str | None = None) -> None:
    existing = path.read_text() if path.exists() else ""
    if (marker or line) in existing:
        return
    print(f"Adding durable note to {path}")
    if not dry_run:
        with path.open("a") as handle:
            if existing and not existing.endswith("\n"):
                handle.write("\n")
            handle.write(line + "\n")


def update_durable_notes(home: Path, dry_run: bool) -> None:
    today = dt.date.today().isoformat()
    agents = home / "AGENTS.md"
    todos = home / "CODEX_TODO.md"
    notes = home / "codex-notes"
    agents_missing = not agents.exists()

    ensure_dir(notes, dry_run)
    ensure_dir(notes / "tasks", dry_run)
    ensure_dir(notes / "state", dry_run)
    ensure_dir(notes / "decisions", dry_run)
    ensure_dir(notes / "credentials", dry_run)

    write_if_missing(
        notes / "INDEX.md",
        "# Codex Notes Index\n\n"
        f"Initialized: {today}\n\n"
        "## Read First\n\n"
        "- `tasks/TODO.md` - active and parked work.\n"
        "- `state/CURRENT.md` - current host and project orientation when maintained.\n"
        "- `decisions/` - dated setup decisions and rationale.\n"
        "- `credentials/NOTES.md` - credential metadata only; no secrets.\n",
        dry_run,
    )
    write_if_missing(
        notes / "tasks" / "TODO.md",
        "# Codex Durable Tasks\n\n"
        f"Last updated: {today}\n\n"
        "## Active\n\n"
        "- No active durable tasks.\n\n"
        "## Parked\n\n"
        "- Record setup follow-ups here when they should survive Codex sessions.\n",
        dry_run,
    )
    write_if_missing(
        notes / "credentials" / "NOTES.md",
        "# Credential Notes\n\n"
        "Record credential locations, owners, scopes, and revocation steps here.\n"
        "Do not record secret values, private keys, tokens, passwords, recovery codes, or seed phrases.\n",
        dry_run,
    )

    write_if_missing(
        agents,
        "# Codex Home Notes\n\n"
        "- At the start of work in this home directory, check `CODEX_TODO.md` for durable setup tasks and parked work.\n"
        "- Treat this machine as a dedicated Codex-managed host only if the user explicitly says so.\n"
        "- Keep credentials scoped and revocable; prefer GitHub Apps over personal access tokens for GitHub automation.\n"
        "- Durable notes live under `~/codex-notes`; read `~/codex-notes/INDEX.md` before relying on memory from previous sessions.\n",
        dry_run,
    )
    if not agents_missing:
        ensure_line(
            agents,
            "- At the start of work in this home directory, check `CODEX_TODO.md` for durable setup tasks and parked work.",
            dry_run,
            marker="CODEX_TODO.md",
        )
        ensure_line(
            agents,
            "- Treat this machine as a dedicated Codex-managed host only if the user explicitly says so.",
            dry_run,
            marker="dedicated Codex-managed host",
        )
        ensure_line(
            agents,
            "- Keep credentials scoped and revocable; prefer GitHub Apps over personal access tokens for GitHub automation.",
            dry_run,
            marker="scoped and revocable",
        )
        ensure_line(
            agents,
            "- Durable notes live under `~/codex-notes`; read `~/codex-notes/INDEX.md` before relying on memory from previous sessions.",
            dry_run,
            marker="codex-notes",
        )
    write_if_missing(
        todos,
        "# Codex TODO\n\n"
        f"Last updated: {today}\n\n"
        "## Active\n\n"
        "- No active durable tasks.\n\n"
        "## Parked\n\n"
        "- Set up GitHub access using a scoped, revocable GitHub App when requested.\n",
        dry_run,
    )


def install_passwordless_sudo(user: str, dry_run: bool) -> None:
    if not re.match(r"^[A-Za-z0-9_.-]+$", user):
        raise ValueError(f"Refusing unsafe sudoers user name: {user}")

    existing = subprocess.run(["sudo", "-n", "true"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if existing.returncode == 0:
        print("Passwordless sudo already works; not installing a sudoers drop-in.")
        return

    sudoers = f"{user} ALL=(ALL) NOPASSWD:ALL\n"
    target = f"/etc/sudoers.d/90-codex-{user}"
    print(f"Installing passwordless sudo drop-in at {target}")

    if dry_run:
        print(f"DRY would validate sudoers content and install {target}")
        return

    with tempfile.NamedTemporaryFile("w", delete=False) as tmp:
        tmp.write(sudoers)
        tmp_path = tmp.name

    try:
        run(["sudo", "visudo", "-cf", tmp_path])
        run(["sudo", "install", "-o", "root", "-g", "root", "-m", "0440", tmp_path, target])
        run(["sudo", "-n", "true"])
    finally:
        Path(tmp_path).unlink(missing_ok=True)


def validate_codex_config(home: Path, dry_run: bool) -> None:
    codex = shutil.which("codex")
    if not codex:
        print("codex command not found; skipping strict config validation.")
        return

    env = os.environ.copy()
    env["HOME"] = str(home)
    run([codex, "exec", "--strict-config", "--version"], dry_run=dry_run, check=False, env=env)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(line_buffering=True)

    parser = argparse.ArgumentParser(description="Configure a dedicated Codex host for high-autonomy local operation.")
    parser.add_argument("--home", default=str(Path.home()), help="Home directory to configure.")
    parser.add_argument("--workspace", default=None, help="Workspace path to mark trusted. Defaults to --home.")
    parser.add_argument("--sudo-user", default=None, help="User for the optional sudoers drop-in. Defaults to current user.")
    parser.add_argument("--dedicated-host", action="store_true", help="Acknowledge this is a dedicated Codex-managed host.")
    parser.add_argument("--enable-passwordless-sudo", action="store_true", help="Install a NOPASSWD sudoers drop-in.")
    parser.add_argument("--yes", action="store_true", help="Do not ask for confirmation.")
    parser.add_argument("--dry-run", action="store_true", help="Print planned changes without writing files.")
    args = parser.parse_args()

    if not args.dedicated_host:
        print("Refusing to continue without --dedicated-host.", file=sys.stderr)
        return 2

    if args.enable_passwordless_sudo and not args.yes and not args.dry_run:
        answer = input("Install passwordless sudo on a dedicated Codex host? Type 'yes': ")
        if answer != "yes":
            print("Aborted.", file=sys.stderr)
            return 3

    home = Path(args.home).expanduser().resolve()
    workspace = Path(args.workspace).expanduser().resolve() if args.workspace else home
    sudo_user = args.sudo_user or getpass.getuser()

    if not args.dry_run and not home.exists():
        print(f"Home directory does not exist: {home}", file=sys.stderr)
        return 2

    update_codex_config(home, workspace, args.dry_run)
    update_durable_notes(home, args.dry_run)

    if args.enable_passwordless_sudo:
        install_passwordless_sudo(sudo_user, args.dry_run)

    validate_codex_config(home, args.dry_run)
    print("Restart Codex or start a new session so sandbox and approval defaults take effect.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
