"""Pre-commit guard: reject a staged ``tasks.json`` that is not strict JSON.

Invoked by the ``.github/hooks/git/pre-commit`` shim on every ``git commit``.

VS Code accepts JSONC (comments, trailing commas) in ``.vscode/tasks.json``,
but the ``createAndRunTask`` agent tool does not -- a single ``//`` line
silently disables the documented fallback execution path for agents that have
no terminal access. The file therefore has to stay parseable as strict JSON.
See ``.github/instructions/tooling.instructions.md``.

Exit codes: 0 pass, 1 blocked, 2 internal error.
"""
from __future__ import annotations

import json
import os
import posixpath
import subprocess
import sys

# Files that must remain strict JSON, matched on the repo-relative path.
GUARDED_BASENAMES = {"tasks.json"}
GUARDED_PARENT = ".vscode"


def _staged_files() -> list[str]:
    result = subprocess.run(
        ["git", "-c", "core.quotePath=false", "diff", "--cached", "-z",
         "--name-only", "--diff-filter=ACMR"],
        capture_output=True, text=True, encoding="utf-8", check=True,
    )
    return [entry for entry in result.stdout.split("\0") if entry]


def _is_guarded(path: str) -> bool:
    return (
        posixpath.basename(path) in GUARDED_BASENAMES
        and posixpath.basename(posixpath.dirname(path)) == GUARDED_PARENT
    )


def _staged_blob_text(path: str) -> str | None:
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
    cat_result = subprocess.run(
        ["git", "cat-file", "blob", parts[1]],
        capture_output=True, text=True, encoding="utf-8", check=True,
    )
    return cat_result.stdout


def main() -> int:
    if os.environ.get("ALLOW_JSONC", "").strip().lower() in {"1", "true", "yes"}:
        print("[strict-json-guard] ALLOW_JSONC override set -- skipping check.")
        return 0
    try:
        offenders: list[tuple[str, str]] = []
        for path in _staged_files():
            if not _is_guarded(path):
                continue
            text = _staged_blob_text(path)
            if text is None:
                continue
            try:
                json.loads(text)
            except json.JSONDecodeError as exc:
                offenders.append((path, f"line {exc.lineno}, column {exc.colno}: {exc.msg}"))
    except subprocess.CalledProcessError as exc:
        print(f"[strict-json-guard] ERROR: git command failed: {exc}", file=sys.stderr)
        return 2
    if not offenders:
        return 0
    print("[strict-json-guard] COMMIT BLOCKED -- staged file(s) are not strict JSON:")
    for path, detail in offenders:
        print(f"  - {path}: {detail}")
    print()
    print("Why: the createAndRunTask agent tool cannot parse JSONC. Comments or")
    print("trailing commas in tasks.json disable the fallback execution path for")
    print("agents without terminal access.")
    print()
    print("To fix:")
    print("  - Move per-task explanation into the task's `detail` field.")
    print("  - Move cross-cutting rules into .github/instructions/tooling.instructions.md.")
    print("  - Remove trailing commas.")
    print("  - One-off override for this commit: ALLOW_JSONC=1 git commit ...")
    return 1


if __name__ == "__main__":
    sys.exit(main())
