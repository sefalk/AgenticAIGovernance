# Hook Integration Tests
# copilot:generated | implementer | 2026-04-01
#
# Exercises each Copilot agent hook with crafted JSON inputs and verifies
# the expected output (deny, ask, allow, or specific JSON fields).
#
# Usage:
#   .github/scripts/test-hooks.ps1              # Run all tests
#   .github/scripts/test-hooks.ps1 -Verbose     # Show pass detail
#
# Exit codes: 0 = all passed, 1 = failures

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'
$scriptDir = Join-Path (Resolve-Path "$PSScriptRoot/..").Path 'hooks/scripts'

if (-not (Test-Path $scriptDir)) {
    Write-Output "ERROR: hooks/scripts not found at $scriptDir"
    exit 1
}

# ── Test harness ─────────────────────────────────────────────────────────

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Invoke-Hook {
    param(
        [string]$Script,
        [string]$JsonInput
    )
    $hookPath = Join-Path $scriptDir $Script
    if (-not (Test-Path $hookPath)) {
        throw "Hook not found: $hookPath"
    }
    # Pipe JSON to the hook script via stdin
    $output = $JsonInput | powershell -NoProfile -ExecutionPolicy Bypass -File $hookPath 2>&1
    $exitCode = $LASTEXITCODE
    # Parse output
    $text = ($output | Out-String).Trim()
    return @{ Output = $text; ExitCode = $exitCode }
}

function Assert-Deny {
    param([string]$TestName, [string]$Script, [string]$Json)
    try {
        $result = Invoke-Hook -Script $Script -JsonInput $Json
        $parsed = $result.Output | ConvertFrom-Json -ErrorAction SilentlyContinue
        $decision = $parsed.hookSpecificOutput.permissionDecision
        if ($decision -eq 'deny') {
            $script:passed++
            if ($Verbose) { Write-Output "  PASS  $TestName" }
        } else {
            $script:failed++
            $script:errors += "FAIL  $TestName -- expected deny, got '$decision' (output: $($result.Output))"
        }
    } catch {
        $script:failed++
        $script:errors += "ERROR $TestName -- $($_.Exception.Message)"
    }
}

function Assert-Ask {
    param([string]$TestName, [string]$Script, [string]$Json)
    try {
        $result = Invoke-Hook -Script $Script -JsonInput $Json
        $parsed = $result.Output | ConvertFrom-Json -ErrorAction SilentlyContinue
        $decision = $parsed.hookSpecificOutput.permissionDecision
        if ($decision -eq 'ask') {
            $script:passed++
            if ($Verbose) { Write-Output "  PASS  $TestName" }
        } else {
            $script:failed++
            $script:errors += "FAIL  $TestName -- expected ask, got '$decision' (output: $($result.Output))"
        }
    } catch {
        $script:failed++
        $script:errors += "ERROR $TestName -- $($_.Exception.Message)"
    }
}

function Assert-Allow {
    param([string]$TestName, [string]$Script, [string]$Json)
    try {
        $result = Invoke-Hook -Script $Script -JsonInput $Json
        $text = $result.Output
        # Allow = empty JSON or no hookSpecificOutput or no permissionDecision
        $isAllow = ($text -eq '{}' -or $text -eq '' -or $null -eq $text)
        if (-not $isAllow) {
            $parsed = $text | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($parsed -and $parsed.hookSpecificOutput -and $parsed.hookSpecificOutput.permissionDecision) {
                $decision = $parsed.hookSpecificOutput.permissionDecision
                $isAllow = ($decision -notin @('deny', 'ask'))
            } else {
                $isAllow = $true
            }
        }
        if ($isAllow) {
            $script:passed++
            if ($Verbose) { Write-Output "  PASS  $TestName" }
        } else {
            $script:failed++
            $script:errors += "FAIL  $TestName -- expected allow, got: $text"
        }
    } catch {
        $script:failed++
        $script:errors += "ERROR $TestName -- $($_.Exception.Message)"
    }
}

