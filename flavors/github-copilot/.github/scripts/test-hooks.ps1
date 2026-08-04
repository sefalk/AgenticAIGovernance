# Hook Integration Tests
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
$githubDir = (Resolve-Path "$PSScriptRoot/..").Path
$scriptDir = Join-Path $githubDir 'hooks/scripts'

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
        [string]$JsonInput,
        [string]$Branch,
        [switch]$Detached
    )
    $hookPath = Join-Path $scriptDir $Script
    if (-not (Test-Path $hookPath)) {
        throw "Hook not found: $hookPath"
    }
    if (-not $Branch -and -not $Detached) {
        # Pipe JSON to the hook script via stdin
        $output = $JsonInput | powershell -NoProfile -ExecutionPolicy Bypass -File $hookPath 2>&1
        $exitCode = $LASTEXITCODE
        # Parse output
        $text = ($output | Out-String).Trim()
        return @{ Output = $text; ExitCode = $exitCode }
    }
    return (Invoke-HookInFixture -HookPath $hookPath -Script $Script -JsonInput $JsonInput -Branch $Branch -Detached:$Detached)
}

# Branch-context gates read the branch of the repo the hook sits in, resolved
# from $PSScriptRoot. Copying the hook into a throwaway repo checked out to
# $Branch makes the branch an input of the test; without it the assertion
# silently inherits the developer's checkout and flips colour with it.
function Invoke-HookInFixture {
    param(
        [string]$HookPath,
        [string]$Script,
        [string]$JsonInput,
        [string]$Branch,
        [switch]$Detached
    )
    $fixture = Join-Path ([System.IO.Path]::GetTempPath()) "af-hook-branch-$(Get-Random)"
    $fixtureHooks = Join-Path $fixture '.github/hooks/scripts'
    New-Item -ItemType Directory -Path $fixtureHooks -Force | Out-Null
    Copy-Item $HookPath $fixtureHooks
    # Same config the hook would read in production, so SRC_DIR is not a guess.
    $confSrc = Join-Path $githubDir 'af-env.conf'
    if (Test-Path $confSrc) { Copy-Item $confSrc (Join-Path $fixture '.github') }
    try {
        Push-Location $fixture
        git init -q 2>&1 | Out-Null
        if ($Detached) {
            git -c user.email=fixture@local -c user.name=fixture commit -q --allow-empty -m 'fixture' 2>&1 | Out-Null
            git checkout -q --detach 2>&1 | Out-Null
        } else {
            git checkout -q -b $Branch 2>&1 | Out-Null
        }
        $output = $JsonInput | powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixtureHooks $Script) 2>&1
        $exitCode = $LASTEXITCODE
        return @{ Output = ($output | Out-String).Trim(); ExitCode = $exitCode }
    } finally {
        Pop-Location
        Remove-Item $fixture -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Assert-Deny {
    param([string]$TestName, [string]$Script, [string]$Json, [string]$Branch, [switch]$Detached)
    try {
        $result = Invoke-Hook -Script $Script -JsonInput $Json -Branch $Branch -Detached:$Detached
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
    param([string]$TestName, [string]$Script, [string]$Json, [string]$Branch)
    try {
        $result = Invoke-Hook -Script $Script -JsonInput $Json -Branch $Branch
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
    param([string]$TestName, [string]$Script, [string]$Json, [string]$Branch)
    try {
        $result = Invoke-Hook -Script $Script -JsonInput $Json -Branch $Branch
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

# ── DENY: hard-blocked, level-independent ────────────────────────────────
Assert-Deny "push to protected branch is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git push origin main"}}'

Assert-Deny "git rebase is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git rebase main"}}'

Assert-Deny "git reset --hard is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git reset --hard HEAD~1"}}'

Assert-Deny "rm -rf broad path is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"rm -rf /tmp/data"}}'

Assert-Deny "recursive force delete is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"Remove-Item ./build -Recurse -Force"}}'

Assert-Deny "git branch -D is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git branch -D old-branch"}}'

Assert-Deny "--no-verify is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git commit --no-verify -m test"}}'

Assert-Deny "git add . is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git add ."}}'

Assert-Deny "git add -A is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git add -A"}}'

# ── ASK: durable change, confirm (balanced defaults) ─────────────────────
Assert-Ask "single-file delete asks by default (FS_WRITE opt-in)" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"Remove-Item ./scratch.tmp"}}'

Assert-Ask "recursive (no force) delete asks" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"Remove-Item ./build -Recurse"}}'

# ── ALLOW: safe under balanced defaults ──────────────────────────────────
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

Assert-Allow "git merge auto-allowed at balanced default" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git merge feature"}}'

# Improvement: git config read (no value) is read-only
Assert-Allow "git config read is safe" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git config --global user.email"}}'

# Improvement: pip show via call-operator + quoted python path is read-only
Assert-Allow "pip show via call operator is safe" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"& \".venv/Scripts/python.exe\" -m pip show ruff"}}'

