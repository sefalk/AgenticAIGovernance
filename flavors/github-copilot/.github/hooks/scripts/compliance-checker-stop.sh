#!/usr/bin/env bash
# Agent-scoped SubagentStop hook for the compliance-checker (issue #286).
#
# Thin dialect wrapper (issue #287). The gate -- a report quoting `path:line`
# with no read_file call behind it is blocked -- lives in
# compliance-checker-stop.py. Everything here is interpreter resolution and
# stdin marshalling.

set -uo pipefail

_af_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$_af_dir/_common.sh"

_af_core="$_af_dir/compliance-checker-stop.py"

if [ -z "${AF_PYTHON:-}" ] || [ ! -f "$_af_core" ]; then
    # Unmeasured, said out loud: silence would read as a verified report.
    echo '{"systemMessage":"compliance-checker:Stop -- read check not measurable (no Python interpreter or compliance-checker-stop.py missing); quotations are unverified, not verified"}'
    exit 0
fi

exec "$AF_PYTHON" "$_af_core"
