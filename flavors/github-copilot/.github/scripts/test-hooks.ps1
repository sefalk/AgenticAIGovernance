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
    # Hooks dot-source the shared preamble; a deployed .github always ships it.
    $commonSrc = Join-Path (Split-Path $HookPath) '_common.ps1'
    if (Test-Path $commonSrc) { Copy-Item $commonSrc $fixtureHooks }
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

# The single place that decides what a hook answered. 'silent' is deliberately
# not 'allow': on the wire they are the same bytes, but only one of them means
# the hook looked at the request. A non-zero exit or unparsable output means it
# never reached a verdict, whatever else it printed.
function Resolve-Decision {
    param([string]$Text, [int]$ExitCode = 0)
    if ($ExitCode -ne 0) { return 'error' }
    $t = if ($null -eq $Text) { '' } else { $Text.Trim() }
    if ($t -eq '' -or $t -eq '{}') { return 'silent' }
    try {
        $parsed = $t | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return 'error'
    }
    $decision = $parsed.hookSpecificOutput.permissionDecision
    if ([string]::IsNullOrWhiteSpace($decision)) { return 'silent' }
    return [string]$decision
}

function Assert-Decision {
    param(
        [string]$TestName,
        [string]$Expected,
        [string]$Script,
        [string]$Json,
        [string]$Branch,
        [switch]$Detached
    )
    try {
        $result = Invoke-Hook -Script $Script -JsonInput $Json -Branch $Branch -Detached:$Detached
        $decision = Resolve-Decision $result.Output $result.ExitCode
        if ($decision -eq $Expected) {
            $script:passed++
            if ($Verbose) { Write-Output "  PASS  $TestName" }
        } else {
            $script:failed++
            $script:errors += "FAIL  $TestName -- expected $Expected, got '$decision' (exit $($result.ExitCode), output: $($result.Output))"
        }
    } catch {
        $script:failed++
        $script:errors += "ERROR $TestName -- $($_.Exception.Message)"
    }
}

function Assert-Deny {
    param([string]$TestName, [string]$Script, [string]$Json, [string]$Branch, [switch]$Detached)
    Assert-Decision -TestName $TestName -Expected 'deny' -Script $Script -Json $Json -Branch $Branch -Detached:$Detached
}

function Assert-Ask {
    param([string]$TestName, [string]$Script, [string]$Json, [string]$Branch, [switch]$Detached)
    Assert-Decision -TestName $TestName -Expected 'ask' -Script $Script -Json $Json -Branch $Branch -Detached:$Detached
}

# The hook examined the request and approved it.
function Assert-Allow {
    param([string]$TestName, [string]$Script, [string]$Json, [string]$Branch, [switch]$Detached)
    Assert-Decision -TestName $TestName -Expected 'allow' -Script $Script -Json $Json -Branch $Branch -Detached:$Detached
}

# The hook had no opinion and said so. Distinct from Assert-Allow: it does not
# claim the request was approved, only that this gate was not the one to judge.
function Assert-Silent {
    param([string]$TestName, [string]$Script, [string]$Json, [string]$Branch, [switch]$Detached)
    Assert-Decision -TestName $TestName -Expected 'silent' -Script $Script -Json $Json -Branch $Branch -Detached:$Detached
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

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Detail)
    if ($Condition) {
        $script:passed++
        if ($Verbose) { Write-Output "  PASS  $TestName" }
    } else {
        $script:failed++
        $script:errors += "FAIL  $TestName -- $Detail"
    }
}

Write-Output "=== Hook Integration Tests ==="
Write-Output ""

# ── 0. Harness self-check ────────────────────────────────────────────────
#
# A gate that cannot run and a gate with nothing to say produce the same
# output: nothing. A harness that reads that silence as approval cannot fail
# on an inert hook -- which is how #64 (wrong payload field, returned {} on
# every real fetch) and #65 (unparsable, exited non-zero, printed nothing)
# stayed green. Verify the instrument before trusting it to judge the hooks.

Write-Output "## harness self-check"

$decAllow = '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"safe"}}'
$decDeny  = '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"blocked"}}'
$decAsk   = '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"confirm"}}'

Assert-True "explicit allow is an allow" `
    ((Resolve-Decision $decAllow 0) -eq 'allow') "got: $(Resolve-Decision $decAllow 0)"
Assert-True "deny is a deny" `
    ((Resolve-Decision $decDeny 0) -eq 'deny') "got: $(Resolve-Decision $decDeny 0)"
