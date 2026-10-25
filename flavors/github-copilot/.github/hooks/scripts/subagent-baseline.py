"""Global SubagentStart hook core: snapshot the working tree a producer starts from (issue #101).

The record lets the producer's stop gate drop files that were already dirty when
it started and that it left untouched; see ``_baseline.py`` for why.

Advisory by construction: it answers ``{}``, never blocks, and any failure leaves
no record, which the stop gate reads as "subtract nothing".

Usage:
    subagent-baseline.py --root <deploying repo> [--code-root <active checkout>] < payload
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from _baseline import write_baseline


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--code-root", default="")
    args = parser.parse_args()
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        if isinstance(payload, dict):
            write_baseline(payload, Path(args.root), [Path(args.code_root)] if args.code_root else [])
    except (OSError, ValueError):
        pass
    print("{}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
