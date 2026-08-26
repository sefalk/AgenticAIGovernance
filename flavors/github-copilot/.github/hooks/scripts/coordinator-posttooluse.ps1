# Agent-scoped PostToolUse hook for the coordinator agent.
#
# TERMINAL FILE-WRITE DETECTOR (detective -- warns when terminal modifies source files)
#
# The coordinator has runInTerminal access (needed for git status, branch checks).
# This hook fires AFTER terminal commands and checks whether source files
# (SRC_DIR/, tests/) were modified -- catching indirect file writes via
# echo >, Set-Content, sed -i, python -c, etc.
#
# This is a detective control (cannot undo the action), complementing the
# preventative PreToolUse hook that blocks edit/create tools.
#
# Fires only when the coordinator agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'

# Worktree-aware path resolution (see ideas/feature-git-worktrees.md §12).
$mainRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot))
$codeRoot = $mainRoot
$sentinel = Join-Path $mainRoot '.github/.active-worktree'
if (Test-Path $sentinel) {
    $p = (Get-Content $sentinel -Raw -ErrorAction SilentlyContinue).Trim()
    if ($p -and (Test-Path $p)) { $codeRoot = $p }
}

# Load project config
$SRC_DIR = 'src'
$confPath = Join-Path $mainRoot '.github/af-env.conf'
if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^SRC_DIR=(.+)$'
    if ($m) { $SRC_DIR = $m.Matches[0].Groups[1].Value.Trim() }
}

# Read and parse stdin
$raw = [Console]::In.ReadToEnd()
try {
    $inputData = $raw | ConvertFrom-Json
} catch {
    Write-Output '{}'
    exit 0
}

# Only inspect terminal tool calls
$toolName = $inputData.tool_name
if ($toolName -notmatch 'terminal|Terminal|runInTerminal') {
    Write-Output '{}'
    exit 0
}

# Attribution, not presence. PreToolUse leaves a baseline of what was already
# dirty, so only what appeared since is attributable to this call (#172).
# No baseline means no evidence -- and a guard that accuses without evidence is
# the defect this replaced, so it stays silent instead.
$gitDir = git -C $codeRoot rev-parse --absolute-git-dir 2>$null | Select-Object -First 1
if (-not $gitDir -or -not (Test-Path -LiteralPath $gitDir)) {
    Write-Output '{}'
    exit 0
}
$snapshot = Join-Path $gitDir 'af-delegation.snapshot'
if (-not (Test-Path -LiteralPath $snapshot)) {
    Write-Output '{}'
    exit 0
}
$baseline = @{}
foreach ($line in (Get-Content -LiteralPath $snapshot)) {
    if ($line -match '\S') { $baseline[$line.TrimEnd()] = $true }
}
Remove-Item -LiteralPath $snapshot -Force

# Check for modified/new files in source directories (fast -- scoped to two dirs)
$status = git -C $codeRoot status --porcelain -- "$SRC_DIR/" tests/ 2>&1
if (-not $status -or $status.Length -eq 0) {
    Write-Output '{}'
    exit 0
}

# Keep only entries the baseline did not already contain. Comparing the whole
# porcelain line, not just the path, so a staged/unstaged transition still counts.
$changedFiles = @($status -split "`n" |
    Where-Object { $_ -match '\S' } |
    ForEach-Object { $_.TrimEnd() } |
    Where-Object { -not $baseline.ContainsKey($_) } |
    ForEach-Object { ($_ -replace '^\s*\S+\s+', '').Trim() } |
    Select-Object -First 10)

if ($changedFiles.Count -eq 0) {
    Write-Output '{}'
    exit 0
}

$fileList = $changedFiles -join ', '
$warning = "DELEGATION VIOLATION DETECTED: $($changedFiles.Count) source file(s) changed while " +
    "this terminal call ran: $fileList. " +
    "Cardinal Rule 1 requires the coordinator to delegate file modifications to subagents. " +
    "Delegate the change and let the subagent redo it. " +
    "Do not discard uncommitted work to clear this warning."

@{
    hookSpecificOutput = @{
        additionalContext = $warning
    }
} | ConvertTo-Json -Depth 3 -Compress
exit 0
