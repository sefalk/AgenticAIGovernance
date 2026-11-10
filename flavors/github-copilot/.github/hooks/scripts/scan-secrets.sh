#!/usr/bin/env bash
# PostToolUse hook: scan edited files for hardcoded secrets.
#
# Thin dialect wrapper (issue #287). The gate itself lives in scan-secrets.py,
# so the two shells have nothing left to disagree about. Everything here is
# interpreter resolution and stdin marshalling.

set -uo pipefail

# Root, config and interpreter come from this script's location, never from
# the cwd the agent happens to run in (issue #54).
_af_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# A call with nothing to scan, record or announce skips Python (#515).
# Without the helper the full path runs: a missing file must not silence the scan.
_af_raw=$(cat)
if [ -f "$_af_dir/_fastpath.sh" ]; then
    . "$_af_dir/_fastpath.sh"
    if af_scan_skippable "$_af_raw"; then echo '{}'; exit 0; fi
fi

. "$_af_dir/_common.sh"

_af_core="$_af_dir/scan-secrets.py"

if [ -z "${AF_PYTHON:-}" ] || [ ! -f "$_af_core" ]; then
    # Loud rather than silent: this branch used to print '{}' and exit 0,
    # which switched the secret gate off without saying so.
    echo '{"gate":"secret-scan","status":"WARN","detail":"Secret scanning did not run: no working Python interpreter was found (tried AF_PYTHON_OVERRIDE, python3, python, py), or scan-secrets.py is missing. Install Python 3 or set AF_PYTHON_OVERRIDE."}'
    exit 0
fi

printf '%s' "$_af_raw" | exec "$AF_PYTHON" "$_af_core"
