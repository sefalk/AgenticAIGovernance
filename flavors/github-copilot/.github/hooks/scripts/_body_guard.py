"""GitHub body and comment shrink guard (#376): the #197 field guard for issues, pull requests and comments.

``issue_write update``, ``update_pull_request`` and ``update_issue_comment``
replace the text; none of them patches. ``record_body`` (PostToolUse, via
scan-secrets.py) caches per session what a read returned -- every object with a
``body`` and a github.com ``html_url`` -- and what a successful write stored.
``check_body`` (PreToolUse, via work-item-owner.py) judges a write against it:

- ``body`` and ``state`` in one call -> deny (it has overwritten a description);
- a target this session never read -> deny;
- a read older than ``WI_FIELD_READ_MAX_AGE_MIN`` -> deny; GitHub offers no
  ``If-Match`` on writes, so recency is the only concurrency check left;
- a shrink or a lost heading -> ``WI_FIELD_SHRINK_POLICY``. A declaration is a
  preceding comment ``af-shrink: body|comment <id>; remove: <heading>, ...;
  expect: <length>``, checked against the diff, and ignored once a verdict has
  named the loss for that text.

Issue and PR text from the last ``## Working state`` heading on is not guarded:
work-item-state sanctions that block as the one place a body may be replaced.
Reads are taken as verbatim, which holds from github-mcp-server 1.12.0 on.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import time

from _field_guard import (
    _DECLARATION,
    EXPECT_TOLERANCE,
    POLICIES,
    _cache_path,
    _config,
    _int,
    _load,
    _norm,
    _save,
    _tool_input,
    _verdict,
    headings,
)

READ_SUFFIXES = (
    "issue_read",
    "pull_request_read",
    "list_issues",
    "search_issues",
    "list_pull_requests",
    "search_pull_requests",
)
WRITE_SUFFIXES = ("issue_write", "update_pull_request", "update_issue_comment", "create_pull_request")
JUDGED = ("issue_write", "update_pull_request", "update_issue_comment")

_URL = re.compile(r"^https://github\.com/([^/\s]+)/([^/\s]+)/(?:issues|pull)/(\d+)(?:#issuecomment-(\d+))?$")
_WORKING_STATE = re.compile(r"^##\s+Working state\s*$", re.MULTILINE | re.IGNORECASE)


def _now() -> float:
    # Tests age a read without sleeping; only a positive skew is honoured, so it can never freshen one.
    try:
        skew = max(0, int(os.environ.get("AF_FIELD_CLOCK_SKEW_SECONDS") or 0))
    except ValueError:
        skew = 0
    return time.time() + skew


def _gh_kind(tool: str) -> str:
    if tool.endswith("sub_issue_write"):
        return ""
    for suffix in (*WRITE_SUFFIXES, "add_issue_comment"):
        if tool.endswith(suffix):
            return suffix
    return "read" if tool.endswith(READ_SUFFIXES) else ""


def _key(owner: object, repo: object, number: object = None, comment: object = None) -> str:
    target = f"c{comment}" if comment else str(number)
    return f"{owner}/{repo}#{target}".lower()


def _guarded(text: str, is_comment: bool) -> str:
    if is_comment:
        return text
    marks = list(_WORKING_STATE.finditer(text))
    return text[: marks[-1].start()] if marks else text


def _snapshot(text: str, is_comment: bool, old: dict[str, object] | None) -> dict[str, object]:
    guarded = _guarded(text, is_comment)
    marks = old.get("marks") if old and isinstance(old.get("marks"), list) else []
    return {
        "len": len(guarded),
        "headings": headings(guarded),
        "hash": hashlib.sha256(guarded.encode("utf-8")).hexdigest()[:16],
        "at": _now(),
        "marks": marks,
    }


def _parse(response: object) -> object:
    if not isinstance(response, str):
        return response
    try:
        return json.loads(response)
    except ValueError:
        return None


def _objects(node: object):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _objects(value)
    elif isinstance(node, list):
        for value in node:
            yield from _objects(value)


def _url_key(url: object) -> tuple[str, bool] | None:
    match = _URL.match(str(url or ""))
    if not match:
        return None
    owner, repo, number, comment = match.groups()
    return _key(owner, repo, number, comment), bool(comment)


def _write_target(kind: str, tool_input: dict[str, object], parsed: object) -> tuple[str, bool] | None:
    owner, repo = tool_input.get("owner"), tool_input.get("repo")
    if kind == "update_issue_comment" and tool_input.get("comment_id"):
        return _key(owner, repo, comment=tool_input["comment_id"]), True
    if kind == "update_pull_request" and tool_input.get("pullNumber"):
        return _key(owner, repo, tool_input["pullNumber"]), False
    if kind == "issue_write" and str(tool_input.get("method") or "").lower() == "update":
        return _key(owner, repo, tool_input.get("issue_number")), False
    if isinstance(parsed, dict):
        return _url_key(parsed.get("url") or parsed.get("html_url"))
    return None


# -- PostToolUse: record what was read or written --------------------------------


def record_body(payload: dict[str, object]) -> None:
    """Cache length, headings and hash of every GitHub body a read returned or a write stored."""
    kind = _gh_kind(str(payload.get("tool_name") or ""))
    if not kind:
        return
    parsed = _parse(payload.get("tool_response"))
    if parsed is None:
        return
    tool_input = _tool_input(payload)
    path = _cache_path(str(payload.get("session_id") or ""))
    cache = _load(path)
    gh = cache.setdefault("gh", {})
    items = gh.setdefault("items", {})
    decls = gh.setdefault("decls", [])

    if kind == "read":
        for obj in _objects(parsed):
            target = _url_key(obj.get("html_url"))
            if target and isinstance(obj.get("body"), str):
                items[target[0]] = _snapshot(obj["body"], target[1], items.get(target[0]))
        _save(path, cache)
        return

    # An error comes back as plain text; only a JSON object with an identity is a write that landed.
    if not (isinstance(parsed, dict) and any(k in parsed for k in ("id", "url", "html_url", "number"))):
        return
    body = tool_input.get("body")
    if kind == "add_issue_comment":
        for match in _DECLARATION.finditer(body if isinstance(body, str) else ""):
            subject = match.group(1).strip().lower()
            owner, repo = tool_input.get("owner"), tool_input.get("repo")
            if subject == "body":
                key = _key(owner, repo, tool_input.get("issue_number"))
            elif subject.startswith("comment") and re.search(r"\d+", subject):
                key = _key(owner, repo, comment=re.search(r"\d+", subject).group(0))
            else:
                continue
            removed = sorted({_norm(h) for h in match.group(2).split(",") if _norm(h)})
            decls.append({"key": key, "removed": removed, "expect": int(match.group(3))})
        _save(path, cache)
        return
    target = _write_target(kind, tool_input, parsed)
    if target and isinstance(body, str):
        items[target[0]] = _snapshot(body, target[1], items.get(target[0]))
        gh["decls"] = [d for d in decls if d.get("key") != target[0]]
        _save(path, cache)


# -- PreToolUse: judge a write ----------------------------------------------------


def check_body(payload: dict[str, object], conf_path: str) -> dict[str, object] | None:
    """PreToolUse verdict for a GitHub body or comment write, or None to defer."""
    kind = _gh_kind(str(payload.get("tool_name") or ""))
    if kind not in JUDGED:
        return None
    tool_input = _tool_input(payload)
    if kind == "issue_write" and str(tool_input.get("method") or "").lower() != "update":
        return None
    body = tool_input.get("body")
    if kind != "update_issue_comment" and isinstance(body, str) and tool_input.get("state") not in (None, ""):
        return _verdict(
            "deny",
            "Body guard (#376): this call sets the body and the state at once, which has silently replaced a "
            "description before. Post the closing note with add_issue_comment, then send the state change alone "
            "(state and state_reason, no body).",
        )
    target = _write_target(kind, tool_input, None)
    if not isinstance(body, str) or not target:
        return None
    key, is_comment = target

    conf = _config(conf_path)
    policy = conf["WI_FIELD_SHRINK_POLICY"].lower()
    policy = policy if policy in POLICIES else "ask"
    pct = _int(conf["WI_FIELD_SHRINK_PCT"], 10)
    chars = _int(conf["WI_FIELD_SHRINK_CHARS"], 200)
    min_chars = _int(conf["WI_FIELD_GUARD_MIN_CHARS"], 500)
    max_age = _int(conf["WI_FIELD_READ_MAX_AGE_MIN"], 10)

    path = _cache_path(str(payload.get("session_id") or ""))
    cache = _load(path)
    gh = cache.get("gh") if isinstance(cache.get("gh"), dict) else {}
    items = gh.get("items") if isinstance(gh.get("items"), dict) else {}
    entry = items.get(key)
    what = f"comment {key.rsplit('#c', 1)[-1]}" if is_comment else f"the body of {key}"
    if not isinstance(entry, dict):
        source = "issue_read method=get_comments" if is_comment else "issue_read or pull_request_read method=get"
        return _verdict(
            "deny",
            f"Body guard (#376): {what} was not read in this session, so this write cannot be compared with the "
            f"text it replaces. Read it first ({source}) and build the new text from what you read.",
        )
    age = _now() - float(entry.get("at", 0) or 0)
    if age > max_age * 60:
        return _verdict(
            "deny",
            f"Body guard (#376): this session last read {what} {int(age // 60)} min ago, longer than "
            f"WI_FIELD_READ_MAX_AGE_MIN={max_age}. GitHub cannot reject a write over a stale copy, so re-read it "
            "and rebuild the text from what you read.",
        )

    old_len = int(entry.get("len", 0) or 0)
    if old_len <= min_chars:
        return None
    new_text = _guarded(body, is_comment)
    kept = {_norm(h) for h in headings(new_text)}
    lost = [h for h in entry.get("headings", []) if _norm(h) not in kept]
    drop = old_len - len(new_text)
    if not (lost or (drop > chars and drop * 100 / old_len > pct)):
        return None

    marks = entry.get("marks") if isinstance(entry.get("marks"), list) else []
    mark = str(entry.get("hash"))
    lost_set = {_norm(h) for h in lost}
    decls = gh.get("decls") if isinstance(gh.get("decls"), list) else []
    declared = mark not in marks and any(
        isinstance(d, dict)
        and d.get("key") == key
        and set(d.get("removed", [])) == lost_set
        and abs(len(body) - int(d.get("expect", -1))) <= EXPECT_TOLERANCE * max(int(d.get("expect", 1)), 1)
        for d in decls
    )
    if policy == "deny":
        decision = "deny"
    elif declared and policy in ("declared", "declared-strict"):
        return None
    elif policy == "declared-strict":
        decision = "deny"
    else:
        decision = "ask"
    # The reason names the loss; a declaration copied from it must not count until the text changes.
    if mark not in marks:
        entry["marks"] = [*marks, mark]
        _save(path, cache)

    change = f"-{round(drop * 100 / old_len)} %" if drop > 0 else "length kept"
    finding = f"{what}: {old_len} -> {len(new_text)} guarded chars ({change})"
    if lost:
        finding += f", headings dropped: {', '.join(lost)}"
    finding += " [declared, and the diff matches]" if declared else ""
    lead = "refused" if decision == "deny" else "needs confirmation"
    return _verdict(
        decision,
        f"Body guard (#376) -- this write shrinks long text and {lead} (WI_FIELD_SHRINK_POLICY={policy}): "
        f"{finding}. Confirm only if that loss is intended; otherwise re-read and rebuild the text from what "
        "you read, changing only what was asked.",
    )
