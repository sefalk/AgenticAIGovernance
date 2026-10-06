"""Work-item field shrink guard (#197): judge an update against what MCP actually returned.

An agent rewrote a 5,447-character description from memory, lost 35 % of it and
reported "+300 chars, preserved verbatim". The check that should have caught it
was the agent's own. This one belongs to the hooks:

``record`` (PostToolUse, via scan-secrets.py) caches, per session and work item,
the revision and per field the length and headings of what a read -- or a
write's own response -- returned.

``check`` (PreToolUse, via work-item-owner.py) judges an ``update`` or
``update_batch`` against that cache:

- a guarded field the session never read -> deny, read it first;
- no ``test /rev`` op, or one that disagrees with the read -> deny;
- a shrink (over PCT % and over CHARS) or a lost heading -> the
  ``WI_FIELD_SHRINK_POLICY`` verdict. A declaration in ``System.History``,
  ``af-shrink: <field>; remove: <heading>, ...; expect: <length>``, counts only
  when the diff confirms it exactly, and never after a verdict was given for the
  same field and revision -- the verdict names the loss, so a later declaration
  could simply be copied from it.
"""

from __future__ import annotations

import json
import os
import re
import tempfile
import time
from pathlib import Path

POLICIES = ("ask", "declared", "declared-strict", "deny")
DEFAULTS = {
    "WI_FIELD_SHRINK_POLICY": "ask",
    "WI_FIELD_SHRINK_PCT": "10",
    "WI_FIELD_SHRINK_CHARS": "200",
    "WI_FIELD_GUARD_MIN_CHARS": "500",
    "WI_FIELD_READ_MAX_AGE_MIN": "10",
}
EXPECT_TOLERANCE = 0.10
CACHE_TTL_SECONDS = 86400
# Fields that are long text by type; a field outside this set is guarded once
# its cached value is long or the new value looks like long text.
MULTILINE_FIELDS = {
    "system.description",
    "microsoft.vsts.common.acceptancecriteria",
    "microsoft.vsts.tcm.reprosteps",
    "microsoft.vsts.tcm.systeminfo",
    "microsoft.vsts.common.resolution",
}
UNJUDGED_FIELDS = {"system.history"}
READ_ACTIONS = {"get", "get_batch"}
WRITE_ACTIONS = {"update", "update_batch", "create"}

_ENVELOPE = re.compile(r"^\s*<<([0-9A-Fa-f]+)>>.*?<<\1>>\s*(.*?)\s*<</\1>>\s*$", re.DOTALL)
_MD_HEADING = re.compile(r"^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$", re.MULTILINE)
_HTML_HEADING = re.compile(r"<h[1-6][^>]*>(.*?)</h[1-6]>", re.IGNORECASE | re.DOTALL)
_TAG = re.compile(r"<[^>]+>")
_DECLARATION = re.compile(r"af-shrink:\s*([^;]+?)\s*;\s*remove:\s*([^;]*?)\s*;\s*expect:\s*(\d+)", re.IGNORECASE)


# -- shared ---------------------------------------------------------------------


def _norm(text: str) -> str:
    return " ".join(_TAG.sub(" ", text).split()).casefold()


def headings(text: str) -> list[str]:
    found = [m.group(1) for m in _MD_HEADING.finditer(text)] + [m.group(1) for m in _HTML_HEADING.finditer(text)]
    return [h for h in (" ".join(_TAG.sub(" ", h).split()) for h in found) if h]


def _cache_path(session: str) -> Path:
    root = Path(os.environ.get("AF_FIELD_CACHE_DIR") or Path(tempfile.gettempdir()) / "af-field-cache")
    root.mkdir(parents=True, exist_ok=True)
    now = time.time()
    for old in root.glob("*.json"):
        try:
            if now - old.stat().st_mtime > CACHE_TTL_SECONDS:
                old.unlink()
        except OSError:
            pass
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", session or "no-session")[:120]
    return root / f"{safe}.json"


def _load(path: Path) -> dict[str, object]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _save(path: Path, data: dict[str, object]) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data), encoding="utf-8")
    os.replace(tmp, path)


def _tool_input(payload: dict[str, object]) -> dict[str, object]:
    value = payload.get("tool_input")
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except ValueError:
            return {}
    return value if isinstance(value, dict) else {}


# -- PostToolUse: record what was read ------------------------------------------


def _unwrap(response: str) -> object:
    match = _ENVELOPE.match(response)
    body = match.group(2) if match else response
    try:
        return json.loads(body)
    except ValueError:
        return None


