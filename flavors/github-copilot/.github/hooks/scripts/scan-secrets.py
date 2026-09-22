#!/usr/bin/env python3
"""PostToolUse gate: scan edited files for hardcoded secrets.

This is the single implementation. `scan-secrets.ps1` and `scan-secrets.sh`
are wrappers that resolve an interpreter and hand stdin over -- the reference
migration for issue #287.

It exists because the two shells had silently stopped agreeing. Measured on
2026-09-22, the twins disagreed on three of four payloads, in both directions:
the Bash side had neither the connection-string rule nor the ``apikey`` alias,
and the PowerShell side filtered by an extension allowlist that excluded
``.conf``, so a key in a config file walked past it. Converging on the union
of the two is deliberate: the alternative is to keep whichever hole happens to
be on the platform you are standing on.

Reads a PostToolUse payload on stdin, writes one verdict object to stdout.
Exit 1 blocks the call (HARD gate); exit 0 allows it.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

# Both sit next to this file; Python puts a script's own directory on
# sys.path[0], which is how every hook here is invoked.
from _agentlog import PATH_KEYS
from _provenance import DETAIL as PROVENANCE_DETAIL
from _provenance import has_provenance_marker

# Kept in step with Test-AfWriteTool / af_is_write_tool in _common.*. Those
# stay until their remaining callers migrate; this list is the Python side of
# the same question, not a second policy.
WRITE_TOOLS = {
    "create_file",
    "replace_string_in_file",
    "multi_replace_string_in_file",
    "insert_edit_into_file",
    "apply_patch",
    "create_directory",
    "edit_notebook_file",
    "create_new_jupyter_notebook",
    "editFiles",
    "editFile",
    "createFile",
    "createDirectory",
    "createDir",
    "editNotebook",
    "writeFile",
    "applyPatch",
    "insertEdit",
}

_WRITE_VERB = re.compile(r"create|write|edit|insert|apply|replace")
_WRITE_NOUN = re.compile(r"file|notebook|dir")

SECRET_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("AWS Key", re.compile(r"AKIA[0-9A-Z]{16}")),
    (
        "Generic Secret",
        re.compile(r"(?i)(password|secret|token|api_key|apikey)\s*[:=]\s*[\"'][^\s\"']{8,}"),
    ),
    # Looser than the PowerShell twin's `(RSA |EC |DSA )?`: the Bash twin
    # matched any BEGIN...PRIVATE KEY line, and a key type nobody enumerated
    # is still a key.
    ("Private Key", re.compile(r"-----BEGIN[^\n]*PRIVATE KEY-----")),
    ("Connection String", re.compile(r"(?i)(Server|Data Source)=.+;(User Id|Password)=")),
]


def is_write_tool(name: str) -> bool:
    """Whether a tool call modifies files or directories in the workspace."""
    if not name:
        return False
    if name in WRITE_TOOLS:
        return True
    # An exact list cannot recognise a tool that does not exist yet, and a gate
    # that has never heard of a tool fails open. A writing verb plus a file
    # noun is enough to take the call seriously; `read_file` carries no verb
    # and `create_and_run_task` carries no file noun.
    return bool(_WRITE_VERB.search(name) and _WRITE_NOUN.search(name))


def write_paths(tool_input: object) -> list[str]:
    """Every workspace path a write-tool payload refers to, in payload order."""
    if not isinstance(tool_input, dict):
        return []

    # Payload order, so a batched edit always reports the same file first.
    found: list[str] = []
    for key, value in tool_input.items():
        if key in PATH_KEYS and isinstance(value, str) and value:
            found.append(value)

    # multi_replace_string_in_file keeps no path at the top level -- its paths
    # sit one level down, the shape that made an earlier gate inert in #64.
    replacements = tool_input.get("replacements")
    if isinstance(replacements, list):
        for item in replacements:
            if isinstance(item, dict):
                value = item.get("filePath")
                if isinstance(value, str) and value:
                    found.append(value)

    seen: set[str] = set()
    return [p for p in found if not (p in seen or seen.add(p))]


def read_text(path: str) -> str | None:
    """File contents, or None when the file is binary or unreadable."""
    try:
        with open(path, "rb") as fh:
            head = fh.read(8192)
            if b"\x00" in head:
                return None
            return (head + fh.read()).decode("utf-8", errors="replace")
    except OSError:
        return None


def gitleaks_verdict(path: str) -> dict[str, str] | None:
    """A FAIL verdict when gitleaks reports a finding, else None."""
    try:
        proc = subprocess.run(
            ["gitleaks", "detect", "--no-git", "--source", path, "--no-color"],
            capture_output=True,
            text=True,
            timeout=60,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode == 0:
        return None
    return {
        "gate": "secret-scan",
        "status": "FAIL",
        "tool": "gitleaks",
        "file": path,
        "detail": (proc.stdout + proc.stderr).strip(),
    }


def emit(verdict: dict[str, str] | None, code: int) -> int:
    print(json.dumps(verdict if verdict else {}, separators=(",", ":")))
    return code


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read())
    except (ValueError, OSError):
        return emit(None, 0)
    if not isinstance(payload, dict):
        return emit(None, 0)

    if not is_write_tool(str(payload.get("tool_name") or "")):
        return emit(None, 0)

    paths = [p for p in write_paths(payload.get("tool_input")) if os.path.isfile(p)]
    if not paths:
        return emit(None, 0)

    has_gitleaks = shutil.which("gitleaks") is not None

    # A batched edit touches several files in one call. A secret anywhere in
    # the batch outranks a missing marker and only one verdict can be emitted,
    # so the advisory is held back until every file has been read.
    advisory: dict[str, str] | None = None

    for path in paths:
        if has_gitleaks:
            verdict = gitleaks_verdict(path)
            if verdict:
                return emit(verdict, 1)
            continue

        content = read_text(path)
        if content is None:
            continue

        findings = [name for name, pattern in SECRET_PATTERNS if pattern.search(content)]
        if findings:
            return emit(
                {
                    "gate": "secret-scan",
                    "status": "FAIL",
                    "tool": "regex-fallback",
                    "file": path,
                    "patterns": ", ".join(findings),
                },
                1,
            )

        if advisory is None and path.endswith(".py") and not has_provenance_marker(content):
            advisory = {
                "gate": "provenance-check",
                "status": "WARN",
                "file": path,
                "detail": PROVENANCE_DETAIL,
            }

    return emit(advisory, 0)


if __name__ == "__main__":
    sys.exit(main())
