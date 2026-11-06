#!/usr/bin/env python3
"""Collect the billed cost of one chat session from the agent debug log.

Emits a YAML `cost:` block on stdout for the documenter to append to
`.github/logs/{workflow-id}.yaml`. It never writes the workflow log, so the
documenter stays the only writer of it and this script stays testable without a
workflow. With ``--facts-out`` it also writes a per-request facts file, the one
artifact it does write.

The facts file exists because the debug log does not survive. It is machine-
local, it is deleted with the session store, it can lose its own beginning (a
log whose rows start mid-session is reported as ``coverage: truncated``), and
it contains every prompt verbatim, so it can never be committed or shared. Any
dimension not extracted while the log still exists is lost for that run
permanently. The aggregates below are therefore derived from the facts rows
rather than from a second pass over the log: a question nobody asked yet stays
answerable, and the block can never disagree with the rows it came from.

Both artifacts accumulate. A workflow can span several chat sessions while the
collector reads one at a time, so a rerun adds the rows the file does not
already carry -- keyed on the request, and on the payload for entities --
instead of replacing it. By the time the second session finalises, the log the
first session's rows came from is gone.

Exit codes:
    0  a block was emitted -- including ``available: false``
    2  usage error (argparse)

A vendor setting being off is not a failure of this framework, so an absent or
unusable log is a normal outcome, never a non-zero exit. The block is
ADVISORY: nothing downstream may gate on it.

The session directory is handed in (VS Code resolves it as
``VSCODE_TARGET_SESSION_LOG``) rather than discovered. Picking a session by
modification time would misattribute silently whenever parallel worktrees run
concurrent sessions. That variable resolves even when logging is disabled and
without checking that the directory exists, so it is a pointer, never
evidence -- everything below is verified here.
"""

from __future__ import annotations

import argparse
import contextlib
import glob
import hashlib
import json
import os
import re
import statistics
import sys
import time
from collections.abc import Callable, Iterator
from typing import Any

# v8: `surviving` and `gaps` when the total is withheld, coverage `gapped`, and
# `by_model`/`by_purpose` render `null` rather than `{}` when withheld (#457).
# v9: `kinds` names the inferred and lower-bound fields the block emitted (#477).
SCHEMA_VERSION = 9
COLLECTOR_VERSION = 9
# v2: the file accumulates instead of being replaced, so it carries one header
# per session and every row names the session it came from.
# v3: every row names the price tier it was priced at (#451).
FACTS_SCHEMA_VERSION = 3
ENTITY_SCHEMA_VERSION = 2

NANO_AIU_PER_CREDIT = 1_000_000_000

# What each top-level field of the `cost:` block is (#477; logs/README.md). A
# field missing here fails test-session-cost, so no estimate can ship as a fact.
FIELD_KINDS: dict[str, str] = {
    "schema_version": "meta",
    "collector": "meta",
    "kinds": "meta",
    "available": "meta",
    "reason": "meta",
    "coverage": "inferred",
    "earliest_ts": "measured",
    "gaps": "measured",
    "surviving": "lower_bound",
    "sessions": "meta",
    "requests": "measured",
    "unbilled_requests": "measured",
    "no_usage_requests": "measured",
    "drift": "measured",
    "tokens": "measured",
    "credits": "measured",
    "rate_card": "meta",
    "credits_by_kind": "inferred",
    "by_model": "measured",
    "by_purpose": "measured",
    "by_agent": "measured",
    "by_entity": "inferred",
    "facts": "meta",
    "environment": "meta",
}
# Rule ids, each defined in logs/README.md under "Measured, inferred, lower bound".
INFERRED_RULES: dict[str, str] = {
    "coverage": "log-head",
    "credits_by_kind": "price-tier-fit",
    "by_entity": "chars-per-token",
}
# The `cost_report:` of `--report`. What is complete rests on each session's
# coverage verdict, so it is inferred; sums over every row are lower bounds.
REPORT_FIELD_KINDS: dict[str, str] = {
    "schema_version": "meta",
    "collector": "meta",
    "kinds": "meta",
    "sessions": "measured",
    "complete": "inferred",
    "credits_complete": "inferred",
    "credits_lower_bound": "lower_bound",
    "requests": "lower_bound",
    "unbilled_requests": "lower_bound",
    "by_model": "lower_bound",
    "context_floor": "inferred",
    "by_session": "inferred",
}
REPORT_INFERRED_RULES: dict[str, str] = {
    "complete": "log-head",
    "credits_complete": "log-head",
    "context_floor": "first-request",
    "by_session": "log-head",
}
# A fall of more than this share between two requests of one log reads as a
# compaction (#479). Inferred: the log records sizes, not a compaction event.
CONTEXT_DROP = 0.5
MAIN_LOG = "main.jsonl"
TOP_FIELD = re.compile(r"^  ([a-z_]+):")

# The usual English rule of thumb. The vendor's tokenizer is not ours to run, so
# every count derived from it is named `_est` and never crossed with a price.
CHARS_PER_TOKEN = 4

# Dumped into the session directory by VS Code; carries the billing rate card.
RATE_CARD_FILE = "models.json"

# `debugName` values that are not agent work. Compaction is charged to whichever
# log it happened in, but it is a cost of the session having grown too long.
COMPACTION = "summarizeConversationHistory"
BACKGROUND = frozenset({"backgroundTodoAgent"})
# `other` last, and always rendered when present: an unrecognised debugName is
# a question, and sorting it into a known bucket would answer it by guessing.
PURPOSE_ORDER = ("agent_work", "compaction", "background", "other")

# Name of the bucket holding the parent session. Deliberately not `coordinator`:
# the file records which log a request came from, not which agent authored it,
# and a session that never delegated has no coordinator in it at all.
PARENT = "main"

# `runSubagent-ado-pr-manager-toolu_011DEuS1yqmhJkPQa1qmtY3U.jsonl`. Split on
# the LAST hyphen -- agent names contain hyphens, the tool-call id does not.
# Same parse as collect-agent-invocations.py; an unmatched name keeps its whole
# stem so a future id format shows up as an odd bucket instead of a lost one.
SUBAGENT = re.compile(r"^runSubagent-(?P<agent>.+)-(?P<call>[^-]+)\.jsonl$")

# Fields a billed request must carry. Missing any of them means the log schema
# moved; these are preview fields under no compatibility promise.
REQUIRED_REQUEST_ATTRS = ("model", "inputTokens", "cachedTokens", "outputTokens")

BILLING_ATTR = "copilotUsageNanoAiu"

# The subset that records what a request consumed. A request can end without
# consuming anything -- a failed compaction reports none of these and no
# billing attribute either -- and that absence is a fact about the request, not
# a changed log schema. `model` is excluded on purpose: it was present on every
# such record observed, so losing it would still be drift.
USAGE_ATTRS = ("inputTokens", "cachedTokens", "outputTokens")

# Definitions carried by the system prompt. Matched as whole elements so the
# measurement is the delivered bytes -- framing and envelope included -- rather
# than the source file the entry was generated from.
PROMPT_ENTITY = {
    "skill": re.compile(r"<skill>(.*?)</skill>", re.S),
    "agent": re.compile(r"<agent>(.*?)</agent>", re.S),
    "instruction": re.compile(r"<instruction>(.*?)</instruction>", re.S),
}
ENTITY_NAME = re.compile(r"<(?:name|file)>(.*?)</(?:name|file)>", re.S)
# An always-on instruction file is not listed but pasted in full, which is a
# different order of magnitude and a separate class for that reason.
ATTACHED = re.compile(r'<attachment filePath="(.*?)"[^>]*>.*?</attachment>', re.S)
# `[skipped] testing.instructions.md \u2014 applyTo '...' did not match any attached files`.
# The reason ends at the next bracketed marker, which is not always a status:
# the record also carries `[custom-agent]` and friends.
CUSTOMIZATION = re.compile(r"\[(applying|skipped|listed)\]\s+(.+?)\s+\u2014\s+(.*?)(?=,\s*\[|$)")
CUSTOMIZATION_CATEGORY = "customization"
REASON_LIMIT = 100


class Drift(Exception):
    """The log no longer carries the fields this collector depends on."""


def purpose_of(debug_name: str) -> str:
    """Why the request was made, not who made it."""
    if debug_name == COMPACTION:
        return "compaction"
    if debug_name in BACKGROUND:
        return "background"
    if debug_name.startswith("tool/runSubagent-") or debug_name.startswith("panel/"):
        return "agent_work"
    return "other"


