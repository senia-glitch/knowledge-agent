"""Read-only pre-push check. Never prints discovered secret values."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BLOCKED_PARTS = {"storage", "backups", ".cache", ".secrets", ".docker", ".venv", "venv"}
SECRET_NAME = re.compile(r"(?:KEY|TOKEN|SECRET|PASSWORD|SALT)$", re.I)
TOKEN_PATTERNS = (
    re.compile(rb"(?:sk|sk-proj|sk-svcacct)-[A-Za-z0-9_-]{20,}"),
    re.compile(rb"gh[pousr]_[A-Za-z0-9]{30,}"),
    re.compile(rb"github_pat_[A-Za-z0-9_]{30,}"),
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
)


def git(*args: str) -> bytes:
    return subprocess.run(
        ["git", "-c", f"safe.directory={ROOT.as_posix()}", *args],
        cwd=ROOT, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout


def forbidden_path(name: str) -> bool:
    parts = Path(name).parts
    base = Path(name).name
    env_file = (base in {".env", ".core-package.env", ".infra.env"} or base.startswith(".env.")) and not base.endswith(".example")
    return bool(BLOCKED_PARTS.intersection(parts)) or env_file or base.endswith((".log", ".p12", ".pfx"))


def local_secrets(root: Path = ROOT) -> set[bytes]:
    secrets: set[bytes] = set()
    for candidate in (root / ".env", root / "storage" / ".env", root / ".core-package.env", root / ".infra.env"):
        if not candidate.is_file():
            continue
        for line in candidate.read_text(encoding="utf-8-sig").splitlines():
            name, sep, value = line.strip().partition("=")
            if not sep or not SECRET_NAME.search(name):
                continue
            value = value.strip().strip("\"'")
            if len(value) >= 12:
                secrets.add(value.encode())
    secret_directory = root / ".secrets"
    if secret_directory.is_dir():
        for candidate in secret_directory.rglob("*"):
            if candidate.is_file() and not candidate.is_symlink() and candidate.stat().st_size <= 16384:
                value = candidate.read_bytes().strip()
                if len(value) >= 12:
                    secrets.add(value)
    return secrets


def contains_secret(data: bytes, known: set[bytes]) -> bool:
    return any(secret in data for secret in known) or any(pattern.search(data) for pattern in TOKEN_PATTERNS)


def scan(history: bool) -> dict:
    known = local_secrets()
    failures: set[str] = set()
    checked_blobs: set[str] = set()
    names = git("ls-files", "-z").decode().split("\0")
    for name in filter(None, names):
        if forbidden_path(name):
            failures.add("runtime-path:" + name)
        path = ROOT / name
        if path.is_file() and contains_secret(path.read_bytes(), known):
            failures.add("worktree:" + name)
        if contains_secret(git("show", ":" + name), known):
            failures.add("index:" + name)
    if history:
        for entry in git("rev-list", "--objects", "--all").decode().splitlines():
            oid, _, name = entry.partition(" ")
            if not name or git("cat-file", "-t", oid).strip() != b"blob":
                continue
            if forbidden_path(name):
                failures.add("history-runtime-path:" + name)
            if oid not in checked_blobs:
                if contains_secret(git("cat-file", "blob", oid), known):
                    failures.add("history-content:" + name)
                checked_blobs.add(oid)
    return {
        "passed": not failures,
        "checkedTrackedFiles": len(list(filter(None, names))),
        "checkedHistoryBlobs": len(checked_blobs),
        "knownLocalSecretCount": len(known),
        "failures": sorted(failures),
    }


def self_test() -> None:
    marker = b"synthetic-" + b"private-value-for-test-only"
    assert contains_secret(b"prefix " + marker, {marker})
    assert not contains_secret(b"ordinary text", {marker})
    assert contains_secret(b"sk-" + b"a" * 32, set())
    for name in (".env", ".env.local", ".core-package.env", ".infra.env", "storage/data.json", ".secrets/service-key", "backups/copy.env"):
        assert forbidden_path(name), name
    for name in (".env.example", "docs/ARCHITECTURE.md", "scripts/check-secrets.py"):
        assert not forbidden_path(name), name


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--history", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        print(json.dumps({"selfTest": "passed"}))
    try:
        result = scan(args.history)
    except (OSError, UnicodeError, subprocess.CalledProcessError):
        print(json.dumps({"passed": False, "error": "Cannot complete Git/secret inspection; push must stop."}))
        raise SystemExit(2)
    print(json.dumps(result, ensure_ascii=False))
    raise SystemExit(0 if result["passed"] else 1)
