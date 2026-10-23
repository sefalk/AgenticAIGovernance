# Global Stop / SubagentStop hook: refresh the session cost store (issue #457).
#
# The chat debug log loses its head at a moment nobody controls, so the cost
# rows are read out as often as the session offers a chance: after every turn
# and every subagent. The collector reads only what the logs gained since its
# last run (see logs/README.md, "The session store").
#
# It runs in the background and this hook answers {} at once: no turn waits for
# it, and it never decides anything. AF_COST_SNAPSHOT_SYNC=1 runs it in the
# foreground so a test can read the store it wrote.

$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot/_common.ps1"

try {
    $hookInput = (Read-AfStdin) | ConvertFrom-Json
    $sid = [string]$hookInput.session_id
    $transcript = [string]$hookInput.transcript_path
    # The session id becomes a directory and file name; one carrying a path must not.
    if ($sid -match '^[A-Za-z0-9][A-Za-z0-9._-]*$' -and $transcript) {
        # <ws>/GitHub.copilot-chat/transcripts/<sid>.jsonl -> .../debug-logs/<sid>
        $chatDir = Split-Path -Parent (Split-Path -Parent $transcript)
        $sessionDir = Join-Path (Join-Path $chatDir 'debug-logs') $sid
        $collector = Join-Path $script:AfMainRoot '.github/scripts/collect-session-cost.py'
        $store = Join-Path $script:AfMainRoot '.github/logs/cost/sessions'

        if ($script:AfPython -and (Test-Path -LiteralPath $collector) -and (Test-Path -LiteralPath $sessionDir)) {
            $collectorArgs = @($collector, '--session-dir', $sessionDir, '--store', $store, '--snapshot')
            if ($env:AF_COST_SNAPSHOT_SYNC) {
                & $script:AfPython @collectorArgs *> $null
            } else {
                # Start-Process joins its arguments with spaces; paths with spaces need their quotes.
                $quoted = @($collectorArgs | ForEach-Object { '"' + $_ + '"' })
                Start-Process -FilePath $script:AfPython -ArgumentList $quoted -WindowStyle Hidden
            }
        }
    }
} catch {
    # Advisory: a failed refresh is retried by the next Stop.
}

Write-Output '{}'