def _basename(path: str) -> str:
    """Last segment, on either separator -- the dumps carry Windows paths."""
    return re.split(r"[\\/]", path.strip())[-1]


def tool_group(name: str) -> str:
    """Which server a tool came from, as far as the name allows.

    VS Code prefixes MCP tools `mcp_{server}_{tool}` and server names contain
    underscores themselves, so the boundary is not recoverable from the name
    alone. Grouping on the first token can therefore merge two servers that
    share it; it can never split one, which is the direction that matters when
    the question is whether a whole server earns its place in the payload.
    """
    if not name.startswith("mcp_"):
        return "built-in"
    head = name[len("mcp_") :].split("_", 1)[0]
    return f"mcp:{head}" if head else "built-in"


def dump_text(session_dir: str, name: Any) -> str | None:
    """Decode a payload dump, or None if it is absent or not what we expect."""
    if not isinstance(name, str) or not name or _basename(name) != name:
        # The name comes from the log; a dump is a bare filename in the session
        # directory, and anything with a path in it is not ours to open.
        return None
    try:
        with open(os.path.join(session_dir, name), encoding="utf-8", errors="replace") as handle:
            outer = json.load(handle)
    except (OSError, ValueError):
        return None
    content = outer.get("content") if isinstance(outer, dict) else None
    return content if isinstance(content, str) else None


def tool_entities(text: str) -> list[dict[str, Any]] | None:
    """One row per tool schema as delivered. None when the dump is unusable."""
    try:
        tools = json.loads(text)
    except (ValueError, TypeError):
        return None
    if not isinstance(tools, list):
        return None
    rows = []
    for tool in tools:
        if not isinstance(tool, dict) or not tool.get("name"):
            continue
        name = str(tool["name"])
        rows.append(
            {
                "class": "tool",
                "name": name,
                "group": tool_group(name),
                "chars": len(json.dumps(tool, separators=(",", ":"))),
            }
        )
    return rows


def prompt_entities(text: str) -> list[dict[str, Any]] | None:
    """One row per definition in the system prompt. None when unusable.

    Only element names and lengths are taken. The prompt body is instructions
    and attached file content, and nothing from it is copied out.
    """
    try:
        blocks = json.loads(text)
    except (ValueError, TypeError):
        return None
    if not isinstance(blocks, list):
        return None
    body = "".join(b.get("content") or "" for b in blocks if isinstance(b, dict))

    rows = []
    for entity_class, pattern in PROMPT_ENTITY.items():
        for match in pattern.finditer(body):
            named = ENTITY_NAME.search(match.group(1))
            rows.append(
                {
                    "class": entity_class,
                    "name": _basename(named.group(1)) if named else "unnamed",
                    "group": entity_class,
                    "chars": len(match.group(0)),
                }
            )
    for match in ATTACHED.finditer(body):
        rows.append(
            {
                "class": "instruction_attached",
                "name": _basename(match.group(1)),
                "group": "instruction",
                "chars": len(match.group(0)),
            }
        )
    return rows


def rate_card(session_dir: str) -> dict[str, list[dict[str, Any]]] | None:
    """Per-model price tiers, smallest prompt ceiling first, or None when unusable.

    `cache_write_price` is read but unusable: cache-write tokens are billed and
    never reported, which is what leaves a residual on every model that charges
    for them. Inferring the count would mean inventing a rounding rule.

    A model can carry more than `default` -- `long_context` was five times the
    default on one model (#451) -- and each tier states its `max_prompt_tokens`.
    """
    try:
        with open(os.path.join(session_dir, RATE_CARD_FILE), encoding="utf-8", errors="replace") as handle:
            models = json.load(handle)
    except (OSError, ValueError):
        return None
    if not isinstance(models, list):
        return None

    cards: dict[str, list[dict[str, Any]]] = {}
    for entry in models:
        if not isinstance(entry, dict) or not entry.get("id"):
            continue
        billing = entry.get("billing") or {}
        prices = billing.get("token_prices") or {}
        if not isinstance(prices.get("default"), dict):
            continue
        tiers = []
        for tier_name, tier in prices.items():
            if not isinstance(tier, dict):
                continue
            try:
                ceiling = tier.get("max_prompt_tokens")
                tiers.append(
                    {
                        "tier": str(tier_name),
                        "input": float(tier["input_price"]),
                        "cache_read": float(tier["cache_read_price"]),
                        "output": float(tier["output_price"]),
                        "ceiling": float(ceiling) if ceiling is not None else float("inf"),
                        "batch": float(prices.get("batch_size") or 1_000_000) or 1_000_000.0,
                        "discount": float(billing.get("auto_discount") or 0.0),
                    }
                )
            except (KeyError, TypeError, ValueError):
                continue
        if any(t["tier"] == "default" for t in tiers):
            cards[str(entry["id"])] = sorted(tiers, key=lambda t: (t["ceiling"], t["tier"] != "default"))
    return cards or None


def tier_for(tiers: list[dict[str, Any]], prompt_tokens: int) -> dict[str, Any]:
    """The cheapest tier whose ceiling holds the prompt; the largest if none does.

    Prompt = uncached + cached input. Inferred from a fit on billed requests
    (#451), not from a specification -- the tier is recorded on the row so the
    choice can be checked against the invoice.
    """
    for tier in tiers:
        if prompt_tokens <= tier["ceiling"]:
            return tier
    return tiers[-1]


def _shape_message_count(shape: Any) -> int | None:
    """Prompt length in messages -- the distance to the next compaction."""
    if not isinstance(shape, str):
        return None
    try:
        parsed = json.loads(shape)
    except (ValueError, TypeError):
        return None
    if not isinstance(parsed, dict):
        return None
    for key in ("messageCount", "inputItemCount"):
        value = parsed.get(key)
        if isinstance(value, int):
            return value
    return None


def _reasoning_effort(options: Any) -> str | None:
    if not isinstance(options, str):
        return None
    try:
        parsed = json.loads(options)
    except (ValueError, TypeError):
        return None
    if not isinstance(parsed, dict):
        return None
    effort = (parsed.get("reasoning") or {}).get("effort")
    return str(effort) if isinstance(effort, str) else None


def collect_entities(
    session_dir: str,
    facts: list[dict[str, Any]],
    invoked: dict[str, int],
) -> dict[str, Any]:
    """Measure the static payload every request carried, at grain payload x entity.

    A definition's tokens are part of a request's `inputTokens`, and a
    request-level billing record cannot be split by which span of the prompt it
    came from. So this axis reports what was *sent* and how often, never what it
    cost. The payload is identified from the request's own `systemPromptFile` /
    `toolsFile`, so which dump is which is read off the log rather than guessed
    from the filename.
    """
    used: dict[str, dict[str, Any]] = {}
    for fact in facts:
        for key, kind in (("system_prompt_file", "system_prompt"), ("tools_file", "tools")):
            name = fact.get(key)
            if isinstance(name, str) and name:
                entry = used.setdefault(name, {"kind": kind, "requests": 0})
                entry["requests"] += 1
    if not used:
        return {"available": False, "reason": "payload_not_named"}

    rows: list[dict[str, Any]] = []
    payloads = {"system_prompt": 0, "tools": 0, "unreadable": 0}
    for name in sorted(used):
        kind = used[name]["kind"]
        text = dump_text(session_dir, name)
        parsed = None
        if text is not None:
            parsed = tool_entities(text) if kind == "tools" else prompt_entities(text)
        if parsed is None:
            payloads["unreadable"] += 1
            continue
        payloads[kind] += 1
        for row in parsed:
            row["payload"] = name
            row["requests"] = used[name]["requests"]
            row["tokens_est"] = row["chars"] // CHARS_PER_TOKEN
            rows.append(row)

    if not rows:
        return {"available": False, "reason": "payload_dumps_unreadable"}
    return {"available": True, "rows": rows, "payloads": payloads, "invoked": invoked}


def _weighted(rows: list[dict[str, Any]], key: str, invoked_by: dict[str, int] | None) -> dict[str, dict[str, int]]:
    """Group entity rows and average their footprint over the requests that carried it.

    The mean is request-weighted rather than a pick of one payload: the payload
    changes during a session, and "what a request carried on average" is a
    measure, while "what the last payload happened to contain" is a choice.
    """
    agg: dict[str, dict[str, Any]] = {}
    for row in rows:
        bucket = agg.setdefault(row[key], {"names": set(), "weighted": 0, "payloads": {}})
        bucket["names"].add(row["name"])
        bucket["weighted"] += row["tokens_est"] * row["requests"]
        bucket["payloads"][row["payload"]] = row["requests"]

    out: dict[str, dict[str, int]] = {}
    for group, bucket in agg.items():
        deliveries = sum(bucket["payloads"].values())
        out[group] = {
            "entities": len(bucket["names"]),
            "tokens_est_per_request": round(bucket["weighted"] / deliveries) if deliveries else 0,
        }
        if invoked_by is not None:
            out[group]["invoked"] = invoked_by.get(group, 0)
    return out


