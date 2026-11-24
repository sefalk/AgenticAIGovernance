#!/usr/bin/env python3
"""Check at session start that ``AF_GH_TOKEN`` still works (#563).

Renewing a fine-grained PAT issues a new value; the old one is rejected at
once. Readiness used to check only that a token variable existed, so the
``af-github`` MCP server failed mid-workflow with no earlier signal.

One ``GET /user`` -- no model call, no write -- answers three questions: is the
token accepted, whose is it, and when does it expire (GitHub returns the
``github-authentication-token-expiration`` header for expiring tokens).

Usage::

    python _gh_token_check.py --root <project root>

Prints at most one line and always exits 0: readiness reports, it never
blocks a session. A line that needs action starts with ``WARNING``. The token
value is never printed. ``AF_GH_API_URL`` overrides the API base (tests,
GitHub Enterprise Server).
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

VAR = "AF_GH_TOKEN"
TOKEN_LABEL = f"GitHub token ({VAR})"
WARN_DAYS = 14
TIMEOUT_SECONDS = 4.0
CONSUMERS = (".mcp.json", ".vscode/mcp.json")


def _consumer(root: Path) -> str | None:
    for rel in CONSUMERS:
        path = root / rel
        try:
            if VAR in path.read_text(encoding="utf-8", errors="replace"):
                return rel
        except OSError:
            continue
    return None


def _expiry(header: str | None) -> datetime.date | None:
    if not header:
        return None
    try:
        return datetime.date.fromisoformat(header.strip()[:10])
    except ValueError:
        return None


def check_token(token: str, api_url: str, root: Path, today: datetime.date) -> str:
    """Return the readiness line for the token, or an empty string.

    Parameters
    ----------
    token : str
        The value of ``AF_GH_TOKEN``; empty when unset.
    api_url : str
        The REST API base, without a trailing ``/user``.
    root : Path
        Project root, searched for an MCP config that consumes the token.
    today : datetime.date
        Reference date for the expiry countdown.

    Returns
    -------
    str
        One line, prefixed ``WARNING`` when action is needed; empty when no
        token is set and nothing consumes one.
    """
    if not token:
        consumer = _consumer(root)
        if consumer is None:
            return ""
        return (
            f"WARNING: {VAR} is not set, but {consumer} uses it -- the af-github MCP server will fail to authenticate"
        )

    request = urllib.request.Request(
        api_url.rstrip("/") + "/user",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "af-session-readiness",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            body = json.loads(response.read().decode("utf-8") or "{}")
            expires = _expiry(response.headers.get("github-authentication-token-expiration"))
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            return (
                f"WARNING: {TOKEN_LABEL} was rejected (HTTP 401) -- af-github MCP and REST "
                f"calls will fail. A renewed PAT has a new value; update {VAR}"
            )
        return f"{TOKEN_LABEL}: not verified (HTTP {exc.code})"
    except (OSError, ValueError) as exc:
        return f"{TOKEN_LABEL}: not verified ({exc.__class__.__name__})"

    login = body.get("login", "unknown") if isinstance(body, dict) else "unknown"
    if expires is None:
        return f"{TOKEN_LABEL}: valid | login={login} | expires=not reported"
    days = (expires - today).days
    when = f"{expires.isoformat()} (in {days} days)"
    if days < WARN_DAYS:
        return f"WARNING: {TOKEN_LABEL} expires {when} | login={login} -- renew it and update {VAR}"
    return f"{TOKEN_LABEL}: valid | login={login} | expires={when}"


def main(argv: list[str]) -> int:
    """Print the readiness line; see the module docstring."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    args = parser.parse_args(argv)
    line = check_token(
        os.environ.get(VAR, ""),
        os.environ.get("AF_GH_API_URL") or "https://api.github.com",
        Path(args.root),
        datetime.date.today(),
    )
    if line:
        sys.stdout.write(line + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
