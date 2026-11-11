"""Measured context fill of the coordinator, for the context budget (#519).

The budget used to count subagent calls, because tokens were "not directly
measurable". The session's debug log records them: every coordinator request
(`debugName` `panel/*`) carries `inputTokens` (cached included), and the
session's `models.json` gives each model's `max_prompt_tokens`. Fill is the
latest of those over the other. Calibrated on 14 local sessions (#519): the
harness compacted at 17-26 % or 84-88 % of the cap, and sessions ran healthy
at 55-71 %, hence 50 / 75. A prompt that shrank by more than half since the
previous request was compacted. Advisory: any failure is None, and the
coordinator then counts calls (#518).
"""

from __future__ import annotations

import json
import os
from pathlib import Path

FILL_DEFAULTS = {"AF_CONTEXT_YELLOW_FILL_PCT": "50", "AF_CONTEXT_RED_FILL_PCT": "75"}
TAIL_BYTES = 4_000_000
DROP = 0.5


def _fill_config() -> dict[str, int]:
    conf = os.environ.get("AF_CONF_PATH") or str(Path(__file__).resolve().parents[2] / "af-env.conf")
    values = dict(FILL_DEFAULTS)
    try:
        with open(conf, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                key, sep, value = line.strip().partition("=")
                if sep and key in values and value.strip():
                    values[key] = value.strip()
    except OSError:
        pass
    out = {}
    for key, default in FILL_DEFAULTS.items():
        try:
            out[key] = int(values[key])
        except ValueError:
            out[key] = int(default)
    return out


def _caps(session_dir: Path) -> dict[str, int]:
    models = json.loads((session_dir / "models.json").read_text(encoding="utf-8"))
    caps = {}
    for model in models if isinstance(models, list) else []:
        limit = (
            ((model.get("capabilities") or {}).get("limits") or {}).get("max_prompt_tokens")
            if isinstance(model, dict)
            else None
        )
        if model.get("id") and isinstance(limit, int) and limit > 0:
            caps[str(model["id"])] = limit
    return caps


def _coordinator_requests(main_log: Path) -> list[tuple[int, str]]:
    """(prompt tokens, model) of the coordinator's own requests, oldest first, from the log's tail."""
    with main_log.open("rb") as handle:
        handle.seek(max(0, main_log.stat().st_size - TAIL_BYTES))
        lines = handle.read().splitlines()
    points = []
    for line in lines:
        if b'"llm_request"' not in line:
            continue
        try:
            event = json.loads(line)
        except ValueError:
            continue
        attrs = event.get("attrs") or {}
        if event.get("type") != "llm_request" or not str(attrs.get("debugName") or "").startswith("panel/"):
            continue
        if isinstance(attrs.get("inputTokens"), int) and attrs.get("model"):
            points.append((attrs["inputTokens"], str(attrs["model"])))
    return points


def context_line(session_dir: Path) -> str | None:
    """`Context budget (#519): GREEN|YELLOW|RED · fill NN % ...`, or None when it cannot be measured."""
    try:
        caps = _caps(session_dir)
        points = _coordinator_requests(session_dir / "main.jsonl")
    except (OSError, ValueError, AttributeError):
        return None
    if not points or points[-1][1] not in caps:
        return None
    tokens, model = points[-1]
    cap = caps[model]
    fill = round(100 * tokens / cap)
    conf = _fill_config()
    state = (
        "RED"
        if fill >= conf["AF_CONTEXT_RED_FILL_PCT"]
        else "YELLOW"
        if fill >= conf["AF_CONTEXT_YELLOW_FILL_PCT"]
        else "GREEN"
    )
    line = f"Context budget (#519): {state} · fill {fill} % of {model} max_prompt_tokens {cap} (measured)"
    if len(points) > 1 and tokens < points[-2][0] * (1 - DROP):
        before = points[-2][0]
        line += f"; the harness compacted the conversation ({before} -> {tokens} tokens), earlier turns are a summary"
    return line
