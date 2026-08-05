# Shared resolution preamble for AF hooks (PowerShell side).
#
# DOT-SOURCE this file, never call it:
#
#     . "$PSScriptRoot/_common.ps1"
#
# Provides:
#   $AfScriptDir   directory this file lives in
#   $AfMainRoot    checkout where .github/ is deployed
#   $AfCodeRoot    active worktree if the sentinel points at one, else MAIN
#   $AfConfPath    absolute path to .github/af-env.conf
#   $AfConfFound   $true if that file exists
#   $AfPython      an interpreter that was proven to run, or ''
#   Get-AfConfig -Key <name> [-Default <value>]
#
# Why this exists: every value is derived from this file's own location, never
# from the current working directory. `Join-Path (Get-Location) '.github/...'`
# resolves to nothing whenever the agent process is not sitting at the repo
# root, and an unread config is indistinguishable from an empty one.

$script:AfScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
$script:AfMainRoot = Split-Path (Split-Path (Split-Path $script:AfScriptDir))

$script:AfCodeRoot = $script:AfMainRoot
$afSentinel = Join-Path $script:AfMainRoot '.github/.active-worktree'
if (Test-Path $afSentinel) {
    $afWt = (Get-Content $afSentinel -Raw -ErrorAction SilentlyContinue)
    if ($afWt) { $afWt = $afWt.Trim() }
    if ($afWt -and (Test-Path $afWt)) { $script:AfCodeRoot = $afWt }
}

$script:AfConfPath = Join-Path $script:AfMainRoot '.github/af-env.conf'
$script:AfConfFound = Test-Path $script:AfConfPath

function Get-AfConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [string]$Default = ''
    )
    if (-not $script:AfConfFound) { return $Default }
    $pattern = '^{0}=(.+)$' -f [regex]::Escape($Key)
    $m = Select-String -Path $script:AfConfPath -Pattern $pattern -ErrorAction SilentlyContinue
    if ($m) {
        $v = $m.Matches[0].Groups[1].Value.Trim()
        if ($v) { return $v }
    }
    return $Default
}

# A resolvable interpreter is not a working one: on Windows `python3` is an
# App Execution Alias that is on PATH, runs nothing and exits non-zero.
# Probe each candidate instead of trusting the lookup.
function Find-AfPython {
    foreach ($candidate in @($env:AF_PYTHON_OVERRIDE, 'python3', 'python', 'py')) {
        if (-not $candidate) { continue }
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if (-not $cmd -or -not $cmd.Source) { continue }
        & $cmd.Source -c '' *> $null
        if ($LASTEXITCODE -eq 0) { return $cmd.Source }
    }
    return ''
}

$script:AfPython = Find-AfPython