def reports_no_usage(event: dict[str, Any]) -> bool:
    """True when the request accounts for nothing: no billing, no token counts.

    Deliberately not a test on `status`: of 51 such records measured, one
    carried `status: ok`, and a status-based check would have let that one
    through and voided the session anyway (issue #238).
    """
    attrs = event.get("attrs") or {}
    return attrs.get(BILLING_ATTR) is None and all(attrs.get(field) is None for field in USAGE_ATTRS)


def build_fact(event: dict[str, Any], session: str, log: str, agent: str) -> dict[str, Any]:
    """One row per request: every dimension the log carries, no prompt text.

    `inputMessages` and `userRequest` are verbatim prompts. They are the reason
    the debug log cannot be shared, and they are never read here -- a facts file
    that leaked them would inherit exactly that restriction.
    """
    attrs = event.get("attrs") or {}
    for field in REQUIRED_REQUEST_ATTRS:
        if attrs.get(field) is None:
            raise Drift(field)

    nano = attrs.get(BILLING_ATTR)
    input_tokens = int(attrs["inputTokens"])
    cached = int(attrs["cachedTokens"])
    debug_name = str(attrs.get("debugName") or "")

    return {
        "session": session,
        "log": log,
        "agent": agent,
        "ts": event.get("ts"),
        "dur": event.get("dur"),
        "status": event.get("status"),
        "span": event.get("spanId"),
        "parent_span": event.get("parentSpanId"),
        "parent_kind": None,  # resolved once every span in the session is known
        "model": str(attrs["model"]),
        "debug_name": debug_name,
        "purpose": purpose_of(debug_name),
        "reasoning_effort": _reasoning_effort(attrs.get("requestOptions")),
        "system_prompt_file": attrs.get("systemPromptFile"),
        "tools_file": attrs.get("toolsFile"),
        "message_count": _shape_message_count(attrs.get("requestShape")),
        "response_id": attrs.get("responseId"),
        "ttft": attrs.get("ttft"),
        "max_tokens": attrs.get("maxTokens"),
        # inputTokens already includes cachedTokens -- adding both double-counts.
        "input_uncached": input_tokens - cached,
        "cached": cached,
        "output": int(attrs["outputTokens"]),
        # Absent means *not billed* (measured: only `backgroundTodoAgent`
        # infrastructure calls), not lost. Never default it to zero.
        "billed": nano is not None,
        "nano_aiu": None if nano is None else int(nano),
    }


def price(fact: dict[str, Any], cards: dict[str, list[dict[str, Any]]] | None) -> None:
    """Split a request's charge across token kinds, in place.

    Verified as an exact identity against `copilotUsageNanoAiu` on every
    request of a model whose `cache_write_price` is 0. Where it is not 0 the
    remainder lands in `nano_unexplained` rather than being spread across the
    kinds that *are* known -- the parts must not appear to sum to the whole.
    """
    for key in ("nano_input_uncached", "nano_cache_read", "nano_output", "nano_unexplained", "price_tier"):
        fact[key] = None
    nano = fact["nano_aiu"]
    if nano is None:
        return

    tiers = (cards or {}).get(fact["model"])
    if not tiers:
        # An unpriced model is fully unexplained, never silently zero.
        fact["nano_unexplained"] = nano
        return

    card = tier_for(tiers, fact["input_uncached"] + fact["cached"])
    fact["price_tier"] = card["tier"]

    scale = NANO_AIU_PER_CREDIT * (1.0 - card["discount"]) / card["batch"]
    fact["nano_input_uncached"] = fact["input_uncached"] * card["input"] * scale
    fact["nano_cache_read"] = fact["cached"] * card["cache_read"] * scale
    fact["nano_output"] = fact["output"] * card["output"] * scale
    # Derived by subtraction so the four parts close on the billed total by
    # construction; a computed residual could not drift from the invoice.
    fact["nano_unexplained"] = nano - (fact["nano_input_uncached"] + fact["nano_cache_read"] + fact["nano_output"])


def _start_hook(event: Any) -> bool:
    """A SessionStart hook's span: written ahead of session_start in an intact log (#467)."""
    return isinstance(event, dict) and event.get("type") == "hook" and event.get("name") == "SessionStart"


def iter_events(path: str, head: dict[str, Any] | None = None) -> Iterator[dict[str, Any]]:
    """Yield parsed JSONL entries, skipping unparseable lines.

    Streams the file: a single session log reached 163 MB. When ``head`` is
    given it records whether the first non-empty line parsed and what it was:
    the size cap cuts mid-line, so a fragment there means the start is gone (#450).
    Leading SessionStart hook spans are passed over: the editor writes them
    before session_start (#467).
    """
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except (ValueError, TypeError):
                event = None
            if head is not None and "type" not in head and not _start_hook(event):
                head["type"] = event.get("type") if isinstance(event, dict) else None
            if isinstance(event, dict):
                if head is not None and "earliest_ts" not in head and isinstance(event.get("ts"), int):
                    head["earliest_ts"] = event["ts"]
                yield event


def log_files(session_dir: str) -> list[str]:
    """Return the parent log plus every subagent log in the same directory.

    Subagent turns are never in ``main.jsonl`` and run a different model, so
    reading only the parent understates every workflow that delegates.
    """
    files = [os.path.join(session_dir, "main.jsonl")]
    files.extend(sorted(glob.glob(os.path.join(session_dir, "runSubagent-*.jsonl"))))
    return files


def agent_from(path: str) -> str:
    """Bucket name for a log file: the parent, or the subagent that wrote it."""
    name = os.path.basename(path)
    if name == "main.jsonl":
        return PARENT
    match = SUBAGENT.match(name)
    if match:
        return match.group("agent")
    return name[: -len(".jsonl")] if name.endswith(".jsonl") else name


class Totals:
    """Billed aggregate over fact rows. Unbilled requests are counted, never summed."""

    def __init__(self) -> None:
        self.requests = 0
        self.unbilled = 0
        self.input_uncached = 0
        self.cached = 0
        self.output = 0
        self.nano_aiu = 0
        self.invocations = 0
        self.by_model: dict[str, dict[str, int]] = {}
        self.by_purpose: dict[str, dict[str, int]] = {}
        self.by_kind: dict[str, float] = {
            "input_uncached": 0.0,
            "cache_read": 0.0,
            "output": 0.0,
            "unexplained": 0.0,
        }

    def add(self, fact: dict[str, Any]) -> None:
        # Counted before the billed check: an unbilled purpose is still a
        # purpose, and `background` is exactly the one that would vanish.
        purpose = self.by_purpose.setdefault(fact["purpose"], {"requests": 0, "unbilled": 0, "nano_aiu": 0})

        if not fact["billed"]:
            self.unbilled += 1
            purpose["unbilled"] += 1
            return

        nano = int(fact["nano_aiu"])
        self.requests += 1
        self.input_uncached += fact["input_uncached"]
        self.cached += fact["cached"]
        self.output += fact["output"]
        self.nano_aiu += nano

        bucket = self.by_model.setdefault(fact["model"], {"requests": 0, "nano_aiu": 0})
        bucket["requests"] += 1
        bucket["nano_aiu"] += nano

        purpose["requests"] += 1
        purpose["nano_aiu"] += nano

        for kind, key in (
            ("input_uncached", "nano_input_uncached"),
            ("cache_read", "nano_cache_read"),
            ("output", "nano_output"),
            ("unexplained", "nano_unexplained"),
        ):
            self.by_kind[kind] += fact.get(key) or 0.0

    @property
    def credits(self) -> float:
        return round(self.nano_aiu / NANO_AIU_PER_CREDIT, 3)

    def credits_by_kind(self) -> dict[str, float]:
        return {k: round(v / NANO_AIU_PER_CREDIT, 3) for k, v in self.by_kind.items()}