function Assert-ExitCode {
    param([string]$TestName, [string]$Script, [string]$Json, [int]$Expected)
    try {
        $result = Invoke-Hook -Script $Script -JsonInput $Json
        if ($result.ExitCode -eq $Expected) {
            $script:passed++
            if ($Verbose) { Write-Output "  PASS  $TestName" }
        } else {
            $script:failed++
            $script:errors += "FAIL  $TestName -- expected exit $Expected, got $($result.ExitCode) (output: $($result.Output))"
        }
    } catch {
        $script:failed++
        $script:errors += "ERROR $TestName -- $($_.Exception.Message)"
    }
}

Write-Output "=== Hook Integration Tests ==="
Write-Output ""

# ── 1. block-dangerous.ps1 ──────────────────────────────────────────────

Write-Output "## block-dangerous.ps1"

# Should ASK for dangerous commands
Assert-Ask "git push triggers ask" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git push origin main"}}'

Assert-Ask "git merge triggers ask" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git merge feature"}}'

Assert-Ask "git rebase triggers ask" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git rebase main"}}'

Assert-Ask "git reset --hard triggers ask" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git reset --hard HEAD~1"}}'

Assert-Ask "rm -rf triggers ask" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"rm -rf /tmp/data"}}'

Assert-Ask "Remove-Item -Recurse triggers ask" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"Remove-Item ./build -Recurse"}}'

Assert-Ask "git branch -D triggers ask" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git branch -D old-branch"}}'

Assert-Ask "--no-verify triggers ask" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git commit --no-verify -m test"}}'

Assert-Ask "git add . triggers ask" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git add ."}}'

Assert-Ask "git add -A triggers ask" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git add -A"}}'

# Should ALLOW safe commands
Assert-Allow "git status is safe" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git status"}}'

Assert-Allow "git diff is safe" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git diff --stat"}}'

Assert-Allow "git add specific file is safe" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git add src/main.py"}}'

Assert-Allow "git commit is safe" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git commit -m \"fix: typo\""}}'

Assert-Allow "non-terminal tool ignored" `
    "block-dangerous.ps1" `
    '{"tool_name":"readFile","tool_input":{"filePath":"src/main.py"}}'

Write-Output ""

# ── 2. coordinator-pretooluse.ps1 ────────────────────────────────────────

Write-Output "## coordinator-pretooluse.ps1"

# Should DENY file modification
Assert-Deny "coordinator cannot editFiles" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"editFiles","tool_input":{"filePath":"src/main.py"}}'

Assert-Deny "coordinator cannot createFile" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"createFile","tool_input":{"filePath":"src/new.py"}}'

# Should ALLOW read/search/terminal
Assert-Allow "coordinator can readFile" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"readFile","tool_input":{"filePath":"src/main.py"}}'

Assert-Allow "coordinator can searchCodebase" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"searchCodebase","tool_input":{"query":"hello"}}'

Assert-Allow "coordinator can listDirectory" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"listDirectory","tool_input":{"path":"src/"}}'

Assert-Allow "coordinator can runInTerminal" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git status"}}'

Assert-Allow "coordinator can getProblems" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"problems","tool_input":{}}'

Write-Output ""

# ── 3. test-writer-pretooluse.ps1 ────────────────────────────────────────

Write-Output "## test-writer-pretooluse.ps1"

# Read SRC_DIR from af-env.conf (or default 'src')
$srcDir = 'src'
$confPath = Join-Path (Get-Location) '.github/af-env.conf'
if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^SRC_DIR=(.+)$'
    if ($m) { $srcDir = $m.Matches[0].Groups[1].Value.Trim() }
}
$absSrcDir = (Resolve-Path $srcDir -ErrorAction SilentlyContinue).Path
if (-not $absSrcDir) { $absSrcDir = Join-Path (Get-Location) $srcDir }