# Improvement: ASK scan ignores quoted literals (no false databricks-export ask)
Assert-Allow "commit message mentioning databricks export does not false-ask" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git commit -m \"populate databricks.yml from prod job export\""}}'

# Improvement: separators inside quotes do not split the command
Assert-Allow "separators inside quotes do not split" `
    "block-dangerous.ps1" `
    '{"tool_name":"runInTerminal","tool_input":{"command":"git commit -m \"fix: a; b | c\""}}'

Assert-Allow "non-terminal tool ignored" `
    "block-dangerous.ps1" `
    '{"tool_name":"readFile","tool_input":{"filePath":"src/main.py"}}'

# ── createAndRunTask shape: hard-deny tier (mirrored from runInTerminal) ───
# The dangerous commands must also be denied when wrapped in createAndRunTask.
# Currently these FAIL because block-dangerous returns {} (allow) for non-terminal tools.
Assert-Deny "createAndRunTask: force push is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"push","type":"shell","command":"git","args":["push","--force","origin","main"]}}}'

Assert-Deny "createAndRunTask: push to protected branch is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"push","type":"shell","command":"git","args":["push","origin","main"]}}}'

Assert-Deny "createAndRunTask: git reset --hard is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"reset","type":"shell","command":"git","args":["reset","--hard","HEAD~1"]}}}'

Assert-Deny "createAndRunTask: git rebase is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"rebase","type":"shell","command":"git","args":["rebase","main"]}}}'

Assert-Deny "createAndRunTask: git branch -D is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"branch-delete","type":"shell","command":"git","args":["branch","-D","old-branch"]}}}'

Assert-Deny "createAndRunTask: rm -rf is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"remove","type":"shell","command":"rm","args":["-rf","/tmp/data"]}}}'

Assert-Deny "createAndRunTask: --no-verify is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"commit","type":"shell","command":"git","args":["commit","--no-verify","-m","test"]}}}'

# ── createAndRunTask shape: bare binary rejection (allowlist enforcement) ──
# The allowlist policy denies bare binaries.
Assert-Deny "createAndRunTask: bare git binary is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"git-status","type":"shell","command":"git","args":["status"]}}}'

Assert-Deny "createAndRunTask: bare ruff binary is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"lint","type":"shell","command":"ruff","args":["check","mpusage/"]}}}'

Assert-Deny "createAndRunTask: bare pytest binary is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"test","type":"shell","command":"pytest","args":["tests/"]}}}'

Assert-Deny "createAndRunTask: bare databricks binary is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"db-list","type":"shell","command":"databricks","args":["workspace","list"]}}}'

# ── createAndRunTask shape: powershell -Command inline script denial ───
# Inline scripts via -Command are denied (must use allowlisted -File path).
Assert-Deny "createAndRunTask: powershell -Command inline script is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"pwsh-inline","type":"shell","command":"powershell","args":["-NoProfile","-Command","Remove-Item x -Recurse -Force"]}}}'

# ── createAndRunTask shape: -File outside allowlist denial ──────────────────
# Files outside AF_TASK_SCRIPT_DIRS are denied (path-traversal prevention).
Assert-Deny "createAndRunTask: -File to %TEMP% script is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"temp-script","type":"shell","command":"powershell","args":["-NoProfile","-File","%TEMP%\\x.ps1"]}}}'

Assert-Deny "createAndRunTask: -File via path traversal is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"traversal","type":"shell","command":"powershell","args":["-NoProfile","-File",".github/scripts/../../../Windows/System32/cmd.exe"]}}}'

