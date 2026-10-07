# Regression suite: a session cannot silently discard work that was uncommitted when it started (#120).
#
# Git keeps no copy of uncommitted changes. #120 lost a correct fix to a later
# session's checkout/restore, and nothing announced it. The guard is two hooks
# over one Python core (_foreign_guard.py):
#
#   - SessionStart (session-context) records every path dirty at session start,
#     per session_id, and reports paths of the previous baseline that went clean
#     without a commit.
#   - PreToolUse (block-dangerous) asks, naming the files, before a git command
#     discards one of this session's baseline paths. Paths the session dirtied
#     itself are not guarded; a missing baseline degrades to the classifier.
#
# Every case runs in both dialects in the same fixture: a guard honoured on one
# platform only is worse than none.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ghDir = Split-Path -Parent $scriptDir
$hookSrc = Join-Path $ghDir 'hooks/scripts'
$shippedConf = Join-Path $ghDir 'af-env.conf'

. (Join-Path $scriptDir '_suite_env.ps1')
$python = Get-AfSuitePython $scriptDir
if (-not $python) {
    Write-Host 'SKIP: no Python 3 interpreter found; the foreign-work guard is a Python core.'
    exit 0
}
$bashExe = @('C:\Program Files\Git\bin\bash.exe', '/bin/bash', '/usr/bin/bash') | Where-Object { Test-Path $_ } | Select-Object -First 1

$results = [ordered]@{}
$details = [ordered]@{}
function Add-Result([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ("af120-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$hooks = Join-Path $fixture '.github/hooks/scripts'
New-Item -ItemType Directory -Path $hooks -Force | Out-Null
foreach ($f in @('block-dangerous.ps1', 'block-dangerous.sh', 'session-context.ps1', 'session-context.sh', '_common.ps1', '_common.sh', '_foreign_guard.py')) {
    Copy-Item (Join-Path $hookSrc $f) $hooks
}
Copy-Item $shippedConf (Join-Path $fixture '.github/af-env.conf')
$prevConf = $env:AF_CONF_PATH
$env:AF_CONF_PATH = Join-Path $fixture '.github/af-env.conf'

# Not named Git: PowerShell resolves names case-insensitively, so it would shadow git itself.
function Invoke-FixtureGit([string[]]$GitArgs) {
    $ErrorActionPreference = 'Continue'
    & git -C $fixture -c user.email=fixture@local -c user.name=fixture @GitArgs 2>&1 | Out-Null
}
function Write-Text([string]$Rel, [string]$Text) {
    $p = Join-Path $fixture $Rel
    New-Item -ItemType Directory -Path (Split-Path $p) -Force | Out-Null
    [IO.File]::WriteAllText($p, $Text)
}

function Invoke-Hook([string]$Hook, [string]$Dialect, [hashtable]$Payload) {
    $json = $Payload | ConvertTo-Json -Depth 6 -Compress
    Push-Location $fixture
    try {
        $ErrorActionPreference = 'Continue'
        if ($Dialect -eq 'sh') {
            $out = $json | & $bashExe ((Join-Path $hooks "$Hook.sh") -replace '\\', '/') 2>$null | Out-String
        } else {
            $out = $json | & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $hooks "$Hook.ps1") 2>$null | Out-String
        }
    } finally { Pop-Location }
    $decision = ''; $reason = ''; $context = ''
    try {
        $o = $out | ConvertFrom-Json
        $h = $o.hookSpecificOutput
        if ($h.PSObject.Properties['permissionDecision']) { $decision = [string]$h.permissionDecision; $reason = [string]$h.permissionDecisionReason }
        if ($h.PSObject.Properties['additionalContext']) { $context = [string]$h.additionalContext }
    } catch { }
    return [pscustomobject]@{ Out = $out.Trim(); Decision = $decision; Reason = $reason; Context = $context }
}

function Start-Session([string]$Session, [string]$Dialect) {
    return Invoke-Hook 'session-context' $Dialect @{ session_id = $Session; hook_event_name = 'SessionStart'; source = 'startup'; transcript_path = '/none' }
}
function Pre([string]$Session, [string]$Dialect, [string]$Command) {
    return Invoke-Hook 'block-dangerous' $Dialect @{ session_id = $Session; hook_event_name = 'PreToolUse'; tool_name = 'run_in_terminal'; tool_input = @{ command = $Command }; tool_use_id = 't1' }
}

# A repository where src/foreign.py is dirty before the session starts and an
# untracked scratch file exists; src/own.py is dirtied only after it started.
function Reset-Fixture {
    Remove-Item (Join-Path $fixture '.git') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $fixture 'src') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $fixture '.github/logs') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $fixture 'notes-wip.txt') -Force -ErrorAction SilentlyContinue
    Invoke-FixtureGit @('init', '-q')
    Invoke-FixtureGit @('checkout', '-q', '-b', 'agent/fixture')
    Write-Text 'src/foreign.py' "x = 1`n"
    Write-Text 'src/own.py' "y = 1`n"
    Write-Text '.gitignore' ".github/hooks/`n.github/af-env.conf`n"
    Invoke-FixtureGit @('add', '--', 'src/foreign.py', 'src/own.py', '.gitignore')
    Invoke-FixtureGit @('commit', '-q', '-m', 'base')
    Write-Text 'src/foreign.py' "x = 2  # someone else's fix`n"
    Write-Text 'notes-wip.txt' "untracked foreign notes`n"
}