class _Sink:
    """What one pass over log events accumulates, whether a whole log or a tail."""

    def __init__(self, session: str, cards: dict[str, list[dict[str, Any]]] | None) -> None:
        self.session = session
        self.cards = cards
        self.facts: list[dict[str, Any]] = []
        self.span_kind: dict[str, str] = {}
        self.invoked: dict[str, int] = {}
        self.customizations: dict[str, dict[str, Any]] = {}
        self.session_start: dict[str, Any] | None = None
        self.parsed = 0
        self.requests_seen = 0
        self.no_usage = 0
        self.drifted: dict[str, int] = {}
        self.drifted_logs: set[str] = set()

    def take(self, event: dict[str, Any], log: str, agent: str, is_main: bool) -> None:
        self.parsed += 1
        span = event.get("spanId")
        if isinstance(span, str):
            self.span_kind[span] = str(event.get("type"))
        kind = event.get("type")
        # Subagent logs and window reloads write their own session_start;
        # only main.jsonl's says when the session began (#450).
        if kind == "session_start" and is_main and self.session_start is None:
            self.session_start = event
        elif kind == "llm_request":
            self.requests_seen += 1
            if reports_no_usage(event):
                self.no_usage += 1
                return
            try:
                fact = build_fact(event, self.session, log, agent)
            except Drift as missing:
                # One unreadable record is a hole in the total, not a
                # reason to discard the records that read cleanly.
                self.drifted[str(missing)] = self.drifted.get(str(missing), 0) + 1
                # A session is many logs; drift in one subagent's log is a
                # different finding from drift in main.jsonl (issue #238).
                self.drifted_logs.add(log)
                return
            price(fact, self.cards)
            self.facts.append(fact)
        elif kind == "tool_call":
            # Only the name. `attrs.args` and `attrs.result` are the call's
            # payload and carry whatever the user put in front of it.
            called = event.get("name")
            if isinstance(called, str) and called:
                self.invoked[called] = self.invoked.get(called, 0) + 1
        elif kind == "generic":
            _record_customizations(event, self.customizations)

    def resolve_parents(self, known: dict[str, str] | None = None) -> None:
        """Every request has a parent span: the subagent, user message or hook that caused it."""
        for fact in self.facts:
            parent = fact["parent_span"]
            if isinstance(parent, str):
                fact["parent_kind"] = self.span_kind.get(parent) or (known or {}).get(parent)


def _tally(facts: list[dict[str, Any]], agent_files: list[str]) -> tuple[Totals, dict[str, Totals]]:
    totals = Totals()
    per_agent: dict[str, Totals] = {name: Totals() for name in agent_files}
    for name in agent_files:
        per_agent[name].invocations += 1
    for fact in facts:
        totals.add(fact)
        per_agent.setdefault(fact["agent"], Totals()).add(fact)
    return totals, per_agent


def collect(session_dir: str, workflow_start: int | None) -> dict[str, Any]:
    """Validate the session directory and aggregate it, or explain why not."""
    if not os.path.isdir(session_dir):
        return {"available": False, "reason": "session_dir_missing"}

    main = os.path.join(session_dir, "main.jsonl")
    if not os.path.isfile(main):
        return {"available": False, "reason": "main_log_missing"}

    session = os.path.basename(os.path.normpath(session_dir))
    sink = _Sink(session, rate_card(session_dir))
    agent_files: list[str] = []
    main_head: dict[str, Any] = {}

    for path in log_files(session_dir):
        if not os.path.isfile(path):
            continue
        agent = agent_from(path)
        # Counted from the filename, so an invocation that produced no billed
        # request still shows up as one -- it happened either way.
        agent_files.append(agent)
        log = os.path.basename(path)
        is_main = agent == PARENT
        for event in iter_events(path, main_head if is_main else None):
            sink.take(event, log, agent, is_main)

    if sink.parsed == 0:
        return {"available": False, "reason": "log_unparseable"}

    # Every request drifted and none survived: there is no total to degrade,
    # only one to withhold.
    if sink.drifted and not sink.facts:
        return {"available": False, "reason": "schema_drift"}

    sink.resolve_parents()
    result = _result(session_dir, sink, agent_files)

    if main_head.get("type") != "session_start":
        # The log lost its head before it was read, so the OLDEST entries --
        # the plan and Red phases -- are gone. A session_start further down is
        # a reload, not the start (#450).
        result["earliest_ts"] = main_head.get("earliest_ts")
        return _withhold(result, "truncated")

    started = (sink.session_start or {}).get("ts")
    return _certify(result, _coverage(started, workflow_start))


def _result(session_dir: str, sink: _Sink, agent_files: list[str]) -> dict[str, Any]:
    """The parts of a result every coverage verdict shares."""
    totals, per_agent = _tally(sink.facts, agent_files)
    result: dict[str, Any] = {
        "available": True,
        "sessions": [sink.session],
        "environment": _environment(sink.session_start),
        "facts": sink.facts,
        "rate_card": RATE_CARD_FILE if sink.cards else None,
        "entities": collect_entities(session_dir, sink.facts, sink.invoked),
        "customizations": sink.customizations,
        "no_usage_requests": sink.no_usage,
        "_totals": totals,
        "_per_agent": per_agent,
    }
    # Only when something was lost. A key that is always present stops being
    # read; one that appears only on a hole is a signal.
    if sink.drifted:
        result["drift"] = {
            "records": sum(sink.drifted.values()),
            "of": sink.requests_seen,
            "fields": sorted(sink.drifted),
            "logs": sorted(sink.drifted_logs),
        }
    return result


def _coverage(started: Any, workflow_start: int | None) -> str:
    if workflow_start is not None and isinstance(started, int) and started > workflow_start:
        return "partial"
    return "full"


def _certify(result: dict[str, Any], coverage: str) -> dict[str, Any]:
    result["coverage"] = coverage
    result["totals"] = result.pop("_totals")
    result["by_agent"] = result.pop("_per_agent")
    result["by_entity"] = result["entities"]
    return result


def _withhold(result: dict[str, Any], coverage: str) -> dict[str, Any]:
    """A set of requests known to be incomplete yields no total (#450).

    A total over it would look complete while being biased downward, and the
    per-agent split and the entity weighting inherit that bias. What the rows
    that did survive add up to is still a fact, so it is rendered under a name
    that says what it is -- `surviving`, a lower bound -- and never as `totals`
    (#457). Each entity row stays accurate; only the weighting behind the mean
    does not, so the rows survive and the mean does not.
    """
    result["coverage"] = coverage
    result["surviving"] = result.pop("_totals")
    result.pop("_per_agent")
    result["totals"] = None
    result["by_agent"] = None
    result["by_entity"] = None
    return result


# ── The session store (issue #457) ─────────────────────────────────────────
#
# The debug log loses its head at a moment nobody controls: 18 of 43 logs on one
# machine no longer started with session_start, at sizes from 1 to 231 MB, so no
# safe interval can be derived from the size. Extracted once, when a workflow
# finishes, a long session is gone before anyone reads it. The store is
# refreshed on every Stop and SubagentStop instead, and three properties make
# that affordable and trustworthy:
#
#   * Incremental. A log whose first bytes are unchanged was only appended to,
#     so only the bytes past the last offset are read. A full pass over a 92 MB
#     log took 2.8 s; a tail is milliseconds.
#   * Union, not snapshot. Completeness is judged over everything the store has
#     ever read. The log losing its head after a snapshot loses nothing.
#   * Proven continuity. When the head changed, the last line read is looked
#     for in the new file. Found, nothing between was lost. Not found, the cut
#     went past it, and the store records a gap with both timestamps instead of
#     certifying a total. Only hashes are kept: a line is a prompt.

# v2: head_seen judged past leading SessionStart hook spans (#467); v1 states
# marked every intact log of a hooked deployment as truncated, so they are re-read.
STORE_VERSION = 2
# A run that crashed leaves its lock behind; one older than this is taken over.
LOCK_STALE_SECONDS = 300
# How much of a log's head is hashed to prove the file was only appended to.
HEAD_PROBE = 4096
# How much of the last line read is hashed to recognise it when a cut lands inside it.
TAIL_PROBE = 256
# Waited for by a caller that renders a block, so it reads a store that is not mid-write.
LOCK_WAIT_SECONDS = 20.0


def _sig(data: bytes) -> str:
    return hashlib.sha1(data).hexdigest()


def _store_paths(store: str, session: str) -> dict[str, str]:
    return {
        "facts": os.path.join(store, f"{session}.facts.ndjson"),
        "state": os.path.join(store, f"{session}.state.json"),
        "lock": os.path.join(store, f"{session}.lock"),
    }


