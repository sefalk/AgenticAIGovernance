#!/usr/bin/env bash
# Global SubagentStart hook: snapshot the working tree a producer starts from (issue #101).
#
# Thin dialect wrapper (issue #287). Which agents are recorded, what is
# snapshotted and where it is stored live in subagent-baseline.py / _baseline.py.
# Everything here is interpreter resolution and stdin marshalling.

set -uo pipefail

_af_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$_af_dir/_common.sh"

_af_core="$_af_dir/subagent-baseline.py"

if [ -z "${AF_PYTHON:-}" ] || [ ! -f "$_af_core" ]; then
    # Advisory: no record means the stop gate subtracts nothing.
    echo '{}'
    exit 0
fi

exec "$AF_PYTHON" "$_af_core" --root "$AF_MAIN_ROOT" --code-root "$AF_CODE_ROOT"
