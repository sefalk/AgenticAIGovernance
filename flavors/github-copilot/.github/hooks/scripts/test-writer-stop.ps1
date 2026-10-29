# Agent-scoped Stop hook for the test-writer agent.
#
# RED PHASE GATE (HARD -- blocks test-writer if new tests do NOT fail)
#
# The Red phase requires that all newly written tests FAIL against the
# existing production code. If tests pass, the test-writer has not
# expressed a genuine requirement gap.
#
# Also checks provenance markers on newly created test files (H5).
#
# Fires as SubagentStop when the test-writer is invoked by the coordinator.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'

# Root resolution AND the shared provenance detector both come from here. The
# hand-rolled worktree block this replaced left Test-AfProvenanceMarker
# undefined, and PowerShell abandons the enclosing `if` on a command-not-found
# error, so Gate 2 silently never fired (issue #175).
. "$PSScriptRoot/_common.ps1"
$codeRoot = $AfCodeRoot
$mainRoot = $AfMainRoot

# Read stdin (hook input JSON -- required by protocol, and Gate 0 needs it)
$stdinRaw = [Console]::In.ReadToEnd()

# Before Gate 0, because Gate 0 blocks too (issue #298).
Invoke-AfStopLoopGuard -StdinRaw $stdinRaw -Agent 'test-writer' `
    -Gates 'undeclared root files, red phase, provenance, no production code'
Invoke-AfRepoGates -StdinRaw $stdinRaw -HookPath $PSCommandPath

# ---------- Gate 0: no undeclared files at the repository root (#123) ----------
#
# Runs before the Red gate on purpose. The Red gate is skipped when no runner
# or no tests are found, and a scratch file left in the root is
# a mess whether or not the suite ran.
$scratch = @(Get-AfUndeclaredScratch -StdinRaw $stdinRaw -Agent 'test-writer' -CodeRoot $codeRoot -MainRoot $mainRoot)
if ($scratch.Count -gt 0) {
    $list = $scratch -join ', '
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "Stop"
            decision      = "block"
            reason        = "Undeclared files at the repository root: $list. You created these, and the task you were given never mentions them. Throwaway runners and verification scripts do not belong in the repository -- delete them, or put them under the system temp directory. If one of them really is a requested deliverable, it belongs in the directory its kind lives in (tests/ for tests, docs/ for documents), not the root."
        }
    } | ConvertTo-Json -Compress -Depth 3
    Write-Output $output
    exit 0
}

# A missing runner, tests/ directory or collected test disables the Red gate
# only. Exiting here used to skip the provenance gate with it, and the runner
# was looked up on a PATH the extension host never puts the venv on (#473).
$redNotRun = $null
$pytest = Get-AfPytest -Root $codeRoot
if ($pytest.Count -eq 0) {
    $redNotRun = 'no pytest in the code root .venv or on PATH'
} elseif (-not (Test-Path (Join-Path $codeRoot 'tests'))) {
    $redNotRun = 'no tests/ directory'
}

# ---------- Gate 1: Red phase -- new tests must FAIL ----------

$result = @()
if (-not $redNotRun) {
    $pytestExe = $pytest[0]
    $pytestArgs = @($pytest | Select-Object -Skip 1)
    Push-Location $codeRoot
    $result = & $pytestExe @pytestArgs tests/ -q --tb=line --no-header 2>&1
    $exitCode = $LASTEXITCODE
    Pop-Location

    # Exit code 0 = all tests pass -> Red phase violation (tests should fail)
    # Exit code 1 = some tests fail -> Red phase satisfied
    # Exit code 5 = no tests collected -> skip (nothing to verify)
    if ($exitCode -eq 0) {
        $output = @{
            hookSpecificOutput = @{
                hookEventName = "Stop"
                decision = "block"
                reason = "Red phase violation: all tests PASS. New tests must FAIL against the existing production code to express a genuine requirement gap. Ensure your tests assert behaviour that is not yet implemented."
            }
        } | ConvertTo-Json -Compress -Depth 3
        Write-Output $output
        exit 0
    }

    if ($exitCode -eq 5) {
        $redNotRun = 'no tests collected'
    }
}

# Not every red is a red. A file that cannot be imported (exit 2) or a test that
# errors before it runs -- missing fixture, fixture raising -- never reaches the
# behaviour it claims to guard, and it stays red after a perfect implementation.
# Everything but 0 and 5 used to fall through to "Red phase satisfied", which
# sent the Green phase hunting for a defect that does not exist (issue #123).
#
# Read off the summary line as well as the exit code: a missing fixture reports
# `1 error` and still exits 1, indistinguishable from a genuine failure by exit
# code alone. Measured 2026-08-24.
$summaryLine = ($result | Where-Object { "$_".Trim() } | Select-Object -Last 1 | Out-String).Trim()
if (-not $redNotRun -and ($exitCode -eq 2 -or $summaryLine -match '\d+ error')) {
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "Stop"
            decision      = "block"
            reason        = "Red phase invalid: the suite reported collection or setup ERRORS, not test failures. A test that cannot be collected or set up never reaches the behaviour it claims to guard, and it stays red after a correct implementation. Fix the test construction -- imports, syntax, fixtures, schema-less DataFrames -- so the red comes from an assertion. Summary: $summaryLine"
        }
    } | ConvertTo-Json -Compress -Depth 3
    Write-Output $output
    exit 0
}

# Tests are failing -- Red phase satisfied. Now check provenance.

# ---------- Gate 2: Provenance markers on new test files (H5) ----------

# --untracked-files=all: a new test directory is otherwise one `?? tests/x/` line
# with no .py in it, and every file inside escaped this gate (#473).
$newTestFiles = & git -C $codeRoot status --porcelain --untracked-files=all "tests/" 2>$null |
    Where-Object { $_ -match '^\?\? ' -or $_ -match '^A ' } |
    ForEach-Object { ($_ -replace '^.. ', '').Trim('"') } |
    Where-Object { $_ -match '\.py$' }

# `git status` is global to the checkout, so a producer running alongside this
# one puts its new test files in this scope. Clearing the block below means
# writing `copilot:generated` -- "this agent produced the whole file" -- into a
# file this agent never opened (issue #101). Same subtraction the implementer
# and refactorer already make; the marker is the stronger claim of the two.
$peerEdits = @(Get-AfPeerEdits -StdinRaw $stdinRaw -Agent 'test-writer' -CodeRoot $codeRoot -MainRoot $mainRoot)
$newTestFiles = @($newTestFiles | Where-Object { $_ -and ($peerEdits -notcontains $_) })

$missingMarkers = @()
foreach ($f in $newTestFiles) {
    if (Test-Path (Join-Path $codeRoot $f)) {
        if (-not (Test-AfProvenanceMarker -Path (Join-Path $codeRoot $f) -Kind 'generated')) {
            $missingMarkers += $f
        }
    }
}

if ($missingMarkers.Count -gt 0) {
    $list = $missingMarkers -join ', '
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "Stop"
            decision = "block"
            reason = "Provenance violation: these new test files carry no 'copilot:generated' marker anywhere: $list. See instructions/provenance.instructions.md for where to put it."
        }
    } | ConvertTo-Json -Compress -Depth 3
    Write-Output $output
    exit 0
}

# All gates passed
$summary = ($result | Select-Object -Last 1 | Out-String).Trim()
$output = @{
    systemMessage = if ($redNotRun) {
        "test-writer:Stop -- Red gate NOT RUN ($redNotRun); provenance OK"
    } else {
        "test-writer:Stop -- Red gate PASS: tests are failing as expected. Provenance OK. Summary: $summary"
    }
} | ConvertTo-Json -Compress
Write-Output $output
exit 0
