#!/usr/bin/env python3
"""Collect the billed cost of one chat session from the agent debug log.

Emits a YAML `cost:` block on stdout for the documenter to append to
`.github/logs/{workflow-id}.yaml`. It never writes the workflow log, so the
documenter stays the only writer of it and this script stays testable without a
workflow. With ``--facts-out`` it also writes a per-request facts file, the one
artifact it does write.

The facts file exists because the debug log does not survive. It is capped at
100 MB, truncation drops the *oldest* entries, and it contains every prompt
verbatim, so it can never be committed or shared. Any dimension not extracted
while the log still exists is lost for that run permanently. The aggregates
below are therefore derived from the facts rows rather than from a second pass
over the log: a question nobody asked yet stays answerable, and the block can
never disagree with the rows it came from.

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
import glob
import json
import os
import re
import sys
from typing import Any, Iterator

SCHEMA_VERSION = 4
COLLECTOR_VERSION = 4
FACTS_SCHEMA_VERSION = 1

NANO_AIU_PER_CREDIT = 1_000_000_000

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


def rate_card(session_dir: str) -> dict[str, dict[str, float]] | None:
    """Per-model token prices, or None when the dump is absent or unusable.

    `cache_write_price` is read but unusable: cache-write tokens are billed and
    never reported, which is what leaves a residual on every model that charges
    for them. Inferring the count would mean inventing a rounding rule.
    """
    try:
        with open(os.path.join(session_dir, RATE_CARD_FILE), encoding="utf-8", errors="replace") as handle:
            models = json.load(handle)
    except (OSError, ValueError):
        return None
    if not isinstance(models, list):
        return None

    cards: dict[str, dict[str, float]] = {}
    for entry in models:
        if not isinstance(entry, dict) or not entry.get("id"):
            continue
        billing = entry.get("billing") or {}
        prices = billing.get("token_prices") or {}
        default = prices.get("default")
        if not isinstance(default, dict):
            continue
        try:
            cards[str(entry["id"])] = {
                "input": float(default["input_price"]),
                "cache_read": float(default["cache_read_price"]),
                "output": float(default["output_price"]),
                "batch": float(prices.get("batch_size") or 1_000_000) or 1_000_000.0,
                "discount": float(billing.get("auto_discount") or 0.0),
            }
        except (KeyError, TypeError, ValueError):
            continue
    return cards or None


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


def price(fact: dict[str, Any], cards: dict[str, dict[str, float]] | None) -> None:
    """Split a request's charge across token kinds, in place.

    Verified as an exact identity against `copilotUsageNanoAiu` on every
    request of a model whose `cache_write_price` is 0. Where it is not 0 the
    remainder lands in `nano_unexplained` rather than being spread across the
    kinds that *are* known -- the parts must not appear to sum to the whole.
    """
    for key in ("nano_input_uncached", "nano_cache_read", "nano_output", "nano_unexplained"):
        fact[key] = None
    nano = fact["nano_aiu"]
    if nano is None:
        return

    card = (cards or {}).get(fact["model"])
    if card is None:
        # An unpriced model is fully unexplained, never silently zero.
        fact["nano_unexplained"] = nano
        return

    scale = NANO_AIU_PER_CREDIT * (1.0 - card["discount"]) / card["batch"]
    fact["nano_input_uncached"] = fact["input_uncached"] * card["input"] * scale
    fact["nano_cache_read"] = fact["cached"] * card["cache_read"] * scale
    fact["nano_output"] = fact["output"] * card["output"] * scale
    # Derived by subtraction so the four parts close on the billed total by
    # construction; a computed residual could not drift from the invoice.
    fact["nano_unexplained"] = nano - (fact["nano_input_uncached"] + fact["nano_cache_read"] + fact["nano_output"])


def iter_events(path: str) -> Iterator[dict[str, Any]]:
    """Yield parsed JSONL entries, skipping unparseable lines.

    Streams the file: a single session log reached 25 MB within a few hours.
    """
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except (ValueError, TypeError):
                continue
            if isinstance(event, dict):
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


def collect(session_dir: str, workflow_start: int | None) -> dict[str, Any]:
    """Validate the session directory and aggregate it, or explain why not."""
    if not os.path.isdir(session_dir):
        return {"available": False, "reason": "session_dir_missing"}

    main = os.path.join(session_dir, "main.jsonl")
    if not os.path.isfile(main):
        return {"available": False, "reason": "main_log_missing"}

    session = os.path.basename(os.path.normpath(session_dir))
    cards = rate_card(session_dir)
    session_start: dict[str, Any] | None = None
    facts: list[dict[str, Any]] = []
    span_kind: dict[str, str] = {}
    agent_files: list[str] = []
    parsed = 0

    for path in log_files(session_dir):
        if not os.path.isfile(path):
            continue
        agent = agent_from(path)
        # Counted from the filename, so an invocation that produced no billed
        # request still shows up as one -- it happened either way.
        agent_files.append(agent)
        log = os.path.basename(path)
        for event in iter_events(path):
            parsed += 1
            span = event.get("spanId")
            if isinstance(span, str):
                span_kind[span] = str(event.get("type"))
            kind = event.get("type")
            if kind == "session_start" and session_start is None:
                session_start = event
            elif kind == "llm_request":
                try:
                    fact = build_fact(event, session, log, agent)
                except Drift:
                    return {"available": False, "reason": "schema_drift"}
                price(fact, cards)
                facts.append(fact)

    if parsed == 0:
        return {"available": False, "reason": "log_unparseable"}

    # The trace states what the filename only implies: every request has a
    # parent span, resolving to the subagent, user message or hook that caused it.
    for fact in facts:
        parent = fact["parent_span"]
        if isinstance(parent, str):
            fact["parent_kind"] = span_kind.get(parent)

    totals = Totals()
    per_agent: dict[str, Totals] = {name: Totals() for name in agent_files}
    for name in agent_files:
        per_agent[name].invocations += 1
    for fact in facts:
        totals.add(fact)
        per_agent[fact["agent"]].add(fact)

    result: dict[str, Any] = {
        "available": True,
        "sessions": [session],
        "environment": _environment(session_start),
        "facts": facts,
        "rate_card": RATE_CARD_FILE if cards else None,
    }

    if session_start is None:
        # The size cap drops the OLDEST entries, i.e. the plan and Red phases.
        # A total would look complete while being biased downward, so emit none.
        # The per-agent split inherits that bias and is withheld with it.
        result["coverage"] = "truncated"
        result["totals"] = None
        result["by_agent"] = None
        return result

    started = session_start.get("ts")
    if workflow_start is not None and isinstance(started, int) and started > workflow_start:
        result["coverage"] = "partial"
    else:
        result["coverage"] = "full"
    result["totals"] = totals
    result["by_agent"] = per_agent
    return result


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


def render(result: dict[str, Any], facts_path: str | None = None) -> str:
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
    lines.append(f"  sessions: [{sessions}]")
    lines.append(f"  requests: {_scalar(totals.requests if totals else None)}")
    lines.append(f"  unbilled_requests: {_scalar(totals.unbilled if totals else None)}")
    lines.append(
        "  tokens: {{ input_uncached: {0}, cached: {1}, output: {2} }}".format(
            _scalar(totals.input_uncached if totals else None),
            _scalar(totals.cached if totals else None),
            _scalar(totals.output if totals else None),
        )
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
        lines[-1] = "  by_model: {}"
    lines.extend(_by_purpose(totals.by_purpose if totals else {}, "  "))
    lines.extend(_by_agent(result.get("by_agent")))
    # Names the artifact a third party can re-aggregate, not just this summary.
    lines.append(f"  facts: {_scalar(facts_path)}")
    lines.append(f"  environment: {{ vscode: {_scalar(env['vscode'])}, copilot_chat: {_scalar(env['copilot_chat'])} }}")
    return "\n".join(lines) + "\n"


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


def write_facts(path: str, result: dict[str, Any]) -> str | None:
    """Write the per-request rows as NDJSON. Returns the path, or None.

    One header row carries the schema version and the rate card the prices came
    from, so a row can be re-priced later without guessing which card was in
    force. Failure to write is reported, never raised: the block is advisory and
    must still be emitted.
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
    try:
        directory = os.path.dirname(os.path.abspath(path))
        if directory:
            os.makedirs(directory, exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(json.dumps(header, sort_keys=True) + "\n")
            for fact in facts:
                handle.write(json.dumps(fact, sort_keys=True) + "\n")
    except OSError:
        return None
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Collect billed session cost from the agent debug log.",
    )
    parser.add_argument(
        "--session-dir",
        required=True,
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
    args = parser.parse_args(argv)

    result = collect(args.session_dir, args.workflow_start)
    written = write_facts(args.facts_out, result) if args.facts_out else None
    sys.stdout.write(render(result, written))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