Assert-True "ask is an ask" `
    ((Resolve-Decision $decAsk 0) -eq 'ask') "got: $(Resolve-Decision $decAsk 0)"

# The three that used to be indistinguishable from an approval.
Assert-True "an empty verdict is silence, not approval" `
    ((Resolve-Decision '{}' 0) -eq 'silent') "got: $(Resolve-Decision '{}' 0)"
Assert-True "no output at all is silence, not approval" `
    ((Resolve-Decision '' 0) -eq 'silent') "got: $(Resolve-Decision '' 0)"
Assert-True "a hook that exits non-zero has made no decision" `
    ((Resolve-Decision '{}' 1) -eq 'error') "got: $(Resolve-Decision '{}' 1)"
Assert-True "a crashing hook is not an approval" `
    ((Resolve-Decision 'bash: line 3: syntax error near unexpected token' 0) -eq 'error') `
    "got: $(Resolve-Decision 'bash: line 3: syntax error near unexpected token' 0)"

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

Assert-Silent "non-terminal tool ignored" `
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
# These four scripts are the framework-approved entry points. The classifier
# must recognise them and say so; falling through to {} would mean it never
# reached a verdict on them.
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

# ── createAndRunTask shape: the effective command is not always `command` ──
# Per the VS Code task docs, executable content reaches a task through four
# places, not one. An allowlist that reads only `command` is decorative.

# "Properties defined in an operating system specific scope override
# properties defined in the task or global scope" -- so `command` is a decoy.
Assert-Deny "createAndRunTask: OS-specific command override is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"os-override","type":"shell","command":".github/scripts/run-tests.ps1","windows":{"command":"cmd.exe","args":["/c","echo pwned"]}}}}'

# "you can override a task's shell with the options.shell property" -- the
# payload then rides in the shell's own arguments.
Assert-Deny "createAndRunTask: options.shell override is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"shell-override","type":"shell","command":".github/scripts/run-tests.ps1","options":{"shell":{"executable":"powershell","args":["-Command","echo pwned"]}}}}}'

# "If a single command is provided, the task system passes the command as is
# to the underlying shell" -- shell metacharacters survive path normalisation,
# so a prefix match on the allowlisted script lets the rest ride along.
Assert-Deny "createAndRunTask: shell metacharacter in command is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"chained","type":"shell","command":".github/scripts/run-tests.ps1; echo pwned"}}}'

Assert-Deny "createAndRunTask: chained command operator is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"chained2","type":"shell","command":".github/scripts/run-tests.ps1 && echo pwned"}}}'

# Indirection variables resolve somewhere the classifier cannot see; the
# command: form additionally executes a VS Code command to produce its value.
Assert-Deny "createAndRunTask: command-substitution variable is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"cmdvar","type":"process","command":"${command:python.interpreterPath}","args":["-c","print(1)"]}}}'

Assert-Deny "createAndRunTask: settings-substitution variable is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"cfgvar","type":"process","command":"${config:python.defaultInterpreterPath}","args":["-c","print(1)"]}}}'

# A task registered to run on folder open would execute later, outside any
# hook's view.
Assert-Deny "createAndRunTask: runOn folderOpen is denied" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"autorun","type":"shell","command":".github/scripts/run-tests.ps1","runOptions":{"runOn":"folderOpen"}}}}'

# False deny costs as much as a false allow: it pushes agents back to the
# terminal. The workspace-folder variable is the documented portable form.
Assert-Allow "createAndRunTask: workspace-folder path variable allows" `
    "block-dangerous.ps1" `
    '{"tool_name":"createAndRunTask","tool_input":{"task":{"label":"wsvar","type":"shell","command":"${workspaceFolder}/.github/scripts/run-tests.ps1","args":["-Scope","domain"]}}}'

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

# The delegation gate only ever objects; on anything it permits it returns {}
# and the tool call proceeds under VS Code's own rules. Assert that silence
# explicitly, so a hook that dies before reaching the gate cannot pass here.
Assert-Silent "coordinator can readFile" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"readFile","tool_input":{"filePath":"src/main.py"}}'

Assert-Silent "coordinator can searchCodebase" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"searchCodebase","tool_input":{"query":"hello"}}'

Assert-Silent "coordinator can listDirectory" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"listDirectory","tool_input":{"path":"src/"}}'

Assert-Silent "coordinator can runInTerminal (git)" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"run_in_terminal","tool_input":{"command":"git status"}}'

Assert-Silent "coordinator can getProblems" `
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

Assert-Silent "coordinator can run git via terminal" `
    "coordinator-pretooluse.ps1" `
    '{"tool_name":"run_in_terminal","tool_input":{"command":"git diff --stat"}}'