# ── createAndRunTask shape: input-variable denial ──────────────────────────
# Interactive input variables are denied (agents must not block on prompts).
# Name is single-quoted: a double-quoted name would interpolate the very
# construct under test and break the parse of everything below it.
Assert-Deny 'createAndRunTask: interactive input variable is denied' `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"user-input","type":"shell","command":"echo","args":["${input:promptUser}"]}}}'

# ── createAndRunTask shape: regression - legitimate curated invocations ────
# These four scripts are the framework-approved entry points. They must ALLOW
# (or defer to user, i.e. return {} which is allow-like).
Assert-Allow "createAndRunTask: .github/scripts/run-tests.ps1 -Scope domain allows" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"test-domain","type":"shell","command":".github/scripts/run-tests.ps1","args":["-Scope","domain"]}}}'

Assert-Allow "createAndRunTask: .github/scripts/run-lint.ps1 -Scope all allows" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"lint-all","type":"shell","command":".github/scripts/run-lint.ps1","args":["-Scope","all"]}}}'

Assert-Allow "createAndRunTask: .github/scripts/run-metrics.ps1 -Metric complexity allows" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"metrics-complexity","type":"shell","command":".github/scripts/run-metrics.ps1","args":["-Metric","complexity"]}}}'

Assert-Allow "createAndRunTask: .github/scripts/run-deps.ps1 -Scope dev allows" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"deps-dev","type":"shell","command":".github/scripts/run-deps.ps1","args":["-Scope","dev"]}}}'

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

Assert-Allow "coordinator can runInTerminal (git)" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"run_in_terminal","tool_input":{"command":"git status"}}'

Assert-Allow "coordinator can getProblems" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"problems","tool_input":{}}'

# Should DENY pytest via terminal
Assert-Deny "coordinator cannot pytest via terminal" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"run_in_terminal","tool_input":{"command":"pytest tests/ -q"}}'

Assert-Deny "coordinator cannot python -m pytest via terminal" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"run_in_terminal","tool_input":{"command":".venv/Scripts/python.exe -m pytest tests/ -q 2>&1"}}'

Assert-Deny "coordinator cannot py.test via terminal" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"run_in_terminal","tool_input":{"command":"py.test tests/domain/"}}'

Assert-Allow "coordinator can run git via terminal" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"run_in_terminal","tool_input":{"command":"git diff --stat"}}'

Assert-Allow "coordinator can run non-test scripts via terminal" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"run_in_terminal","tool_input":{"command":".github/scripts/audit-tools.ps1"}}'

Write-Output ""

# ── 3. test-writer-pretooluse.ps1 ────────────────────────────────────────

Write-Output "## test-writer-pretooluse.ps1"

# Read SRC_DIR from the same af-env.conf the fixture hands to the hook
$srcDir = 'src'
$confPath = Join-Path $githubDir 'af-env.conf'
if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^SRC_DIR=(.+)$'
    if ($m) { $srcDir = $m.Matches[0].Groups[1].Value.Trim() }
}

# File paths stay relative: the hook resolves them against its own working
# directory, which inside a fixture is the fixture root.
$agentBranch = 'agent/fixture-37'

# SRC_DIR gate -- asserted on an agent/* branch so the branch gate, which is
# evaluated first, cannot answer in its place.
$prodJson = @{ tool_name = "editFiles"; tool_input = @{ filePath = "$srcDir/main.py" } } | ConvertTo-Json -Compress
Assert-Deny "test-writer cannot edit production code" `
    "test-writer-pretooluse.ps1" $prodJson -Branch $agentBranch

$prodCreate = @{ tool_name = "createFile"; tool_input = @{ filePath = "$srcDir/new_module.py" } } | ConvertTo-Json -Compress
Assert-Deny "test-writer cannot create production file" `
    "test-writer-pretooluse.ps1" $prodCreate -Branch $agentBranch

# Branch-context gate (v1.18.10+), both directions. test-writer must run inside
# a worktree checked out to agent/*; on any other branch a test file edit is a
# hard block, and on an agent branch it must go through.
$testJson = @{ tool_name = "editFiles"; tool_input = @{ filePath = "tests/test_example.py" } } | ConvertTo-Json -Compress
Assert-Deny "test-writer denied on non-agent branch (test file edit)" `
    "test-writer-pretooluse.ps1" $testJson -Branch 'dev'

$testCreate = @{ tool_name = "createFile"; tool_input = @{ filePath = "tests/test_new.py" } } | ConvertTo-Json -Compress
Assert-Deny "test-writer denied on non-agent branch (test file create)" `
    "test-writer-pretooluse.ps1" $testCreate -Branch 'dev'

Assert-Allow "test-writer may edit a test file on an agent branch" `
    "test-writer-pretooluse.ps1" $testJson -Branch $agentBranch

# A detached worktree is the documented way to rehearse merges, and it is not
# an agent branch either.
Assert-Deny "test-writer denied on detached HEAD" `
    "test-writer-pretooluse.ps1" $testJson -Detached

# Should ALLOW read tools
Assert-Allow "test-writer can readFile" `
    "test-writer-pretooluse.ps1" `
    '{"tool_name":"readFile","tool_input":{"filePath":"src/main.py"}}'

Write-Output ""

# ── 4. refactorer-pretooluse.ps1 ─────────────────────────────────────────

Write-Output "## refactorer-pretooluse.ps1"

# No-new-files gate -- asserted on an agent/* branch so the branch gate, which
# is evaluated first, cannot answer in its place.
Assert-Deny "refactorer cannot createFile" `
    "refactorer-pretooluse.ps1" `
    '{"tool_name":"createFile","tool_input":{"filePath":"src/new.py"}}' -Branch $agentBranch

Assert-Deny "refactorer cannot createDirectory" `
    "refactorer-pretooluse.ps1" `
    '{"tool_name":"createDirectory","tool_input":{"path":"src/new_dir/"}}' -Branch $agentBranch

# Branch-context gate (v1.18.10+), both directions
Assert-Deny "refactorer denied on non-agent branch (file edit)" `
    "refactorer-pretooluse.ps1" `
    '{"tool_name":"editFiles","tool_input":{"filePath":"src/main.py"}}' -Branch 'dev'

Assert-Allow "refactorer may edit an existing file on an agent branch" `
    "refactorer-pretooluse.ps1" `
    '{"tool_name":"editFiles","tool_input":{"filePath":"src/main.py"}}' -Branch $agentBranch

Assert-Deny "refactorer denied on detached HEAD" `
    "refactorer-pretooluse.ps1" `
    '{"tool_name":"editFiles","tool_input":{"filePath":"src/main.py"}}' -Detached

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
