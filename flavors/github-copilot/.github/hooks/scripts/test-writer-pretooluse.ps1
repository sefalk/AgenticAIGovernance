# Agent-scoped PreToolUse hook for the test-writer agent.
#
# TDD PHASE ISOLATION (HARD -- blocks test-writer from editing production code)
#
# The Red phase must only create/edit test files. If the test-writer modifies
# production code under SRC_DIR/, the tests may pass immediately and the
# Green phase becomes a no-op -- violating the most fundamental TDD invariant.
#
# Fires only when the test-writer agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'

# Load project config
$SRC_DIR = 'src'
$confPath = Join-Path (Get-Location) '.github/af-env.conf'
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

# Only inspect file-modifying tools
$toolName = $inputData.tool_name
if ($toolName -notmatch 'edit|create|write|file') {
    Write-Output '{}'
    exit 0
}

# Extract the file path from tool input
$filePath = $inputData.tool_input.filePath
if (-not $filePath) {
    # Try alternate property names
    $filePath = $inputData.tool_input.path
}
if (-not $filePath) {
    Write-Output '{}'
    exit 0
}

# Resolve to absolute path and check against production source directory
try {
    $resolved = [System.IO.Path]::GetFullPath($filePath)
    $prodRoot = [System.IO.Path]::GetFullPath($SRC_DIR)

    if ($resolved.StartsWith($prodRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        @{
            hookSpecificOutput = @{
                hookEventName      = 'PreToolUse'
                permissionDecision = 'deny'
                permissionDecisionReason = "TDD phase isolation: test-writer cannot modify production code under $SRC_DIR/. Only test files should be created or edited during the Red phase."
            }
        } | ConvertTo-Json -Depth 3 -Compress
        exit 0
    }
} catch {
    # Path resolution failed -- allow (don't block on parse errors)
    Write-Output '{}'
    exit 0
}

# Not a production file -- allow
Write-Output '{}'
