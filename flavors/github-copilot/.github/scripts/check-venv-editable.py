"""Report editable installs that point into a foreign checkout (#579).

Run with the interpreter of the venv to inspect. A worktree in
WORKTREE_VENV_MODE=shared borrows the main checkout's venv; if that venv holds
an editable install of the main checkout, pytest in the worktree imports the
main checkout's code and passes or fails on code nobody changed. This lists
every distribution installed editable from a path inside ``--foreign-root``
that is not also inside ``--workspace`` (a worktree may live inside the main
checkout).

Exit codes: 0 none found, 3 found, 2 usage error.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from importlib import metadata
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import url2pathname


def _norm(path: str | Path) -> str:
    return os.path.normcase(os.path.realpath(str(path)))


def _inside(path: str, root: str) -> bool:
    try:
        return os.path.commonpath([path, root]) == root
    except ValueError:
        return False


def _editable_sources() -> list[tuple[str, str]]:
    """Return ``(name, source path)`` for every editable install in this interpreter.

    Returns
    -------
    list[tuple[str, str]]
        PEP 610 ``direct_url.json`` installs and legacy ``*.egg-link`` files.
    """
    found: list[tuple[str, str]] = []
    for dist in metadata.distributions():
        raw = dist.read_text("direct_url.json")
        if not raw:
            continue
        try:
            data = json.loads(raw)
        except ValueError:
            continue
        if not data.get("dir_info", {}).get("editable"):
            continue
        url = urlparse(data.get("url", ""))
        if url.scheme == "file":
            found.append((dist.metadata["Name"] or "?", url2pathname(url.path)))
    for entry in sys.path:
        if not entry or not os.path.isdir(entry):
            continue
        for link in Path(entry).glob("*.egg-link"):
            lines = link.read_text(encoding="utf-8", errors="replace").splitlines()
            if lines and lines[0].strip():
                found.append((link.stem, lines[0].strip()))
    return found


def main(argv: list[str] | None = None) -> int:
    """Print foreign editable installs and return the exit code.

    Parameters
    ----------
    argv : list[str] | None
        Command-line arguments; ``sys.argv[1:]`` when None.

    Returns
    -------
    int
        0 when none is found, 3 when at least one is.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--foreign-root", required=True, help="checkout the venv belongs to")
    parser.add_argument("--workspace", required=True, help="checkout the runner works in")
    args = parser.parse_args(argv)

    foreign = _norm(args.foreign_root)
    workspace = _norm(args.workspace)
    hits = [
        (name, source)
        for name, source in _editable_sources()
        if _inside(_norm(source), foreign) and not _inside(_norm(source), workspace)
    ]
    for name, source in hits:
        print(f"editable install from the main checkout: {name} -> {source}")
    return 3 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