# Should DENY edits to production code
$prodFile = Join-Path $absSrcDir 'main.py'
$prodJson = @{ tool_name = "editFiles"; tool_input = @{ filePath = $prodFile } } | ConvertTo-Json -Compress
Assert-Deny "test-writer cannot edit production code" `
    "test-writer-pretooluse.ps1" $prodJson

$prodCreate = @{ tool_name = "createFile"; tool_input = @{ filePath = (Join-Path $absSrcDir 'new_module.py') } } | ConvertTo-Json -Compress
Assert-Deny "test-writer cannot create production file" `
    "test-writer-pretooluse.ps1" $prodCreate

# Should ALLOW test file edits
$testJson = @{ tool_name = "editFiles"; tool_input = @{ filePath = (Join-Path (Get-Location) "tests/test_example.py") } } | ConvertTo-Json -Compress
Assert-Allow "test-writer can edit test files" `
    "test-writer-pretooluse.ps1" $testJson

$testCreate = @{ tool_name = "createFile"; tool_input = @{ filePath = (Join-Path (Get-Location) "tests/test_new.py") } } | ConvertTo-Json -Compress
Assert-Allow "test-writer can create test files" `
    "test-writer-pretooluse.ps1" $testCreate

# Should ALLOW read tools
Assert-Allow "test-writer can readFile" `
    "test-writer-pretooluse.ps1" `
    '{"tool_name":"readFile","tool_input":{"filePath":"src/main.py"}}'

Write-Output ""

# ── 4. refactorer-pretooluse.ps1 ─────────────────────────────────────────

Write-Output "## refactorer-pretooluse.ps1"

# Should DENY file/directory creation
Assert-Deny "refactorer cannot createFile" `
    "refactorer-pretooluse.ps1" `
    '{"tool_name":"createFile","tool_input":{"filePath":"src/new.py"}}'

Assert-Deny "refactorer cannot createDirectory" `
    "refactorer-pretooluse.ps1" `
    '{"tool_name":"createDirectory","tool_input":{"path":"src/new_dir/"}}'

# Should ALLOW edits to existing files
Assert-Allow "refactorer can editFiles" `
    "refactorer-pretooluse.ps1" `
    '{"tool_name":"editFiles","tool_input":{"filePath":"src/main.py"}}'

Assert-Allow "refactorer can readFile" `
    "refactorer-pretooluse.ps1" `
    '{"tool_name":"readFile","tool_input":{"filePath":"src/main.py"}}'

# createAndRunTask is not a file creation
Assert-Allow "refactorer can createAndRunTask" `
    "refactorer-pretooluse.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"label":"test"}}'

Write-Output ""

# ── 5. researcher-pretooluse.ps1 ─────────────────────────────────────────

Write-Output "## researcher-pretooluse.ps1"

# Should WARN (but allow) URLs with credentials
Assert-Allow "clean URL is allowed" `
    "researcher-pretooluse.ps1" `
    '{"tool_name":"fetch","tool_input":{"url":"https://docs.python.org/3/"}}'

# Credential URL -- hook warns but still exits 0, so it's "allow" with advisory output
Assert-ExitCode "credential URL exits 0 (advisory)" `
    "researcher-pretooluse.ps1" `
    '{"tool_name":"fetch","tool_input":{"url":"https://user:pass@example.com/api"}}' `
    0

Assert-Allow "non-fetch tool ignored" `
    "researcher-pretooluse.ps1" `
    '{"tool_name":"readFile","tool_input":{"filePath":"src/main.py"}}'

Write-Output ""

# ── 6. scan-secrets.ps1 ─────────────────────────────────────────────────

Write-Output "## scan-secrets.ps1"

# Create a temp file with a secret pattern for testing
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "hook-test-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$secretFile = Join-Path $tempDir "secret.py"
Set-Content -Path $secretFile -Value 'password = "SuperSecret123!"'

$cleanFile = Join-Path $tempDir "clean.py"
Set-Content -Path $cleanFile -Value "# copilot:generated | implementer | 2026-04-01`ndef hello(): pass"