Assert-Silent "coordinator can run non-test scripts via terminal" `
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

Assert-Silent "test-writer may edit a test file on an agent branch" `
    "test-writer-pretooluse.ps1" $testJson -Branch $agentBranch

# A detached worktree is the documented way to rehearse merges, and it is not
# an agent branch either.
Assert-Deny "test-writer denied on detached HEAD" `
    "test-writer-pretooluse.ps1" $testJson -Detached

# Read tools are outside the gate's remit
Assert-Silent "test-writer can readFile" `
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

Assert-Silent "refactorer may edit an existing file on an agent branch" `
    "refactorer-pretooluse.ps1" `
    '{"tool_name":"editFiles","tool_input":{"filePath":"src/main.py"}}' -Branch $agentBranch

Assert-Deny "refactorer denied on detached HEAD" `
    "refactorer-pretooluse.ps1" `
    '{"tool_name":"editFiles","tool_input":{"filePath":"src/main.py"}}' -Detached

Assert-Silent "refactorer can readFile" `
    "refactorer-pretooluse.ps1" `
    '{"tool_name":"readFile","tool_input":{"filePath":"src/main.py"}}'

# createAndRunTask is not a file creation
Assert-Silent "refactorer can createAndRunTask" `
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

Assert-Silent "non-fetch tool ignored" `
    "researcher-pretooluse.ps1" `
    '{"tool_name":"readFile","tool_input":{"filePath":"src/main.py"}}'

# The shape VS Code's fetch tool actually sends: `urls` (an array) beside
# `query`. These assert the explicit decision, because '{}' here would mean the
# hook never examined the URLs -- which is how it stayed green for as long as
# it did (issue #64).
$fetchUrlsOk      = '{"tool_name":"fetch_webpage","tool_input":{"urls":["https://docs.python.org/3/library/os.html"],"query":"os.path"}}'
$fetchUrlsUnknown = '{"tool_name":"fetch_webpage","tool_input":{"urls":["https://unlisted.example.com/x"],"query":"x"}}'
$fetchUrlsMixed   = '{"tool_name":"fetch_webpage","tool_input":{"urls":["https://docs.python.org/3/library/os.html","https://unlisted.example.com/x"],"query":"x"}}'
$fetchUrlsCred    = '{"tool_name":"fetch_webpage","tool_input":{"urls":["https://user:hunter2@docs.python.org/3/?token=abc123"],"query":"x"}}'
# The host is what follows the last `@` in the authority, not what precedes the
# first `:`. Reading the userinfo instead turns any allowlisted name into a
# password on an arbitrary host.
$fetchUrlsSpoof   = '{"tool_name":"fetch_webpage","tool_input":{"urls":["https://docs.python.org:x@evil.example.com/"],"query":"x"}}'

function Get-FetchDecision([string]$Json) {
    $r = Invoke-Hook -Script 'researcher-pretooluse.ps1' -JsonInput $Json
    $parsed = $r.Output | ConvertFrom-Json -ErrorAction SilentlyContinue
    return @{ Decision = $parsed.hookSpecificOutput.permissionDecision; Output = $r.Output }
}

$rOk = Get-FetchDecision $fetchUrlsOk
Assert-True "urls array reaches the allowlist" ($rOk.Decision -eq 'allow') `
    "expected an explicit allow, got: $($rOk.Output)"

$rUnknown = Get-FetchDecision $fetchUrlsUnknown
Assert-True "unlisted url in a urls array prompts" ($rUnknown.Decision -eq 'ask') `
    "expected ask, got: $($rUnknown.Output)"

# One bad entry has to decide the batch: the tool fetches every URL in the
# array, so allowing on the first match approves the rest unexamined.
$rMixed = Get-FetchDecision $fetchUrlsMixed
Assert-True "one unlisted entry decides the batch" ($rMixed.Decision -eq 'ask') `
    "expected ask, got: $($rMixed.Output)"

$rCred = Get-FetchDecision $fetchUrlsCred
Assert-True "credentialed url is reported without echoing the secret" `
    ($rCred.Output.Contains('***') -and -not $rCred.Output.Contains('hunter2')) `
    "got: $($rCred.Output)"

$rSpoof = Get-FetchDecision $fetchUrlsSpoof
Assert-True "userinfo cannot spoof an allowlisted host" ($rSpoof.Decision -eq 'ask') `
    "expected ask, got: $($rSpoof.Output)"

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
Assert-Silent "non-edit tool ignored" `
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

# ── 8. Resolution invariants (roots, config, interpreter) ────────────────

# The production failure these cover is silence: a config read from the wrong
# place returns nothing, which is indistinguishable from "the setting is not
# configured". Every case below therefore runs from a cwd that is *not* the
# fixture root -- the shape the existing fixtures never exercised.

