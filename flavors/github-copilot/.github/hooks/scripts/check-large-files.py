"""Pre-commit guard: reject staged files exceeding a configurable size threshold.

Invoked by the ``.github/hooks/git/pre-commit`` shim on every ``git commit``.
Blocks accidental commits of oversized files (e.g. self-contained Plotly HTML
exports, ~4.8 MB) while allowing deliberate large files via an allowlist
in ``.github/af-env.conf`` or a one-off ``ALLOW_LARGE_FILES=1`` override.

Exit codes: 0 pass, 1 blocked, 2 internal error.
"""
from __future__ import annotations

import fnmatch
import os
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_MAX_BYTES = 1_048_576  # 1 MB


def _repo_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, encoding="utf-8", check=True,
    )
    return Path(result.stdout.strip())


def _read_conf(conf_path: Path) -> tuple[int, list[str]]:
    max_bytes = DEFAULT_MAX_BYTES
    allowlist: list[str] = []
    if not conf_path.is_file():
        return max_bytes, allowlist
    text = conf_path.read_text(encoding="utf-8")
    size_match = re.search(r"^LARGE_FILE_MAX_BYTES=(.+)$", text, re.MULTILINE)
    if size_match:
        value = size_match.group(1).strip()
        if value.isdigit():
            max_bytes = int(value)
    allow_match = re.search(r"^LARGE_FILE_ALLOWLIST=(.*)$", text, re.MULTILINE)
    if allow_match:
        value = allow_match.group(1).strip()
        if value:
            allowlist = [p.strip() for p in value.split(",") if p.strip()]
    return max_bytes, allowlist


def _staged_files() -> list[str]:
    result = subprocess.run(
        ["git", "-c", "core.quotePath=false", "diff", "--cached", "-z",
         "--name-only", "--diff-filter=ACMR"],
        capture_output=True, text=True, encoding="utf-8", check=True,
    )
    return [entry for entry in result.stdout.split("\0") if entry]


def _staged_blob_size(path: str) -> int | None:
    ls_result = subprocess.run(
        ["git", "ls-files", "-s", "--", f":(literal){path}"],
        capture_output=True, text=True, encoding="utf-8", check=True,
    )
    line = ls_result.stdout.strip()
    if not line:
        return None
    parts = line.split()  # "<mode> <blob-sha> <stage>\t<path>"
    if len(parts) < 2:
        return None
    blob_sha = parts[1]
    cat_result = subprocess.run(
        ["git", "cat-file", "-s", blob_sha],
        capture_output=True, text=True, encoding="utf-8", check=True,
    )
    size_text = cat_result.stdout.strip()
    return int(size_text) if size_text.isdigit() else None


def _is_allowlisted(path: str, allowlist: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in allowlist)


def main() -> int:
    if os.environ.get("ALLOW_LARGE_FILES", "").strip().lower() in {"1", "true", "yes"}:
        print("[large-file-guard] ALLOW_LARGE_FILES override set -- skipping check.")
        return 0
    try:
        root = _repo_root()
        max_bytes, allowlist = _read_conf(root / ".github" / "af-env.conf")
        staged = _staged_files()
        offenders: list[tuple[str, int]] = []
        for path in staged:
            if _is_allowlisted(path, allowlist):
                continue
            size = _staged_blob_size(path)
            if size is not None and size > max_bytes:
                offenders.append((path, size))
    except subprocess.CalledProcessError as exc:
        print(f"[large-file-guard] ERROR: git command failed: {exc}", file=sys.stderr)
        return 2
    if not offenders:
        return 0
    threshold_mb = max_bytes / (1024 * 1024)
    print("[large-file-guard] COMMIT BLOCKED -- oversized file(s) staged:")
    for path, size in offenders:
        print(f"  - {path}: {size / (1024 * 1024):.2f} MB (limit {threshold_mb:.2f} MB)")
    print()
    print("To fix:")
    print("  - Reduce the file size (e.g. export Plotly HTML in CDN mode, not self-contained).")
    print("  - One-off override for this commit: ALLOW_LARGE_FILES=1 git commit ...")
    print("  - Deliberate large file: add a glob to LARGE_FILE_ALLOWLIST in .github/af-env.conf")
    print("  - Large binary asset to version: track it with Git LFS so only a pointer is")
    print('    committed -- `git lfs track "<pattern>"`, then commit .gitattributes + the file.')
    return 1


if __name__ == "__main__":
    sys.exit(main())