$secretJson = @{ tool_name = "editFiles"; tool_input = @{ filePath = $secretFile } } | ConvertTo-Json -Compress
Assert-ExitCode "secret pattern detected (exit 1)" `
    "scan-secrets.ps1" $secretJson 1

$cleanJson = @{ tool_name = "editFiles"; tool_input = @{ filePath = $cleanFile } } | ConvertTo-Json -Compress
Assert-ExitCode "clean file passes (exit 0)" `
    "scan-secrets.ps1" $cleanJson 0

# Non-edit tool should be ignored
Assert-Allow "non-edit tool ignored" `
    "scan-secrets.ps1" `
    '{"tool_name":"readFile","tool_input":{"filePath":"src/main.py"}}'

# Cleanup
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Output ""

# ── 7. Edge cases ────────────────────────────────────────────────────────

Write-Output "## Edge cases"

# Empty/invalid JSON should not crash any hook
$hooks = @(
    'block-dangerous.ps1',
    'coordinator-pretooluse.ps1',
    'test-writer-pretooluse.ps1',
    'refactorer-pretooluse.ps1',
    'researcher-pretooluse.ps1'
)
foreach ($hook in $hooks) {
    Assert-ExitCode "$hook handles empty input gracefully" `
        $hook '' 0
    Assert-ExitCode "$hook handles malformed JSON gracefully" `
        $hook 'not-json' 0
}

Write-Output ""

# ── 8. Trace telemetry verification ──────────────────────────────────────

Write-Output "## Trace telemetry (hook-utils.ps1)"

# The hooks that made deny/ask/block/warn decisions should have written
# trace entries to .github/logs/hook-trace.jsonl. Verify the file exists
# and contains expected hook names.

$tracePath = Join-Path (Get-Location) '.github/logs/hook-trace.jsonl'
if (Test-Path $tracePath) {
    $traceLines = Get-Content $tracePath
    $traceHooks = $traceLines | ForEach-Object {
        try { ($_ | ConvertFrom-Json).hook } catch {}
    } | Sort-Object -Unique

    $expectedHooks = @(
        'block-dangerous',
        'coordinator-pretooluse',
        'test-writer-pretooluse',
        'refactorer-pretooluse',
        'scan-secrets'
    )

    foreach ($h in $expectedHooks) {
        if ($h -in $traceHooks) {
            $script:passed++
            if ($Verbose) { Write-Output "  PASS  trace: $h wrote to hook-trace.jsonl" }
        } else {
            $script:failed++
            $script:errors += "FAIL  trace: $h missing from hook-trace.jsonl"
        }
    }

    # Verify trace entries are valid JSON
    $invalidCount = 0
    foreach ($line in $traceLines) {
        try { $null = $line | ConvertFrom-Json } catch { $invalidCount++ }
    }
    if ($invalidCount -eq 0) {
        $script:passed++
        if ($Verbose) { Write-Output "  PASS  trace: all $($traceLines.Count) entries are valid JSON" }
    } else {
        $script:failed++
        $script:errors += "FAIL  trace: $invalidCount invalid JSON lines in hook-trace.jsonl"
    }

    # Clean up trace file after test (it's a test artifact)
    Remove-Item $tracePath -Force -ErrorAction SilentlyContinue
} else {
    $script:failed++
    $script:errors += "FAIL  trace: hook-trace.jsonl was not created -- hooks may not be writing traces"
}

Write-Output ""

# ── Summary ──────────────────────────────────────────────────────────────

Write-Output "=== Summary ==="
Write-Output "  Passed: $($script:passed)"
Write-Output "  Failed: $($script:failed)"

if ($script:errors.Count -gt 0) {
    Write-Output ""
    Write-Output "  Failures:"
    foreach ($err in $script:errors) {
        Write-Output "    $err"
    }
    Write-Output ""
    exit 1
} else {
    Write-Output "  All hook tests passed."
    exit 0
}
