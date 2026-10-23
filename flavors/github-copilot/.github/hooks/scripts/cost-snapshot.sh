#!/usr/bin/env bash
# Global Stop / SubagentStop hook: refresh the session cost store (issue #457).
#
# Thin dialect wrapper (issue #287). Locating the session log and starting the
# collector in the background live in cost-snapshot.py. Everything here is
# interpreter resolution and stdin marshalling.

set -uo pipefail

_af_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$_af_dir/_common.sh"

_af_core="$_af_dir/cost-snapshot.py"

if [ -z "${AF_PYTHON:-}" ] || [ ! -f "$_af_core" ]; then
    # Advisory: no interpreter, no refresh; the documenter run still reads the log.
    echo '{}'
    exit 0
fi

exec "$AF_PYTHON" "$_af_core"