Write-Output "## Resolution invariants"

$commonPs1 = Join-Path $scriptDir '_common.ps1'
$commonSh = Join-Path $scriptDir '_common.sh'
Assert-True "shared preamble present (.ps1)" (Test-Path $commonPs1) "expected $commonPs1"
Assert-True "shared preamble present (.sh)" (Test-Path $commonSh) "expected $commonSh"

if (Test-Path $commonPs1) {
    $fx = Join-Path ([System.IO.Path]::GetTempPath()) "af-resolve-$(Get-Random)"
    $fxHooks = Join-Path $fx '.github/hooks/scripts'
    New-Item -ItemType Directory -Path $fxHooks -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fx 'docs/deep') -Force | Out-Null
    Copy-Item $commonPs1 $fxHooks
    Set-Content -Path (Join-Path $fx '.github/af-env.conf') -Value "SRC_DIR=lib`nBASE_BRANCH=trunk"

    $probeBody = @'
. "$PSScriptRoot/_common.ps1"
$found = if ($AfConfFound) { 1 } else { 0 }
$src = Get-AfConfig -Key 'SRC_DIR' -Default 'src'
$absent = Get-AfConfig -Key 'NOPE' -Default 'fallback'
Write-Output "found=$found src=$src absent=$absent"
'@
    $probePath = Join-Path $fxHooks 'probe.ps1'
    Set-Content -Path $probePath -Value $probeBody

    $seen = @()
    foreach ($cwd in @($fx, (Join-Path $fx 'docs/deep'), ([System.IO.Path]::GetTempPath()))) {
        Push-Location $cwd
        $seen += (& powershell -NoProfile -ExecutionPolicy Bypass -File $probePath 2>&1 | Out-String).Trim()
        Pop-Location
    }
    $distinct = @($seen | Select-Object -Unique)
    $joined = $seen -join ' | '
    Assert-True "config resolves identically from every cwd" ($distinct.Count -eq 1) "got: $joined"
    Assert-True "configured value wins over the default" ($joined -like '*src=lib*') "got: $joined"
    Assert-True "absent key falls back to the default" ($joined -like '*absent=fallback*') "got: $joined"
    Assert-True "config presence is reported" ($joined -like '*found=1*') "got: $joined"

    Remove-Item (Join-Path $fx '.github/af-env.conf') -Force -ErrorAction SilentlyContinue
    Push-Location $fx
    $noConf = (& powershell -NoProfile -ExecutionPolicy Bypass -File $probePath 2>&1 | Out-String).Trim()
    Pop-Location
    Assert-True "missing config is distinguishable from an unset key" `
        (($noConf -like '*found=0*') -and ($noConf -like '*src=src*')) "got: $noConf"

    Remove-Item $fx -Recurse -Force -ErrorAction SilentlyContinue
}

# A resolvable interpreter is not a working one. The .sh side asserts this; the
# .ps1 side has to as well, because PowerShell 5.1 drops empty-string arguments
# to native commands -- a probe written as `-c ''` rejects every candidate,
# including the working ones, and the hook then reports "no Python found".
$fxPy = Join-Path ([System.IO.Path]::GetTempPath()) "af-res-py-$(Get-Random)"
New-Item -ItemType Directory -Path (Join-Path $fxPy '.github/hooks/scripts') -Force | Out-Null
if (Test-Path $commonPs1) {
    Copy-Item $commonPs1 (Join-Path $fxPy '.github/hooks/scripts/')
    $pyProbe = Join-Path $fxPy '.github/hooks/scripts/pyprobe.ps1'
    Set-Content -Path $pyProbe -Value @'
. "$PSScriptRoot/_common.ps1"
# Single quotes inside: PowerShell 5.1 strips double quotes when it hands the
# argument to a native command, so print("ran") would reach python as print(ran).
if ($AfPython) { & $AfPython -c "print('ran')" } else { Write-Output "none" }
'@

    Push-Location ([System.IO.Path]::GetTempPath())
    $pyOut = (& powershell -NoProfile -ExecutionPolicy Bypass -File $pyProbe 2>&1 | Out-String).Trim()
    Pop-Location
    Assert-True "resolved interpreter actually runs" ($pyOut -eq 'ran') "got: $pyOut"

    $stubDir = Join-Path ([System.IO.Path]::GetTempPath()) "af-res-stub-$(Get-Random)"
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    $stub = Join-Path $stubDir 'python3.cmd'
    Set-Content -Path $stub -Value "@echo off`r`necho Install Python from the Microsoft Store`r`nexit /b 9009"
    $env:AF_PYTHON_OVERRIDE = $stub
    $stubOut = (& powershell -NoProfile -ExecutionPolicy Bypass -File $pyProbe 2>&1 | Out-String).Trim()
    Remove-Item Env:AF_PYTHON_OVERRIDE -ErrorAction SilentlyContinue
    Assert-True "interpreter resolver rejects a stub that resolves but does not run" `
        ($stubOut -eq 'ran') "got: $stubOut"

    Remove-Item $stubDir -Recurse -Force -ErrorAction SilentlyContinue
}
Remove-Item $fxPy -Recurse -Force -ErrorAction SilentlyContinue