def _items(parsed: object) -> list[dict[str, object]]:
    if isinstance(parsed, dict) and isinstance(parsed.get("value"), list):
        parsed = parsed["value"]
    candidates = parsed if isinstance(parsed, list) else [parsed]
    return [
        c for c in candidates if isinstance(c, dict) and "id" in c and "rev" in c and isinstance(c.get("fields"), dict)
    ]


def record(payload: dict[str, object]) -> None:
    """Cache revision, field lengths and headings from a work-item read or write response."""
    tool = str(payload.get("tool_name") or "")
    action = str(_tool_input(payload).get("action") or "").lower()
    if not (
        (tool.endswith("wit_work_item") and action in READ_ACTIONS)
        or (tool.endswith("wit_work_item_write") and action in WRITE_ACTIONS)
    ):
        return
    response = payload.get("tool_response")
    items = _items(_unwrap(response)) if isinstance(response, str) else []
    if not items:
        return
    path = _cache_path(str(payload.get("session_id") or ""))
    cache = _load(path)
    entries = cache.setdefault("items", {})
    for item in items:
        try:
            key, rev = str(int(item["id"])), int(item["rev"])
        except (TypeError, ValueError):
            continue
        entry = entries.get(key) or {}
        if entry and int(entry.get("rev", -1)) > rev:
            continue
        if not entry or int(entry.get("rev", -1)) < rev:
            entry = {"rev": rev, "fields": {}, "marks": entry.get("marks", []) if entry else []}
        multiline = item.get("multilineFieldsFormat") if isinstance(item.get("multilineFieldsFormat"), dict) else {}
        for name, value in item["fields"].items():
            if isinstance(value, str):
                entry["fields"][name] = {"len": len(value), "headings": headings(value), "multiline": name in multiline}
        entries[key] = entry
    _save(path, cache)


# -- PreToolUse: judge an update -------------------------------------------------


def _config(conf_path: str) -> dict[str, str]:
    values = dict(DEFAULTS)
    if conf_path and os.path.isfile(conf_path):
        with open(conf_path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                key, sep, value = line.strip().partition("=")
                if sep and key in values and value.strip():
                    values[key] = value.strip()
    return values


def _int(value: str, default: int) -> int:
    try:
        return int(value)
    except ValueError:
        return default


def _updates_by_item(tool_input: dict[str, object]) -> dict[str, list[dict[str, object]]]:
    action = str(tool_input.get("action") or "").lower()
    grouped: dict[str, list[dict[str, object]]] = {}
    if action == "update":
        ops = tool_input.get("updates")
        if isinstance(ops, list):
            grouped[str(tool_input.get("id"))] = [op for op in ops if isinstance(op, dict)]
    elif action == "update_batch":
        ops = tool_input.get("batchUpdates")
        for op in ops if isinstance(ops, list) else []:
            if isinstance(op, dict):
                grouped.setdefault(str(op.get("id")), []).append(op)
    return grouped


def _declarations(ops: list[dict[str, object]]) -> list[tuple[str, set[str], int]]:
    found = []
    for op in ops:
        if str(op.get("path") or "").lower() != "/fields/system.history" or not isinstance(op.get("value"), str):
            continue
        text = re.sub(r"(?i)<br\s*/?>|</p>|</div>", "\n", str(op["value"]))
        for match in _DECLARATION.finditer(_TAG.sub(" ", text)):
            removed = {_norm(h) for h in match.group(2).split(",") if _norm(h)}
            found.append((match.group(1).strip(), removed, int(match.group(3))))
    return found


def _declared(field: str, lost: list[str], new_len: int, declarations: list[tuple[str, set[str], int]]) -> bool:
    lost_set = {_norm(h) for h in lost}
    for name, removed, expect in declarations:
        same_field = name.casefold() == field.casefold() or field.casefold().endswith("." + name.casefold())
        if same_field and removed == lost_set and abs(new_len - expect) <= EXPECT_TOLERANCE * max(expect, 1):
            return True
    return False


def _verdict(decision: str, reason: str) -> dict[str, object]:
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": reason,
        }
    }