$dialects = @('ps')
if ($bashExe) { $dialects += 'sh' }
$verdicts = @{}

try {
    foreach ($d in $dialects) {
        Reset-Fixture
        $sc = Start-Session 's1' $d
        Write-Text 'src/own.py' "y = 2  # this session's edit`n"
        $base = Join-Path $fixture '.github/logs/.worktree-baseline-s1'
        $baseText = if (Test-Path $base) { Get-Content $base -Raw } else { '' }
        Add-Result "F01_${d}_session_start_records_the_foreign_paths" (($baseText -match 'src/foreign.py') -and ($baseText -match 'notes-wip.txt') -and ($baseText -notmatch 'own.py')) "baseline: $baseText | hook: $($sc.Out)"
        $status = (git -C $fixture status --porcelain --untracked-files=all 2>$null) -join "`n"
        Add-Result "F02_${d}_the_baseline_is_not_itself_tracked" ($status -notmatch '\.github/logs') "git status: $status"

        $cases = [ordered]@{
            "F03_${d}_restore_of_a_foreign_path_asks"            = @('git restore src/foreign.py', 'ask')
            "F04_${d}_restore_of_a_self_dirtied_path_is_not_held" = @('git restore src/own.py', 'allow')
            "F05_${d}_checkout_dash_dash_dot_asks"                = @('git checkout -- .', 'ask')
            "F06_${d}_a_bare_stash_asks"                          = @('git stash', 'ask')
            "F07_${d}_stash_list_is_not_held"                     = @('git stash list', 'allow')
            "F08_${d}_restore_staged_only_is_not_held"            = @('git restore --staged src/foreign.py', 'allow')
            "F09_${d}_clean_of_foreign_untracked_asks"            = @('git clean -fd', 'ask')
            "F10_${d}_a_quoted_and_dash_C_path_asks"              = @("git -C `"$($fixture -replace '\\','/')`" restore `"src/foreign.py`"", 'ask')
            "F11_${d}_a_directory_spec_covers_the_file"           = @('git checkout -- src', 'ask')
        }
        foreach ($name in $cases.Keys) {
            $cmd, $want = $cases[$name]
            $r = Pre 's1' $d $cmd
            $ok = ($r.Decision -eq $want) -and ($want -ne 'ask' -or $r.Reason -match 'foreign\.py|notes-wip\.txt')
            Add-Result $name $ok "cmd: $cmd | got: $($r.Decision) | $($r.Reason)"
            $verdicts["$($name.Substring(4))"] = $r.Decision
        }

        $other = Pre 's2' $d 'git restore src/foreign.py'
        Add-Result "F12_${d}_a_session_without_a_baseline_degrades_to_the_classifier" ($other.Decision -eq 'allow') "got: $($other.Decision) | $($other.Reason)"

        # Reconciliation: the foreign change is discarded behind the guard's back, then a new session starts.
        Invoke-FixtureGit @('checkout', '--', 'src/foreign.py')
        $next = Start-Session 's3' $d
        Add-Result "F13_${d}_a_discarded_foreign_change_is_reported_at_the_next_session" (($next.Context -match 'AF WARNING') -and ($next.Context -match 'src/foreign.py')) "context: $($next.Context)"

        Reset-Fixture
        $null = Start-Session 's4' $d
        Invoke-FixtureGit @('add', '--', 'src/foreign.py')
        Invoke-FixtureGit @('commit', '-q', '-m', 'keep the fix')
        $after = Start-Session 's5' $d
        Add-Result "F14_${d}_a_committed_foreign_change_is_not_reported" ($after.Context -notmatch 'src/foreign.py') "context: $($after.Context)"
    }

    if ($bashExe) {
        $diff = @($verdicts.Keys | Where-Object { $_ -like 'ps_*' } | Where-Object {
                $verdicts[$_] -ne $verdicts[('sh_' + $_.Substring(3))] })
        Add-Result 'F15_both_dialects_give_the_same_verdicts' ($diff.Count -eq 0) "differ: $($diff -join ', ')"
    } else {
        Add-Result 'F15_both_dialects_give_the_same_verdicts' $false 'no bash found -- this case would prove nothing'
    }
} finally {
    $env:AF_CONF_PATH = $prevConf
    Remove-Item $fixture -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output '===== Foreign-work guard tests (issue #120) ====='
$failed = 0
foreach ($k in $results.Keys) {
    if ($results[$k]) {
        Write-Output "PASS  $k"
    } else {
        $failed++
        Write-Output "FAIL  $k"
        Write-Output "      $($details[$k])"
    }
}
Write-Output "----- $($results.Count - $failed)/$($results.Count) passed -----"
if ($failed -gt 0) { exit 1 }
exit 0