# A helper alone does not stop the next hook from being written the old way.
$resolveChecker = Join-Path $PSScriptRoot 'check-hook-resolution.py'
Assert-True "resolution drift checker present" (Test-Path $resolveChecker) "expected $resolveChecker"

$pyExe = (Get-Command python -ErrorAction SilentlyContinue).Source
if ((Test-Path $resolveChecker) -and $pyExe) {
    & $pyExe $resolveChecker $scriptDir *> $null
    Assert-True "no hook resolves config or interpreter the unsafe way" ($LASTEXITCODE -eq 0) "checker exit $LASTEXITCODE"

    $seed = Join-Path ([System.IO.Path]::GetTempPath()) "af-drift-$(Get-Random)"
    New-Item -ItemType Directory -Path $seed -Force | Out-Null
    Set-Content -Path (Join-Path $seed 'seeded-hook.sh') `
        -Value 'V=$(grep "^SRC_DIR=" .github/af-env.conf | cut -d= -f2)'
    Set-Content -Path (Join-Path $seed 'seeded-hook.ps1') `
        -Value '$c = Join-Path (Get-Location) ''.github/af-env.conf'''
    & $pyExe $resolveChecker $seed *> $null
    Assert-True "checker flags a reintroduced cwd-relative read" ($LASTEXITCODE -ne 0) "checker exit $LASTEXITCODE"

    Set-Content -Path (Join-Path $seed 'seeded-hook.sh') `
        -Value 'PYTHON=$(command -v python3 2>/dev/null || echo "")'
    Remove-Item (Join-Path $seed 'seeded-hook.ps1') -Force -ErrorAction SilentlyContinue
    & $pyExe $resolveChecker $seed *> $null
    Assert-True "checker flags an unvalidated interpreter lookup" ($LASTEXITCODE -ne 0) "checker exit $LASTEXITCODE"

    Remove-Item $seed -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ""

# ── 9. Parse gate ────────────────────────────────────────────────────────
#
# A hook that dies at parse time produces no output, and no output is
# indistinguishable from no objection -- the gate disarms itself silently.
# The behavioural cases above only cover hooks this harness invokes, so assert
# that every shipped script parses, invoked or not.

Write-Output "## parse gate"

$badPs1 = @()
foreach ($f in (Get-ChildItem -Path $scriptDir -Filter '*.ps1' -File)) {
    $tokErrors = $null
    [System.Management.Automation.PSParser]::Tokenize(
        (Get-Content $f.FullName -Raw), [ref]$tokErrors) | Out-Null
    if ($tokErrors -and $tokErrors.Count -gt 0) { $badPs1 += $f.Name }
}
Assert-True "every shipped PowerShell hook parses" ($badPs1.Count -eq 0) "tokenizer failed: $($badPs1 -join ', ')"

# Git for Windows ships bash; without it the .sh half is left to test-hooks.sh.
$bashExe = (Get-Command bash -ErrorAction SilentlyContinue).Source
if (-not $bashExe -and (Test-Path 'C:/Program Files/Git/bin/bash.exe')) {
    $bashExe = 'C:/Program Files/Git/bin/bash.exe'
}
if ($bashExe) {
    # bash writes its syntax diagnostics to stderr, and under 'Stop' a native
    # command's stderr is a terminating error -- the suite would die on the
    # finding instead of recording it. Redirection does not help; the
    # preference does.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $badSh = @()
    foreach ($f in (Get-ChildItem -Path $scriptDir -Filter '*.sh' -File)) {
        & $bashExe -n $f.FullName *> $null
        if ($LASTEXITCODE -ne 0) { $badSh += $f.Name }
    }
    $ErrorActionPreference = $prevEap
    Assert-True "every shipped bash hook parses" ($badSh.Count -eq 0) "bash -n failed: $($badSh -join ', ')"
} else {
    Write-Output "  SKIP  bash parse gate -- no bash on this host (covered by test-hooks.sh)"
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