def check(payload: dict[str, object], conf_path: str) -> dict[str, object] | None:
    """PreToolUse verdict for a work-item update, or None to defer."""
    tool_input = _tool_input(payload)
    grouped = _updates_by_item(tool_input)
    if not grouped:
        return None

    conf = _config(conf_path)
    policy = conf["WI_FIELD_SHRINK_POLICY"].lower()
    policy = policy if policy in POLICIES else "ask"
    pct = _int(conf["WI_FIELD_SHRINK_PCT"], 10)
    chars = _int(conf["WI_FIELD_SHRINK_CHARS"], 200)
    min_chars = _int(conf["WI_FIELD_GUARD_MIN_CHARS"], 500)

    path = _cache_path(str(payload.get("session_id") or ""))
    cache = _load(path)
    entries = cache.get("items") if isinstance(cache.get("items"), dict) else {}

    findings: list[str] = []
    undeclared = 0
    new_marks: list[tuple[dict[str, object], str]] = []
    for item_id, ops in grouped.items():
        entry = entries.get(item_id) or {}
        cached_fields = entry.get("fields") if isinstance(entry.get("fields"), dict) else {}
        test_rev = next(
            (op.get("value") for op in ops if str(op.get("op")).lower() == "test" and op.get("path") == "/rev"), None
        )
        declarations = _declarations(ops)
        guarded: list[tuple[str, dict[str, object], str | None]] = []
        for op in ops:
            kind = str(op.get("op") or "").lower()
            field_path = str(op.get("path") or "")
            if kind not in ("add", "replace", "remove") or not field_path.startswith("/fields/"):
                continue
            field = field_path[len("/fields/") :]
            if field.casefold() in UNJUDGED_FIELDS:
                continue
            value = op.get("value") if kind != "remove" else ""
            new_text = value if isinstance(value, str) else ""
            cached = cached_fields.get(field)
            if cached is None:
                looks_long = field.casefold() in MULTILINE_FIELDS or "\n" in new_text or len(new_text) > min_chars
                if looks_long:
                    return _verdict(
                        "deny",
                        f"Field guard (#197): work item {item_id} field {field} was not read in this session, so "
                        "this update cannot be compared with what it replaces. Read the item first "
                        "(wit_work_item action=get, without a fields filter that omits this field), then retry "
                        "with a test op on /rev set to the revision you read.",
                    )
                continue
            if int(cached.get("len", 0)) > min_chars:
                guarded.append((field, cached, new_text))

        if not guarded:
            continue
        rev = int(entry.get("rev", -1))
        if test_rev is None:
            return _verdict(
                "deny",
                f"Field guard (#197): this update replaces long text on work item {item_id} without "
                f'{{"op": "test", "path": "/rev", "value": {rev}}}. Add it, so Azure DevOps itself rejects '
                "the write if the item changed since you read it.",
            )
        try:
            same_rev = int(test_rev) == rev
        except (TypeError, ValueError):
            same_rev = False
        if not same_rev:
            return _verdict(
                "deny",
                f"Field guard (#197): test /rev is {test_rev}, but this session last read work item {item_id} "
                f"at revision {rev}. Re-read the item and rebuild the update from what you read.",
            )

        marks = entry.get("marks") if isinstance(entry.get("marks"), list) else []
        for field, cached, new_text in guarded:
            old_len, new_len = int(cached.get("len", 0)), len(new_text or "")
            kept = {_norm(x) for x in headings(new_text or "")}
            lost = [h for h in cached.get("headings", []) if _norm(h) not in kept]
            drop = old_len - new_len
            if not (lost or (drop > chars and old_len and drop * 100 / old_len > pct)):
                continue
            mark = f"{field}@{rev}"
            is_declared = mark not in marks and _declared(field, lost, new_len, declarations)
            if not is_declared:
                undeclared += 1
            if mark not in marks:
                new_marks.append((entry, mark))
            change = f"-{round(drop * 100 / old_len)} %" if old_len and drop > 0 else "length kept"
            text = f"{field} of work item {item_id}: {old_len} -> {new_len} chars ({change})"
            if lost:
                text += f", headings dropped: {', '.join(lost)}"
            text += " [declared, and the diff matches]" if is_declared else ""
            findings.append(text)

    if not findings:
        return None

    if policy == "deny":
        decision = "deny"
    elif undeclared == 0 and policy in ("declared", "declared-strict"):
        return None
    elif policy == "declared-strict":
        decision = "deny"
    else:
        decision = "ask"
    # The reason names the loss; a declaration copied from it must not count next time.
    for entry, mark in new_marks:
        entry.setdefault("marks", []).append(mark)
    if new_marks:
        _save(path, cache)
    lead = "refused" if decision == "deny" else "needs confirmation"
    return _verdict(
        decision,
        f"Field guard (#197) -- this update shrinks long text and {lead} (WI_FIELD_SHRINK_POLICY={policy}): "
        + "; ".join(findings)
        + ". Confirm only if that loss is intended; otherwise re-read the item and rebuild the update "
        "from the text you read, changing only what was asked.",
    )