def _acquire(lock: str) -> bool:
    """Take the session lock, or report that another run holds it."""
    for _ in range(2):
        try:
            fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        except FileExistsError:
            try:
                age = time.time() - os.path.getmtime(lock)
            except OSError:
                continue
            if age < LOCK_STALE_SECONDS:
                return False
            try:
                os.remove(lock)
            except OSError:
                return False
            continue
        os.write(fd, str(os.getpid()).encode("ascii"))
        os.close(fd)
        return True
    return False


def _load_state(path: str, session: str) -> dict[str, Any]:
    try:
        with open(path, encoding="utf-8") as handle:
            state = json.load(handle)
        if isinstance(state, dict) and state.get("store_version") == STORE_VERSION:
            return state
    except (OSError, ValueError):
        pass
    return {
        "store_version": STORE_VERSION,
        "session": session,
        # None until main.jsonl is first seen: True when it then still began
        # with session_start, False when its head was already gone.
        "head_seen": None,
        "started_ts": None,
        "earliest_ts": None,
        "gaps": [],
        "logs": {},
        "spans": {},
        "invoked": {},
        "customizations": {},
        "environment": None,
        "no_usage_requests": 0,
        "requests_seen": 0,
        "drift": {},
        "drift_logs": [],
    }


def _save_state(path: str, state: dict[str, Any]) -> None:
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(state, handle, sort_keys=True)
    os.replace(tmp, path)


def _complete_lines(handle: Any, start: int) -> Iterator[tuple[int, bytes]]:
    """(offset after line, line) for every newline-terminated line from start.

    A line without its newline is still being written. Consuming it half would
    either lose it or count it twice once it is complete, so it is left for the
    next run, and the offset stays in front of it.
    """
    handle.seek(start)
    offset = start
    for raw in handle:
        if not raw.endswith(b"\n"):
            return
        offset += len(raw)
        yield offset, raw


def _parse(raw: bytes) -> dict[str, Any] | None:
    try:
        event = json.loads(raw.decode("utf-8", errors="replace"))
    except (ValueError, TypeError):
        return None
    return event if isinstance(event, dict) else None


def _read_log(path: str, prev: dict[str, Any] | None) -> dict[str, Any]:
    """Decide where reading resumes in one log, and whether anything was lost.

    Returns the start offset, the lines to skip at the front (already read
    before the head was cut), and a gap when continuity cannot be shown.
    """
    with open(path, "rb") as handle:
        if prev:
            head = handle.read(int(prev["head_len"]))
            size = os.path.getsize(path)
            if _sig(head) == prev["head_sig"] and size >= int(prev["offset"]):
                return {"start": int(prev["offset"]), "skip": 0, "gap": None, "rescan": False}

        if not prev or not prev.get("tail_sig"):
            return {"start": 0, "skip": 0, "gap": None, "rescan": prev is not None}

        # The head changed: find the last line read. A cut that landed inside
        # it leaves its tail as the first line, which still proves continuity.
        skip = None
        for index, (_, raw) in enumerate(_complete_lines(handle, 0)):
            line = raw.rstrip(b"\r\n")
            if _sig(line) == prev["tail_sig"]:
                skip = index + 1
                break
            if index == 0 and len(line) >= TAIL_PROBE and _sig(line[-TAIL_PROBE:]) == prev.get("tail_end_sig"):
                skip = 1
                break
        if skip is not None:
            return {"start": 0, "skip": skip, "gap": None, "rescan": True}
        return {"start": 0, "skip": 0, "gap": {"after_ts": prev.get("max_ts")}, "rescan": True}


def update_store(session_dir: str, store: str) -> dict[str, Any] | None:
    """Read what the logs gained since the last run into the store.

    Returns the state, or None when another run holds the lock or there is no
    log to read. Never raises for a missing or unreadable log: the store is
    advisory, and the next Stop tries again.
    """
    main = os.path.join(session_dir, "main.jsonl")
    if not os.path.isfile(main):
        return None
    session = os.path.basename(os.path.normpath(session_dir))
    os.makedirs(store, exist_ok=True)
    paths = _store_paths(store, session)
    if not _acquire(paths["lock"]):
        return None
    try:
        return _update_locked(session_dir, session, paths)
    finally:
        with contextlib.suppress(OSError):
            os.remove(paths["lock"])


def _update_locked(session_dir: str, session: str, paths: dict[str, str]) -> dict[str, Any]:
    state = _load_state(paths["state"], session)
    cards = rate_card(session_dir)
    sink = _Sink(session, cards)

    for path in log_files(session_dir):
        if not os.path.isfile(path):
            continue
        log = os.path.basename(path)
        agent = agent_from(path)
        is_main = agent == PARENT
        prev = state["logs"].get(log)
        plan = _read_log(path, prev)
        entry = dict(prev or {"max_ts": None, "tail_sig": None, "tail_end_sig": None})
        first_ts: int | None = None
        read_bytes = 0
        offset = plan["start"]

        with open(path, "rb") as handle:
            for index, (end, raw) in enumerate(_complete_lines(handle, plan["start"])):
                offset = end
                if index < plan["skip"]:
                    continue
                read_bytes += len(raw)
                line = raw.rstrip(b"\r\n")
                entry["tail_sig"] = _sig(line)
                entry["tail_end_sig"] = _sig(line[-TAIL_PROBE:]) if len(line) >= TAIL_PROBE else None
                event = _parse(raw)
                if is_main and state["head_seen"] is None and not _start_hook(event):
                    # First line past the SessionStart hook spans: did main.jsonl still begin at the start?
                    # Undecided until that line is read, which may be a later snapshot.
                    state["head_seen"] = bool(event and event.get("type") == "session_start")
                if event is None:
                    continue
                ts = event.get("ts")
                if isinstance(ts, int):
                    first_ts = ts if first_ts is None else first_ts
                    entry["max_ts"] = ts if entry["max_ts"] is None else max(int(entry["max_ts"]), ts)
                    if is_main and state["head_seen"] is False and state["earliest_ts"] is None:
                        state["earliest_ts"] = ts
                sink.take(event, log, agent, is_main)

            handle.seek(0)
            entry["head_len"] = min(HEAD_PROBE, offset)
            entry["head_sig"] = _sig(handle.read(entry["head_len"]))

        if plan["gap"] is not None:
            state["gaps"].append({"log": log, "after_ts": plan["gap"]["after_ts"], "resumed_ts": first_ts})
        entry["offset"] = offset
        entry["agent"] = agent
        entry["last_read_bytes"] = read_bytes
        state["logs"][log] = entry

    if sink.session_start is not None and state["started_ts"] is None and state["head_seen"]:
        state["started_ts"] = sink.session_start.get("ts")
        state["environment"] = _environment(sink.session_start)
    sink.resolve_parents(state["spans"])
    state["spans"].update(sink.span_kind)
    for name, count in sink.invoked.items():
        state["invoked"][name] = state["invoked"].get(name, 0) + count
    for name, bucket in sink.customizations.items():
        merged = state["customizations"].setdefault(name, {"applying": 0, "skipped": 0, "listed": 0, "reason": None})
        for status in ("applying", "skipped", "listed"):
            merged[status] += bucket[status]
        merged["reason"] = merged["reason"] or bucket["reason"]
    state["no_usage_requests"] += sink.no_usage
    state["requests_seen"] += sink.requests_seen
    for field, count in sink.drifted.items():
        state["drift"][field] = state["drift"].get(field, 0) + count
    state["drift_logs"] = sorted(set(state["drift_logs"]) | sink.drifted_logs)
    state["rate_card"] = RATE_CARD_FILE if cards else state.get("rate_card")
    state["updated"] = int(time.time() * 1000)

    if sink.facts:
        header = {
            "record": "header",
            "facts_schema_version": FACTS_SCHEMA_VERSION,
            "collector": f"collect-session-cost.py@{COLLECTOR_VERSION}",
            "session": session,
            # The store's coverage changes with every snapshot; the state file
            # carries it, a header written once could only carry a stale one.
            "coverage_in": os.path.basename(paths["state"]),
            "rate_card": state["rate_card"],
        }
        _append_ndjson(paths["facts"], header, sink.facts, _fact_key)
    _save_state(paths["state"], state)
    return state


