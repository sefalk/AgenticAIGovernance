#!/usr/bin/env python3
"""Are the tier models ones Copilot actually serves? (#421)

VS Code greys out an unknown `model:` entry ("Unknown model ... will be
ignored") but reports it as neither error nor warning, so no agent sees it, and
a tier whose every entry is unknown silently falls back to the picker model.

Copilot Chat writes its `/models` catalogue to `models.json` in each debug-log
session directory (needs `github.copilot.chat.agentDebugLog.fileLogging.enabled`).
This compares the effective tier lists -- the project's `AF_MODEL_TIER_*`
override, else the framework's `AF_MODEL_DEFAULT_*` (#418) -- against the newest
copy. The catalogue is a snapshot from the last time Copilot Chat loaded it, so
"unknown" is a finding and "known" is not a guarantee; its age is always shown.

Exit: 0 all known, 1 unknown model(s), 2 no catalogue (not checked -- never a pass).
Stdlib only.
"""

# copilot:generated | coordinator | 2026-10-20

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import sys
import time
from pathlib import Path

TIERS = ("PREMIUM", "BALANCED", "EFFICIENT")
VENDOR = re.compile(r"\s*\([^()]*\)\s*$")


def _env_value(path: Path | None, key: str) -> str:
    if path is None or not path.is_file():
        return ""
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith(key + "="):
            return line.split("=", 1)[1].strip()
    return ""


def tier_models(source_env: Path | None, target_env: Path | None) -> dict[str, list[str]]:
    out = {}
    for tier in TIERS:
        raw = _env_value(target_env, f"AF_MODEL_TIER_{tier}") or _env_value(source_env, f"AF_MODEL_DEFAULT_{tier}")
        out[tier] = [m.strip() for m in raw.split(",") if m.strip()]
    return out


def discover_catalogue() -> Path | None:
    """The newest models.json, found the way the cost analysis finds it."""
    explicit = os.environ.get("AF_MODELS_JSON")
    if explicit:
        return Path(explicit)
    here = Path(__file__).resolve().parent / "analyze-copilot-usage.py"
    spec = importlib.util.spec_from_file_location("analyze_copilot_usage", here)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    # @dataclass in that module looks itself up in sys.modules.
    sys.modules[spec.name] = module
    try:
        spec.loader.exec_module(module)
    except (OSError, ImportError, SyntaxError, AttributeError):
        return None
    return module.discover_models_json(None)


def catalogue_names(path: Path) -> set[str]:
    entries = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(entries, dict):
        entries = entries.get("data", [])
    return {
        e["name"]
        for e in entries
        if isinstance(e, dict)
        and isinstance(e.get("name"), str)
        and (e.get("capabilities") or {}).get("type") == "chat"
    }


def check(source_env: Path | None, target_env: Path | None, models_json: Path | None) -> tuple[int, list[str]]:
    if models_json is None or not models_json.is_file():
        return 2, [
            "  NOTE    tier models not checked -- no Copilot models.json found"
            " (enable github.copilot.chat.agentDebugLog.fileLogging.enabled)"
        ]
    try:
        known = catalogue_names(models_json)
    except (OSError, ValueError):
        return 2, [f"  NOTE    tier models not checked -- unreadable catalogue {models_json}"]
    age_h = (time.time() - models_json.stat().st_mtime) / 3600
    source = f"catalogue {models_json} ({age_h:.0f} h old)"
    lines = [
        f"  WARN    unknown model '{model}' in tier {tier} -- Copilot will ignore it"
        for tier, models in tier_models(source_env, target_env).items()
        for model in models
        if VENDOR.sub("", model) not in known
    ]
    if lines:
        return 1, [*lines, f"          {source}"]
    return 0, [f"  OK      every tier model is in the {source}"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source-env", type=Path, help="framework af-env.conf (AF_MODEL_DEFAULT_*)")
    parser.add_argument("--target-env", type=Path, help="project af-env.conf (AF_MODEL_TIER_*)")
    parser.add_argument("--models-json", type=Path, help="catalogue; default: $AF_MODELS_JSON, else the newest copy")
    args = parser.parse_args()
    code, lines = check(args.source_env, args.target_env, args.models_json or discover_catalogue())
    print("\n".join(lines))
    return code


if __name__ == "__main__":
    sys.exit(main())
