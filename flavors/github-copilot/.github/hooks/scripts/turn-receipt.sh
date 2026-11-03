#!/usr/bin/env bash
# Global Stop hook: name this turn's NOT RUN, block, deny and error verdicts under the answer (issue #478).
#
# Thin dialect wrapper (issue #287). Reading the hook log and choosing what to
# report live in turn-receipt.py. Everything here is interpreter resolution and
# stdin marshalling.

set -uo pipefail

_af_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$_af_dir/_common.sh"

_af_core="$_af_dir/turn-receipt.py"

if [ -z "${AF_PYTHON:-}" ] || [ ! -f "$_af_core" ]; then
    # Advisory: no interpreter, no receipt; the verdicts stay in their subagent blocks.
    echo '{}'
    exit 0
fi

exec "$AF_PYTHON" "$_af_core"