def _store_rows(path: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                if isinstance(record, dict) and record.get("record") != "header":
                    rows.append(record)
    except OSError:
        pass
    return rows


def _store_coverage(state: dict[str, Any]) -> str:
    if not state.get("head_seen"):
        return "truncated"
    if state.get("gaps"):
        return "gapped"
    return "full"


def collect_store(session_dir: str, store: str, workflow_start: int | None) -> dict[str, Any]:
    """Refresh the store, then aggregate the union of everything it has read."""
    if not os.path.isdir(session_dir):
        return {"available": False, "reason": "session_dir_missing"}
    if not os.path.isfile(os.path.join(session_dir, "main.jsonl")):
        return {"available": False, "reason": "main_log_missing"}

    session = os.path.basename(os.path.normpath(session_dir))
    paths = _store_paths(store, session)
    deadline = time.time() + LOCK_WAIT_SECONDS
    while update_store(session_dir, store) is None and time.time() < deadline:
        # A background snapshot holds the lock; its result is what we want too.
        time.sleep(0.2)
    state = _load_state(paths["state"], session)
    if not state["logs"]:
        return {"available": False, "reason": "log_unparseable"}

    facts = _store_rows(paths["facts"])
    if state["drift"] and not facts:
        return {"available": False, "reason": "schema_drift"}

    sink = _Sink(session, None)
    sink.facts = facts
    sink.invoked = dict(state["invoked"])
    sink.customizations = dict(state["customizations"])
    sink.no_usage = int(state["no_usage_requests"])
    sink.requests_seen = int(state["requests_seen"])
    sink.drifted = dict(state["drift"])
    sink.drifted_logs = set(state["drift_logs"])
    agent_files = [entry.get("agent") or agent_from(log) for log, entry in sorted(state["logs"].items())]
    result = _result(session_dir, sink, agent_files)
    result["rate_card"] = state.get("rate_card")
    result["environment"] = state.get("environment") or _environment(None)

    coverage = _store_coverage(state)
    if coverage == "truncated":
        result["earliest_ts"] = state.get("earliest_ts")
        return _withhold(result, coverage)
    if coverage == "gapped":
        result["gaps"] = state["gaps"]
        return _withhold(result, coverage)
    return _certify(result, _coverage(state.get("started_ts"), workflow_start))


def context_series(facts: list[dict[str, Any]], head_lost: bool = False) -> dict[str, dict[str, Any]]:
    """Per log: input tokens per request over time, floor, median, max and inferred drops (#479).

    Input is uncached + cached: what the model read, not what it cost. Only
    agent_work requests count; a compaction call is a different conversation.
    The floor is the first request, so a log that lost its head has none.
    """
    series: dict[str, dict[str, Any]] = {}
    for fact in sorted(facts, key=lambda f: f.get("ts") or 0):
        if fact.get("purpose") != "agent_work":
            continue
        entry = series.setdefault(fact["log"], {"agent": fact["agent"], "points": []})
        entry["points"].append((fact["ts"], fact["input_uncached"] + fact["cached"], fact["model"]))
    for log, entry in series.items():
        points = entry["points"]
        sizes = [size for _, size, _ in points]
        entry["floor"] = None if head_lost and log == MAIN_LOG else sizes[0]
        entry["median"] = int(statistics.median(sizes))
        entry["max"] = max(sizes)
        entry["drops"] = [
            {"ts": cur[0], "from": prev[1], "to": cur[1]}
            for prev, cur in zip(points, points[1:], strict=False)
            if cur[1] < prev[1] * (1 - CONTEXT_DROP)
        ]
    return series


def report(store: str) -> str:
    """The total across every session in the store, complete and lower bound kept apart."""
    sessions: list[dict[str, Any]] = []
    floors: list[int] = []
    for path in sorted(glob.glob(os.path.join(store, "*.state.json"))):
        session = os.path.basename(path)[: -len(".state.json")]
        state = _load_state(path, session)
        if not state["logs"]:
            continue
        rows = _store_rows(_store_paths(store, session)["facts"])
        totals, _ = _tally(rows, [])
        stamps = [row["ts"] for row in rows if isinstance(row.get("ts"), int)]
        coverage = _store_coverage(state)
        if coverage == "full":
            main_series = context_series(rows).get(MAIN_LOG)
            if main_series:
                floors.append(main_series["floor"])
        sessions.append(
            {
                "session": session,
                "coverage": coverage,
                "totals": totals,
                "first_ts": min(stamps) if stamps else None,
                "last_ts": max(stamps) if stamps else None,
            }
        )

    complete = [s for s in sessions if s["coverage"] == "full"]
    every = Totals()
    for s in sessions:
        every.requests += s["totals"].requests
        every.unbilled += s["totals"].unbilled
        every.nano_aiu += s["totals"].nano_aiu
        for model, bucket in s["totals"].by_model.items():
            merged = every.by_model.setdefault(model, {"requests": 0, "nano_aiu": 0})
            merged["requests"] += bucket["requests"]
            merged["nano_aiu"] += bucket["nano_aiu"]
    credits_complete = round(sum(s["totals"].nano_aiu for s in complete) / NANO_AIU_PER_CREDIT, 3)

    lines = [
        "cost_report:",
        f"  schema_version: {SCHEMA_VERSION}",
        f'  collector: "collect-session-cost.py@{COLLECTOR_VERSION}"',
        f"  sessions: {len(sessions)}",
        f"  complete: {len(complete)}",
        # Only sessions whose every request is in the store sum to a number.
        f"  credits_complete: {credits_complete}",
        # Every row the store holds, including sessions with a gap or a lost
        # head: what was spent at least, never what was spent.
        f"  credits_lower_bound: {every.credits}",
        f"  requests: {every.requests}",
        f"  unbilled_requests: {every.unbilled}",
        # What the first request of a complete session read: the system prompt
        # and catalogue every empty turn carries (#479, #221).
        "  context_floor: "
        + (
            f"{{ sessions: {len(floors)}, min: {min(floors)}, median: {int(statistics.median(floors))},"
            f" max: {max(floors)} }}"
            if floors
            else "null"
        ),
        "  by_model:",
    ]
    for model, bucket in sorted(every.by_model.items()):
        lines.append(
            f"    {model}: {{ requests: {bucket['requests']}, "
            f"credits: {round(bucket['nano_aiu'] / NANO_AIU_PER_CREDIT, 3)} }}"
        )
    if not every.by_model:
        lines[-1] = "  by_model: {}"
    lines.append("  by_session:")
    for s in sorted(sessions, key=lambda s: (s["first_ts"] or 0, s["session"])):
        lines.append(
            f"    - {{ session: {_scalar(s['session'])}, coverage: {s['coverage']}, "
            f"requests: {s['totals'].requests}, credits: {s['totals'].credits}, "
            f"first_ts: {_scalar(s['first_ts'])}, last_ts: {_scalar(s['last_ts'])} }}"
        )
    if not sessions:
        lines[-1] = "  by_session: []"
    return "\n".join(_with_kinds(lines, REPORT_FIELD_KINDS, REPORT_INFERRED_RULES)) + "\n"


def _record_customizations(event: dict[str, Any], sink: dict[str, dict[str, Any]]) -> None:
    """Aggregate the per-turn `[applying] / [skipped]` record with its reason.

    An instruction file that never applies is pure cost: its catalogue entry is
    sent on every request regardless. The reason is the vendor's own words for
    why, and it is the part that says whether the fix is to narrow `applyTo` or
    to delete the file.
    """
    attrs = event.get("attrs") or {}
    if attrs.get("category") != CUSTOMIZATION_CATEGORY:
        return
    details = attrs.get("details")
    if not isinstance(details, str) or "|" not in details:
        return
    for status, name, reason in CUSTOMIZATION.findall(details.split("|", 1)[1]):
        bucket = sink.setdefault(_basename(name), {"applying": 0, "skipped": 0, "listed": 0, "reason": None})
        bucket[status] += 1
        if status != "applying" and not bucket["reason"]:
            bucket["reason"] = reason.strip()[:REASON_LIMIT]


def _environment(session_start: dict[str, Any] | None) -> dict[str, str | None]:
    attrs = (session_start or {}).get("attrs") or {}
    return {
        "vscode": attrs.get("vscodeVersion"),
        "copilot_chat": attrs.get("copilotVersion"),
    }


def _scalar(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    # YAML double-quoting is JSON escaping, so a Windows path stays a path
    # instead of becoming an invalid `\U` escape that breaks the whole log.
    return json.dumps(str(value))


def render(result: dict[str, Any], facts_path: str | None = None, entities_path: str | None = None) -> str:
    """Render the block. Only numbers and short identifiers are ever emitted.

    No field is copied from the log unless it is constructed here: request
    payloads carry whatever was pasted into chat.
    """
    lines = [
        "cost:",
        f"  schema_version: {SCHEMA_VERSION}",
        f'  collector: "collect-session-cost.py@{COLLECTOR_VERSION}"',
        f"  available: {_scalar(result['available'])}",
    ]
    if not result["available"]:
        lines.append(f"  reason: {result['reason']}")
        return "\n".join(lines) + "\n"

    sessions = ", ".join(_scalar(s) for s in result["sessions"])
    totals: Totals | None = result["totals"]
    env = result["environment"]

    lines.append(f"  coverage: {result['coverage']}")
    if "earliest_ts" in result:
        # Only on a truncated log: dates the first event that survived the cap.
        lines.append(f"  earliest_ts: {_scalar(result['earliest_ts'])}")
    if result.get("gaps"):
        # Where the log was cut past the last line the store had read.
        lines.append("  gaps:")
        for gap in result["gaps"]:
            lines.append(
                f"    - {{ log: {_scalar(gap.get('log'))}, after_ts: {_scalar(gap.get('after_ts'))},"
                f" resumed_ts: {_scalar(gap.get('resumed_ts'))} }}"
            )
    surviving: Totals | None = result.get("surviving")
    if surviving is not None:
        # What the rows that did survive add up to: a lower bound, never a total.
        lines.append(
            f"  surviving: {{ requests: {surviving.requests}, unbilled_requests: {surviving.unbilled},"
            f" credits: {surviving.credits} }}"
        )
    lines.append(f"  sessions: [{sessions}]")
    lines.append(f"  requests: {_scalar(totals.requests if totals else None)}")
    lines.append(f"  unbilled_requests: {_scalar(totals.unbilled if totals else None)}")
    # Separate from `unbilled`, which counts requests that did spend tokens.
    lines.append(f"  no_usage_requests: {_scalar(result.get('no_usage_requests'))}")
    drift = result.get("drift")
    if drift:
        lines.append(
            f"  drift: {{ records: {drift['records']}, of: {drift['of']}, "
            f"fields: [{', '.join(drift['fields'])}], logs: [{', '.join(drift['logs'])}] }}"
        )
    lines.append(
        f"  tokens: {{ input_uncached: {_scalar(totals.input_uncached if totals else None)}, "
        f"cached: {_scalar(totals.cached if totals else None)}, "
        f"output: {_scalar(totals.output if totals else None)} }}"
    )
    lines.append(f"  credits: {_scalar(totals.credits if totals else None)}")
    lines.append(f"  rate_card: {_scalar(result.get('rate_card'))}")
    if totals is None:
        lines.append("  credits_by_kind: null")
    else:
        kinds = totals.credits_by_kind()
        lines.append(
            f"  credits_by_kind: {{ input_uncached: {kinds['input_uncached']},"
            f" cache_read: {kinds['cache_read']}, output: {kinds['output']},"
            f" unexplained: {kinds['unexplained']} }}"
        )
    lines.append("  by_model:")
    for model, bucket in sorted((totals.by_model if totals else {}).items()):
        credits = round(bucket["nano_aiu"] / NANO_AIU_PER_CREDIT, 3)
        lines.append(f"    {model}: {{ requests: {bucket['requests']}, credits: {credits} }}")
    if not (totals and totals.by_model):
        # Withheld is not empty: `{}` would read as "cost nothing" (#457).
        lines[-1] = "  by_model: {}" if totals else "  by_model: null"
    lines.extend(_by_purpose(totals.by_purpose, "  ") if totals else ["  by_purpose: null"])
    lines.extend(_by_agent(result.get("by_agent")))
    lines.extend(_by_entity(result, entities_path))
    # Names the artifact a third party can re-aggregate, not just this summary.
    lines.append(f"  facts: {_scalar(facts_path)}")
    lines.append(f"  environment: {{ vscode: {_scalar(env['vscode'])}, copilot_chat: {_scalar(env['copilot_chat'])} }}")
    return "\n".join(_with_kinds(lines)) + "\n"


def _with_kinds(
    lines: list[str], kinds: dict[str, str] = FIELD_KINDS, rules: dict[str, str] = INFERRED_RULES
) -> list[str]:
    """Name the inferred and lower-bound fields among those emitted; the rest are measured or meta (#477)."""
    emitted = [m.group(1) for line in lines if (m := TOP_FIELD.match(line))]
    inferred = [f"{name}: {rules[name]}" for name in emitted if kinds.get(name) == "inferred"]
    lower = [name for name in emitted if kinds.get(name) == "lower_bound"]
    parts = []
    if inferred:
        parts.append("inferred: { " + ", ".join(inferred) + " }")
    if lower:
        parts.append("lower_bound: [" + ", ".join(lower) + "]")
    if not parts:
        return lines
    return [*lines[:3], f"  kinds: {{ {', '.join(parts)} }}", *lines[3:]]


def _by_agent(per_agent: dict[str, Totals] | None) -> list[str]:
    """Which log each request came from, keyed by agent (issue #212).

    `totals` carries the same fields as the session totals so the split
    reconciles against them, and `by_model` resolves the two axes jointly:
    "the implementer is expensive" and "opus is expensive" are different
    findings, and only the crossing says which agent to move off which model.
    """
    if per_agent is None:
        # Withheld, not empty: `{}` would read as "no agent consumed anything".
        return ["  by_agent: null"]
    if not per_agent:
        return ["  by_agent: {}"]
    lines = ["  by_agent:"]
    # Most expensive first: the block exists to be acted on, and the reader
    # who stops after two lines should have read the two that matter.
    order = sorted(per_agent.items(), key=lambda kv: (-kv[1].nano_aiu, kv[0]))
    for agent, bucket in order:
        lines.append(f"    {agent}:")
        lines.append(
            f"      totals: {{ invocations: {bucket.invocations}, requests: {bucket.requests}, "
            f"unbilled_requests: {bucket.unbilled}, input_uncached: {bucket.input_uncached}, "
            f"cached: {bucket.cached}, output: {bucket.output}, credits: {bucket.credits} }}"
        )
        if bucket.by_model:
            lines.append("      by_model:")
            for model, sub in sorted(bucket.by_model.items()):
                credits = round(sub["nano_aiu"] / NANO_AIU_PER_CREDIT, 3)
                lines.append(f"        {model}: {{ requests: {sub['requests']}, credits: {credits} }}")
        else:
            lines.append("      by_model: {}")
        # Rendered for every bucket, including the uniform ones: a reader must
        # not have to decide whether an absent split means uniform or unknown.
        lines.extend(_by_purpose(bucket.by_purpose, "      "))
    return lines


def _by_purpose(by_purpose: dict[str, dict[str, int]], indent: str) -> list[str]:
    """What each request was *for* (issue #215).

    Compaction is the price of the session having grown too long, not of the
    agent whose turn happened to trigger it, and the lever that reduces it is a
    different one. Unbilled purposes are listed too, or `background` -- which is
    always unbilled -- would be the one category that silently disappears.
    """
    if not by_purpose:
        return [f"{indent}by_purpose: {{}}"]
    lines = [f"{indent}by_purpose:"]
    known = [p for p in PURPOSE_ORDER if p in by_purpose]
    rest = sorted(p for p in by_purpose if p not in PURPOSE_ORDER)
    for purpose in known + rest:
        sub = by_purpose[purpose]
        credits = round(sub["nano_aiu"] / NANO_AIU_PER_CREDIT, 3)
        lines.append(
            f"{indent}  {purpose}: {{ requests: {sub['requests']}, unbilled: {sub['unbilled']}, credits: {credits} }}"
        )
    return lines


def _by_entity(result: dict[str, Any], entities_path: str | None) -> list[str]:
    """What the requests carried, not what it cost (issue #214).

    Deliberately has no credits column anywhere. An entity's tokens are inside
    a request's `inputTokens`, and a request-level billing record cannot be
    split by which span of the prompt produced it, so a per-entity credit
    figure could only be invented by dividing. What is honest is the footprint,
    how many requests carried it, and how often it was actually used.
    """
    entities = result.get("by_entity")
    if entities is None:
        # Withheld, not empty -- the weighting behind the mean is incomplete.
        return ["  by_entity: null"]
    if not entities.get("available"):
        return [
            "  by_entity:",
            "    available: false",
            f"    reason: {entities.get('reason')}",
        ]

    rows = entities["rows"]
    payloads = entities["payloads"]
    invoked = entities["invoked"]
    by_group: dict[str, int] = {}
    for name, count in invoked.items():
        group = tool_group(name)
        by_group[group] = by_group.get(group, 0) + count

    lines = [
        "  by_entity:",
        "    available: true",
        # Stated in the block, not only in the docs: the next reader of this
        # file is the one who would otherwise cross a footprint with a price.
        "    credits_attributable: false",
        f"    payloads: {{ system_prompt: {payloads['system_prompt']}, tools: {payloads['tools']},"
        f" unreadable: {payloads['unreadable']} }}",
        "    classes:",
    ]
    classes = _weighted(rows, "class", None)
    for name, bucket in sorted(classes.items(), key=lambda kv: (-kv[1]["tokens_est_per_request"], kv[0])):
        lines.append(f"      {name}: {{ {_entity_fields(bucket)} }}")

    # `invoked` is reported only where it is complete. A skill or an agent
    # description is read by the model, not called, so a zero there would mean
    # "not measurable", which is not what a zero next to a token count reads as.
    lines.append("    tools_by_group:")
    tools = [row for row in rows if row["class"] == "tool"]
    groups = _weighted(tools, "group", by_group)
    if not groups:
        lines[-1] = "    tools_by_group: {}"
    for name, bucket in sorted(groups.items(), key=lambda kv: (-kv[1]["tokens_est_per_request"], kv[0])):
        lines.append(f"      {name}: {{ {_entity_fields(bucket)} }}")

    lines.extend(_customizations(result.get("customizations") or {}))
    lines.append(f"    rows: {_scalar(entities_path)}")
    return lines


def _entity_fields(bucket: dict[str, int]) -> str:
    fields = f"entities: {bucket['entities']}, tokens_est_per_request: {bucket['tokens_est_per_request']}"
    if "invoked" in bucket:
        fields += f", invoked: {bucket['invoked']}"
    return fields


def _customizations(customizations: dict[str, dict[str, Any]]) -> list[str]:
    """Which definitions applied and which were skipped, with the reason why.

    Never-applied first: those are the ones whose entry was paid for on every
    request and used on none, and the reason states whether the fix is to
    narrow `applyTo` or to remove the file.
    """
    if not customizations:
        return ["    customizations: {}"]
    lines = ["    customizations:"]
    order = sorted(customizations.items(), key=lambda kv: (kv[1]["applying"] > 0, kv[0]))
    for name, bucket in order:
        fields = f"applying: {bucket['applying']}, skipped: {bucket['skipped']}, listed: {bucket['listed']}"
        if bucket["reason"]:
            fields += f", reason: {_scalar(bucket['reason'])}"
        lines.append(f"      {name}: {{ {fields} }}")
    return lines


def _fact_key(record: dict[str, Any]) -> tuple:
    """Identify a request. `span` is unique per session; the rest disambiguates
    a log that reported none."""
    return (
        record.get("session"),
        record.get("span"),
        record.get("ts"),
        record.get("response_id"),
    )


def _entity_key(record: dict[str, Any]) -> tuple:
    return (
        record.get("session"),
        record.get("payload"),
        record.get("kind"),
        record.get("name"),
    )


def _append_ndjson(
    path: str,
    header: dict[str, Any],
    records: list[dict[str, Any]],
    key_of: Callable[[dict[str, Any]], tuple],
) -> str | None:
    """Add the records this file does not already carry. Returns the path, or None.

    A workflow can span several chat sessions and the collector reads one
    session at a time, so the file is written more than once for the same
    workflow. Overwriting would make the last session the only one that ever
    existed -- and the debug log the earlier rows came from is gone by then, so
    that loss is permanent and silent. Appending with a dedup key instead makes
    a repeat call idempotent: re-running against the same session adds nothing.

    One header per session, so a reader can tell which coverage and which rate
    card the rows after it were priced under. Failure to write is reported,
    never raised: the cost block is advisory and must still be emitted.
    """
    seen: set[tuple] = set()
    header_written = False
    try:
        if os.path.exists(path):
            with open(path, encoding="utf-8") as handle:
                for line in handle:
                    try:
                        record = json.loads(line)
                    except ValueError:
                        # A half-written last line must not void the whole file.
                        continue
                    if record.get("record") == "header":
                        if record.get("session") == header.get("session"):
                            header_written = True
                    else:
                        seen.add(key_of(record))

        new = [record for record in records if key_of(record) not in seen]
        if header_written and not new:
            return path

        directory = os.path.dirname(os.path.abspath(path))
        if directory:
            os.makedirs(directory, exist_ok=True)
        with open(path, "a", encoding="utf-8", newline="\n") as handle:
            if not header_written:
                handle.write(json.dumps(header, sort_keys=True) + "\n")
            for record in new:
                handle.write(json.dumps(record, sort_keys=True) + "\n")
    except OSError:
        return None
    return path


def write_facts(path: str, result: dict[str, Any]) -> str | None:
    """Write the per-request rows as NDJSON. Returns the path, or None.

    A header row carries the schema version and the rate card the prices came
    from, so a row can be re-priced later without guessing which card was in
    force.
    """
    facts = result.get("facts")
    if not facts:
        return None
    header = {
        "record": "header",
        "facts_schema_version": FACTS_SCHEMA_VERSION,
        "collector": f"collect-session-cost.py@{COLLECTOR_VERSION}",
        "session": result["sessions"][0],
        "coverage": result.get("coverage"),
        "rate_card": result.get("rate_card"),
    }
    return _append_ndjson(path, header, facts, _fact_key)


def write_entities(path: str, result: dict[str, Any]) -> str | None:
    """Write the entity rows as NDJSON at grain payload x entity.

    Its own schema version and its own header, because it is a different grain
    from the facts file and the two must never be summed together. A row says
    "this definition was inside this delivered payload, and that payload went
    out on `requests` requests". `requests` is a multiplier, not a count of
    anything the row itself did: adding it up across rows counts each request
    once per definition it carried. The fan-out is left visible as a column
    rather than materialised as duplicate rows, and there is no credits column
    at any grain -- see `_by_entity`.
    """
    entities = result.get("entities") or {}
    rows = entities.get("rows")
    if not rows:
        return None
    session = result["sessions"][0]
    header = {
        "record": "header",
        "entity_schema_version": ENTITY_SCHEMA_VERSION,
        "collector": f"collect-session-cost.py@{COLLECTOR_VERSION}",
        "session": session,
        "coverage": result.get("coverage"),
        "grain": "payload x entity",
        "credits_attributable": False,
        "requests_is_a_multiplier": True,
    }
    # The session is on the row, not only the header: once the file accumulates
    # more than one session, a payload name alone no longer identifies a row.
    records = [{"record": "entity", "session": session, **row} for row in rows]
    return _append_ndjson(path, header, records, _entity_key)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Collect billed session cost from the agent debug log.",
    )
    parser.add_argument(
        "--session-dir",
        default=None,
        help="Session log directory (VS Code: VSCODE_TARGET_SESSION_LOG).",
    )
    parser.add_argument(
        "--workflow-start",
        type=int,
        default=None,
        help="Workflow start as epoch milliseconds; enables partial-coverage detection.",
    )
    parser.add_argument(
        "--facts-out",
        default=None,
        help="Write the per-request facts as NDJSON here. The debug log expires; these rows do not.",
    )
    parser.add_argument(
        "--entities-out",
        default=None,
        help="Write the payload-by-entity rows as NDJSON here. Different grain from --facts-out.",
    )
    parser.add_argument(
        "--store",
        default=None,
        help="Session store directory. Refreshed incrementally; the block aggregates its union.",
    )
    parser.add_argument(
        "--snapshot",
        action="store_true",
        help="With --store: refresh the store and print nothing. What the Stop hook runs.",
    )
    parser.add_argument(
        "--report",
        default=None,
        metavar="STORE",
        help="Print the total across every session in this store, instead of one session's block.",
    )
    args = parser.parse_args(argv)

    if args.report:
        sys.stdout.write(report(args.report))
        return 0
    if not args.session_dir:
        parser.error("--session-dir is required (or --report STORE)")
    if args.snapshot:
        if not args.store:
            parser.error("--snapshot needs --store")
        # One attempt: a held lock means another run is reading the same bytes.
        # Advisory: on an I/O error the next Stop tries again from the same offset.
        with contextlib.suppress(OSError):
            update_store(args.session_dir, args.store)
        return 0

    if args.store:
        result = collect_store(args.session_dir, args.store, args.workflow_start)
    else:
        result = collect(args.session_dir, args.workflow_start)
    written = write_facts(args.facts_out, result) if args.facts_out else None
    entities = write_entities(args.entities_out, result) if args.entities_out else None
    sys.stdout.write(render(result, written, entities))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
