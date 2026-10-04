#!/usr/bin/env python3
"""Report actual GitHub Copilot token usage and AI credit cost per chat session.

Reads the per-turn usage telemetry that VS Code persists in its chat session
store and reports what the framework actually cost to run.

Two record shapes exist and are reported separately:

1. ``source: foreground`` -- a real user turn (the agent doing work).
2. ``source: background`` -- context compaction / summarization, billed to a
   separate, usually cheaper model. This is framework overhead, not work.

Foreground turns are *sampled*, not recorded per turn: measurement across 139
session files found roughly one foreground record per file, regardless of how
long the session ran. The records that are kept skew expensive, so their share
of credits far exceeds their share of turns -- read the record count, not the
credit share, before trusting any per-workflow attribution. Compaction, by
contrast, is recorded consistently, which makes it the usable signal. Its cost
scales with context size, so ``contextLengthBefore`` is the metric that
framework trimming has to move.

Ground truth vs estimate
------------------------
Records carry ``copilot_usage.total_nano_aiu`` -- GitHub's own computed cost in
nano AI units (1e9 nano_aiu = 1 AI credit = 0.01 USD). Where present, that value
is authoritative. Where absent, the cost is estimated from the local price table
in ``models.json``. The two are reconciled in the report, because list prices and
billed rates are not necessarily identical.

Usage:
    python analyze-copilot-usage.py                     # auto-discover storage
    python analyze-copilot-usage.py --storage <path>    # explicit chatSessions dir
    python analyze-copilot-usage.py --by-session        # per-session breakdown
    python analyze-copilot-usage.py --json              # machine-readable output
    python analyze-copilot-usage.py --baseline b.json   # snapshot for regressions

Exit codes:
    0 -- report produced
    1 -- no usage records found
    2 -- fatal error (bad arguments, storage not found)

No hook runs this: it answers a question a human asked, at a terminal, about a
store that already exists (af-caller-ok).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

NANO_AIU_PER_CREDIT = 1_000_000_000
USD_PER_CREDIT = 0.01

# Per-workflow attribution needs a usage record per turn; below that it samples.
FOREGROUND_ATTRIBUTION_DENSITY = 1.0

USAGE_MARKER = '"usage":{'

RE_TOTAL_NANO_AIU = re.compile(r'"total_nano_aiu"\s*:\s*(\d+)')
RE_MODEL = re.compile(r'"model"\s*:\s*"([^"]+)"')
RE_SOURCE = re.compile(r'"source"\s*:\s*"([^"]+)"')
RE_CONTEXT_BEFORE = re.compile(r'"contextLengthBefore"\s*:\s*(\d+)')
RE_ROUNDS_SINCE = re.compile(r'"numRoundsSinceLastSummarization"\s*:\s*(\d+)')
RE_DURATION_MS = re.compile(r'"durationMs"\s*:\s*(\d+)')
RE_TOKEN_DETAIL = re.compile(
    r'\{"batch_size":(\d+),"cost_per_batch":(\d+),'
    r'"token_count":(\d+),"token_type":"([^"]+)"\}'
)

# models.json price fields are USD/100 per 1M tokens, i.e. credits per 1M tokens.
PRICE_FIELDS = {
    "input": "input_price",
    "cache_read": "cache_price",
    "cache_write": "cache_write_price",
    "output": "output_price",
}


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------


@dataclass
class UsageRecord:
    """One billed model interaction."""

    session: str
    model: str
    source: str
    prompt_tokens: int
    cached_tokens: int
    completion_tokens: int
    reasoning_tokens: int
    nano_aiu: int | None
    context_before: int = 0
    rounds_since_summarization: int = 0
    duration_ms: int = 0
    billed_rates: dict[str, float] = field(default_factory=dict)

    @property
    def is_compaction(self) -> bool:
        """True when this record is a background context compaction."""
        return self.source == "background"

    @property
    def uncached_tokens(self) -> int:
        """Input tokens actually sent to the model, excluding cache reads."""
        return max(0, self.prompt_tokens - self.cached_tokens)

    @property
    def credits_actual(self) -> float | None:
        """Billed cost in AI credits, or None when telemetry is absent."""
        if self.nano_aiu is None:
            return None
        return self.nano_aiu / NANO_AIU_PER_CREDIT

    @property
    def identity(self) -> tuple[str, str, int, int, int, int]:
        """Key used to collapse duplicate copies of the same interaction.

        VS Code persists each response twice -- once in the response metadata and
        once in the rendered-message copy. The token counts are byte-identical,
        so counting both would double every figure in the report.
        """
        return (
            self.session,
            self.model,
            self.prompt_tokens,
            self.cached_tokens,
            self.completion_tokens,
            self.nano_aiu or 0,
        )


# ---------------------------------------------------------------------------
# Storage discovery
# ---------------------------------------------------------------------------


def _candidate_storage_roots() -> list[Path]:
    """Return plausible VS Code user-storage roots for the current platform."""
    roots: list[Path] = []
    if sys.platform == "win32":
        appdata = os.environ.get("APPDATA")
        if appdata:
            roots.append(Path(appdata) / "Code" / "User")
    elif sys.platform == "darwin":
        roots.append(Path.home() / "Library" / "Application Support" / "Code" / "User")
    else:
        roots.append(Path.home() / ".config" / "Code" / "User")
    return roots


def discover_session_dirs(explicit: str | None) -> list[Path]:
    """Find directories holding chat session JSONL files.

    Parameters
    ----------
    explicit:
        A user-supplied path. When given, it is used verbatim and no
        auto-discovery happens.

    Returns
    -------
    list[Path]
        Directories that exist and contain at least one ``.jsonl`` file.
    """
    if explicit:
        p = Path(explicit)
        return [p] if p.is_dir() else []

    found: list[Path] = []
    for root in _candidate_storage_roots():
        ws = root / "workspaceStorage"
        if not ws.is_dir():
            continue
        for child in ws.iterdir():
            sessions = child / "chatSessions"
            if sessions.is_dir() and any(sessions.glob("*.jsonl")):
                found.append(sessions)
    return found


def discover_models_json(explicit: str | None) -> Path | None:
    """Locate the newest ``models.json`` price table."""
    if explicit:
        p = Path(explicit)
        return p if p.is_file() else None

    newest: Path | None = None
    for root in _candidate_storage_roots():
        ws = root / "workspaceStorage"
        if not ws.is_dir():
            continue
        for candidate in ws.glob("*/GitHub.copilot-chat/debug-logs/**/models.json"):
            if newest is None or candidate.stat().st_mtime > newest.stat().st_mtime:
                newest = candidate
    return newest


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------


def _extract_object(text: str, brace_index: int) -> str | None:
    """Return the balanced JSON object starting at ``brace_index``.

    Returns None when the object is truncated, which happens if a session file
    was written mid-flush.
    """
    depth = 0
    in_string = False
    escaped = False
    for i in range(brace_index, len(text)):
        ch = text[i]
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[brace_index : i + 1]
    return None


def _parse_window(session: str, window: str) -> UsageRecord | None:
    """Build a UsageRecord from the text slice belonging to one usage object.

    The window must not extend into the next usage record; overlapping windows
    were the original source of misattributed models and sources.
    """
    brace = window.find("{", len(USAGE_MARKER) - 1)
    if brace < 0:
        return None
    raw = _extract_object(window, brace)
    if raw is None:
        return None
    try:
        usage = json.loads(raw)
    except json.JSONDecodeError:
        return None

    model_m = RE_MODEL.search(window)
    source_m = RE_SOURCE.search(window)
    nano_m = RE_TOTAL_NANO_AIU.search(window)
    ctx_m = RE_CONTEXT_BEFORE.search(window)
    rounds_m = RE_ROUNDS_SINCE.search(window)
    dur_m = RE_DURATION_MS.search(window)

    rates: dict[str, float] = {}
    for batch_size, cost_per_batch, _count, token_type in RE_TOKEN_DETAIL.findall(window):
        size = int(batch_size)
        if size:
            # credits per 1M tokens
            rates[token_type] = (int(cost_per_batch) / NANO_AIU_PER_CREDIT) * (1_000_000 / size)

    return UsageRecord(
        session=session,
        model=model_m.group(1) if model_m else "unknown",
        source=source_m.group(1) if source_m else "unknown",
        prompt_tokens=int(usage.get("prompt_tokens", 0)),
        cached_tokens=int(usage.get("prompt_tokens_details", {}).get("cached_tokens", 0)),
        completion_tokens=int(usage.get("completion_tokens", 0)),
        reasoning_tokens=int(usage.get("completion_tokens_details", {}).get("reasoning_tokens", 0)),
        nano_aiu=int(nano_m.group(1)) if nano_m else None,
        context_before=int(ctx_m.group(1)) if ctx_m else 0,
        rounds_since_summarization=int(rounds_m.group(1)) if rounds_m else 0,
        duration_ms=int(dur_m.group(1)) if dur_m else 0,
        billed_rates=rates,
    )


def parse_session_file(path: Path) -> list[UsageRecord]:
    """Extract every usage record from one chat session file.

    Session files hold very large single-line JSON payloads, so the file is
    streamed line by line and only the usage objects are parsed.
    """
    session = path.stem[:8]
    records: list[UsageRecord] = []
    with path.open("r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            starts = [m.start() for m in re.finditer(re.escape(USAGE_MARKER), line)]
            for i, start in enumerate(starts):
                end = starts[i + 1] if i + 1 < len(starts) else len(line)
                rec = _parse_window(session, line[start:end])
                if rec is not None:
                    records.append(rec)
    return records


def deduplicate(records: list[UsageRecord]) -> list[UsageRecord]:
    """Collapse duplicate persisted copies of the same interaction.

    When copies disagree on metadata, the one carrying a concrete ``source`` is
    kept, because the duplicate is truncated before that field.
    """
    best: dict[tuple[str, str, int, int, int, int], UsageRecord] = {}
    for rec in records:
        existing = best.get(rec.identity)
        if existing is None or (existing.source == "unknown" and rec.source != "unknown"):
            best[rec.identity] = rec
    return list(best.values())


def _percentile(values: list[int], pct: float) -> int:
    """Nearest-rank percentile of an unsorted integer list."""
    if not values:
        return 0
    ordered = sorted(values)
    rank = max(1, min(len(ordered), round(pct / 100 * len(ordered))))
    return ordered[rank - 1]


def compaction_stats(records: list[UsageRecord], table: dict[str, dict[str, float]]) -> dict[str, object]:
    """Profile context compaction, the dominant recorded cost.

    Compaction re-reads the whole conversation, so its cost scales with context
    size. ``contextLengthBefore`` is therefore the most direct measure of context
    bloat available locally, and the metric that framework trimming should move.
    """
    compactions = [r for r in records if r.is_compaction]
    if not compactions:
        return {"count": 0}

    contexts = [r.context_before for r in compactions if r.context_before > 0]
    gaps = [r.rounds_since_summarization for r in compactions if r.rounds_since_summarization > 0]

    credits = 0.0
    per_session: dict[str, dict[str, float]] = defaultdict(
        lambda: defaultdict(float)  # type: ignore[arg-type]
    )
    for rec in compactions:
        cost = rec.credits_actual
        if cost is None:
            cost = estimate_credits(rec, table) or 0.0
        credits += cost
        bucket = per_session[rec.session]
        bucket["compactions"] += 1
        bucket["credits"] += cost
        if rec.context_before > 0:
            bucket["context_sum"] += rec.context_before
            bucket["context_n"] += 1

    return {
        "count": len(compactions),
        "credits": credits,
        "credits_per_compaction": credits / len(compactions),
        "context_before_n": len(contexts),
        "context_before_mean": (sum(contexts) / len(contexts)) if contexts else 0,
        "context_before_p50": _percentile(contexts, 50),
        "context_before_p90": _percentile(contexts, 90),
        "context_before_max": max(contexts) if contexts else 0,
        "rounds_between_mean": (sum(gaps) / len(gaps)) if gaps else 0,
        "duration_ms_mean": (sum(r.duration_ms for r in compactions) / len(compactions)),
        "by_session": {k: dict(v) for k, v in per_session.items()},
    }


def load_price_table(models_json: Path | None) -> dict[str, dict[str, float]]:
    """Load list prices (credits per 1M tokens) keyed by model id."""
    if models_json is None:
        return {}
    try:
        data = json.loads(models_json.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}

    table: dict[str, dict[str, float]] = {}
    for entry in data:
        prices = (entry.get("billing") or {}).get("token_prices", {}).get("default")
        if not prices:
            continue
        table[entry.get("id", "")] = {
            kind: float(prices.get(field_name, 0) or 0) for kind, field_name in PRICE_FIELDS.items()
        }
    return table


def estimate_credits(rec: UsageRecord, table: dict[str, dict[str, float]]) -> float | None:
    """Estimate cost in credits from the local list-price table."""
    prices = table.get(rec.model)
    if not prices:
        return None
    return (
        rec.uncached_tokens * prices["input"]
        + rec.cached_tokens * prices["cache_read"]
        + rec.completion_tokens * prices["output"]
    ) / 1_000_000


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------


def _fmt(value: float) -> str:
    return f"{value:,.2f}"


def build_report(
    records: list[UsageRecord], table: dict[str, dict[str, float]], files_scanned: int = 0
) -> dict[str, object]:
    """Aggregate records into the reportable structure."""
    by_model: dict[str, dict[str, float]] = defaultdict(
        lambda: defaultdict(float)  # type: ignore[arg-type]
    )
    by_session: dict[str, dict[str, float]] = defaultdict(
        lambda: defaultdict(float)  # type: ignore[arg-type]
    )
    by_source: dict[str, dict[str, float]] = defaultdict(
        lambda: defaultdict(float)  # type: ignore[arg-type]
    )

    totals = defaultdict(float)
    rate_samples: dict[str, dict[str, float]] = {}

    for rec in records:
        actual = rec.credits_actual
        est = estimate_credits(rec, table)

        for bucket, key in ((by_model, rec.model), (by_session, rec.session), (by_source, rec.source)):
            b = bucket[key]
            b["requests"] += 1
            b["input"] += rec.uncached_tokens
            b["cached"] += rec.cached_tokens
            b["output"] += rec.completion_tokens
            b["reasoning"] += rec.reasoning_tokens
            if actual is not None:
                b["credits_actual"] += actual
                b["priced_requests"] += 1
            if est is not None:
                b["credits_estimated"] += est
            # Effective cost: billed figure when present, list-price estimate otherwise.
            effective = actual if actual is not None else est
            if effective is not None:
                b["credits_effective"] += effective
            else:
                b["unpriced_requests"] += 1

        totals["requests"] += 1
        totals["input"] += rec.uncached_tokens
        totals["cached"] += rec.cached_tokens
        totals["output"] += rec.completion_tokens
        totals["reasoning"] += rec.reasoning_tokens
        if actual is not None:
            totals["credits_actual"] += actual
            totals["priced_requests"] += 1
            if est is not None:
                totals["credits_estimated_where_actual"] += est
        if est is not None:
            totals["credits_estimated"] += est
        effective = actual if actual is not None else est
        if effective is not None:
            totals["credits_effective"] += effective
        else:
            totals["unpriced_requests"] += 1

        if rec.billed_rates and rec.model not in rate_samples:
            rate_samples[rec.model] = rec.billed_rates

    return {
        "totals": dict(totals),
        "files_scanned": files_scanned,
        "compaction": compaction_stats(records, table),
        "by_model": {k: dict(v) for k, v in by_model.items()},
        "by_session": {k: dict(v) for k, v in by_session.items()},
        "by_source": {k: dict(v) for k, v in by_source.items()},
        "billed_rates": rate_samples,
        "list_prices": {m: table[m] for m in rate_samples if m in table},
    }


def print_report(report: dict[str, object], by_session: bool) -> None:
    """Render the report as text."""
    totals = report["totals"]  # type: ignore[index]
    assert isinstance(totals, dict)

    print("=" * 78)
    print("Copilot usage report")
    print("=" * 78)
    print(f"Requests analysed          : {int(totals.get('requests', 0)):,}")
    print(f"  with billing telemetry   : {int(totals.get('priced_requests', 0)):,}")
    print(f"Input tokens (uncached)    : {int(totals.get('input', 0)):,}")
    print(f"Input tokens (cache read)  : {int(totals.get('cached', 0)):,}")
    print(f"Output tokens              : {int(totals.get('output', 0)):,}")
    print(f"  of which reasoning       : {int(totals.get('reasoning', 0)):,}")

    actual = float(totals.get("credits_actual", 0.0))
    effective = float(totals.get("credits_effective", 0.0))
    unpriced = int(totals.get("unpriced_requests", 0))
    print()
    print(f"Total cost    : {_fmt(effective)} credits  (${_fmt(effective * USD_PER_CREDIT)})")
    print(f"  billed telemetry         : {_fmt(actual)} credits")
    print(f"  list-price estimate      : {_fmt(effective - actual)} credits (no telemetry available)")
    if unpriced:
        print(f"  WARNING: {unpriced} request(s) could be neither billed nor estimated")

    paired = float(totals.get("credits_estimated_where_actual", 0.0))
    if paired > 0 and actual > 0:
        delta = (paired - actual) / actual * 100
        print()
        print(f"Reconciliation: where both exist, the list price overstates the billed cost by {delta:+.1f}%")
        print(f"  billed {_fmt(actual)} credits vs list-price {_fmt(paired)} credits")

    # foreground = real work, background = context compaction overhead
    by_source = report["by_source"]  # type: ignore[index]
    assert isinstance(by_source, dict)
    if by_source:
        print()
        print("-- By source " + "-" * 64)
        print(f"{'source':<14}{'req':>6}{'credits':>14}{'share':>9}")
        total_src = sum(float(v.get("credits_effective", 0.0)) for v in by_source.values())
        for name, vals in sorted(by_source.items(), key=lambda kv: -float(kv[1].get("credits_effective", 0.0))):
            c = float(vals.get("credits_effective", 0.0))
            share = (c / total_src * 100) if total_src else 0.0
            print(f"{name:<14}{int(vals['requests']):>6}{_fmt(c):>14}{share:>8.1f}%")

    by_model = report["by_model"]  # type: ignore[index]
    assert isinstance(by_model, dict)
    print()
    print("-- By model " + "-" * 65)
    print(f"{'model':<24}{'req':>5}{'input':>12}{'cached':>12}{'output':>11}{'credits':>11}")
    for name, vals in sorted(by_model.items(), key=lambda kv: -float(kv[1].get("credits_effective", 0.0))):
        print(
            f"{name:<24}{int(vals['requests']):>5}{int(vals['input']):>12,}"
            f"{int(vals['cached']):>12,}{int(vals['output']):>11,}"
            f"{float(vals.get('credits_effective', 0.0)):>11,.2f}"
        )

    if by_session:
        by_sess = report["by_session"]  # type: ignore[index]
        assert isinstance(by_sess, dict)
        print()
        print("-- By session " + "-" * 63)
        print(f"{'session':<12}{'req':>5}{'input':>12}{'cached':>12}{'output':>11}{'credits':>11}")
        for name, vals in sorted(by_sess.items(), key=lambda kv: -float(kv[1].get("credits_effective", 0.0))):
            print(
                f"{name:<12}{int(vals['requests']):>5}{int(vals['input']):>12,}"
                f"{int(vals['cached']):>12,}{int(vals['output']):>11,}"
                f"{float(vals.get('credits_effective', 0.0)):>11,.2f}"
            )

    rates = report["billed_rates"]  # type: ignore[index]
    lists = report["list_prices"]  # type: ignore[index]
    assert isinstance(rates, dict) and isinstance(lists, dict)
    if rates:
        print()
        print("-- Billed rate vs list price (credits per 1M tokens) " + "-" * 24)
        print(f"{'model':<24}{'kind':<12}{'billed':>10}{'list':>10}{'delta':>9}")
        for model in sorted(rates):
            for kind, billed in sorted(rates[model].items()):
                listed = lists.get(model, {}).get(kind)
                if listed:
                    delta = f"{(listed - billed) / billed * 100:+.1f}%"
                else:
                    listed, delta = 0.0, "n/a"
                print(f"{model:<24}{kind:<12}{billed:>10,.2f}{listed:>10,.2f}{delta:>9}")

    _print_compaction(report)
    _print_coverage(report)


def _print_compaction(report: dict[str, object]) -> None:
    """Render the compaction profile."""
    stats = report["compaction"]  # type: ignore[index]
    assert isinstance(stats, dict)
    if not stats.get("count"):
        return

    print()
    print("-- Compaction profile " + "-" * 55)
    print(f"Compactions                : {int(stats['count']):,}")
    print(f"Cost                       : {_fmt(float(stats['credits']))} credits")
    print(f"  per compaction           : {_fmt(float(stats['credits_per_compaction']))} credits")
    print(f"Context before compaction  : mean {int(stats['context_before_mean']):,} tok")
    print(
        f"  p50 / p90 / max          : {int(stats['context_before_p50']):,}"
        f" / {int(stats['context_before_p90']):,}"
        f" / {int(stats['context_before_max']):,} tok"
    )
    print(f"Rounds between compactions : {float(stats['rounds_between_mean']):.1f}")
    print(f"Mean duration              : {float(stats['duration_ms_mean']) / 1000:.1f} s")
    print()
    print("Context size before compaction is the regression signal: framework")
    print("trimming should lower the mean and p90, and widen the round gap.")


def _print_coverage(report: dict[str, object]) -> None:
    """Warn about the limits of the local telemetry.

    The chat session store is not a billing statement. Foreground turns are
    sampled rather than recorded per turn, so the totals describe compaction
    overhead well and total agent spend poorly. The density is measured here
    rather than asserted, because the sampling behaviour is an implementation
    detail of the Copilot Chat extension and may change.
    """
    by_source = report["by_source"]  # type: ignore[index]
    assert isinstance(by_source, dict)

    fg = int(by_source.get("foreground", {}).get("requests", 0))
    bg = int(by_source.get("background", {}).get("requests", 0))
    files = int(report.get("files_scanned", 0))  # type: ignore[arg-type]
    per_file = fg / files if files else 0.0

    print()
    print("-- Coverage " + "-" * 65)
    print(f"Session files scanned      : {files}")
    print(f"Foreground turns recorded  : {fg}  ({per_file:.2f} per session file)")
    print(f"Background summarizations  : {bg}")
    if per_file < FOREGROUND_ATTRIBUTION_DENSITY:
        print()
        print("NOTE: foreground turns are sampled, not recorded per turn -- about")
        print(f"      {per_file:.2f} record(s) per session file, where per-workflow attribution")
        print("      needs one per turn. The sampled records skew expensive, so their")
        print("      credit share overstates their share of turns. Treat the totals as")
        print("      a compaction profile; use the organisation usage export for spend.")


BASELINE_SCHEMA_VERSION = 1


def build_baseline(report: dict[str, object]) -> dict[str, object]:
    """Reduce the report to the few figures worth tracking over time.

    Deliberately excludes timestamps and session ids so two snapshots diff to
    signal rather than noise.
    """
    stats = report["compaction"]  # type: ignore[index]
    totals = report["totals"]  # type: ignore[index]
    assert isinstance(stats, dict) and isinstance(totals, dict)

    return {
        "schema_version": BASELINE_SCHEMA_VERSION,
        "compactions": int(stats.get("count", 0)),
        "compaction_credits": round(float(stats.get("credits", 0.0)), 2),
        "credits_per_compaction": round(float(stats.get("credits_per_compaction", 0.0)), 2),
        "context_before_mean": int(stats.get("context_before_mean", 0)),
        "context_before_p50": int(stats.get("context_before_p50", 0)),
        "context_before_p90": int(stats.get("context_before_p90", 0)),
        "context_before_max": int(stats.get("context_before_max", 0)),
        "rounds_between_compactions": round(float(stats.get("rounds_between_mean", 0.0)), 1),
        "tokens_input_uncached": int(totals.get("input", 0)),
        "tokens_cache_read": int(totals.get("cached", 0)),
        "tokens_output": int(totals.get("output", 0)),
    }


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    """Parse arguments, collect usage records, and print the report."""
    parser = argparse.ArgumentParser(description="Report Copilot token usage and AI credit cost.")
    parser.add_argument("--storage", help="Path to a chatSessions directory")
    parser.add_argument("--models-json", help="Path to models.json price table")
    parser.add_argument("--by-session", action="store_true", help="Include the per-session breakdown")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of text")
    parser.add_argument(
        "--baseline",
        metavar="PATH",
        help="Write a deterministic metrics snapshot for regression comparison",
    )
    args = parser.parse_args(argv)

    session_dirs = discover_session_dirs(args.storage)
    if not session_dirs:
        where = args.storage or "auto-discovered VS Code storage"
        print(f"ERROR: no chatSessions directory found ({where}).", file=sys.stderr)
        return 2

    records: list[UsageRecord] = []
    files_scanned = 0
    for directory in session_dirs:
        for path in sorted(directory.glob("*.jsonl")):
            files_scanned += 1
            records.extend(parse_session_file(path))

    if not records:
        print("ERROR: no usage records found. The telemetry shape may have changed.", file=sys.stderr)
        return 1

    records = deduplicate(records)

    table = load_price_table(discover_models_json(args.models_json))
    report = build_report(records, table, files_scanned)

    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print_report(report, args.by_session)

    if args.baseline:
        snapshot = build_baseline(report)
        Path(args.baseline).write_text(json.dumps(snapshot, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print()
        print(f"Baseline snapshot written to {args.baseline}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
