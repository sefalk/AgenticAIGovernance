# Regression suite: a session without Python is told once which gates are off (#342).
#
# #331 settled that a missing interpreter degrades rather than blocks. Each hook
# then said so on its own, per call, where nobody reads it back -- and on a
# machine without Python most of the suite is off, with no single place saying
# which part. SessionStart now says it once. This suite holds the announcement
# to the truth: the expected list is derived here independently, transitively
# through the shared helpers, so a new Python-backed hook or helper that the
# announcement misses fails here instead of going unmentioned.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$hookDir = Join-Path (Split-Path -Parent $scriptDir) 'hooks/scripts'

. (Join-Path $scriptDir '_suite_env.ps1')
$python = Get-AfSuitePython $scriptDir
if (-not $python) {
    Write-Host 'SKIP: no Python 3 interpreter found; cannot derive the expected list.'
    exit 0
}

$results = [ordered]@{}
$details = [ordered]@{}
function Add-Result([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

$derive = @'
import json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
GUARD = {"af_require_python", "af_deny_no_python"}
def dialect(ext, common, fn_rx, token):
    text = (root / common).read_text(encoding="utf-8")
    bodies = {m.group(1): m.group(2) for m in re.finditer(fn_rx, text, re.M | re.S)}
    using = {n for n, b in bodies.items() if token in b and n not in GUARD}
    grew = True
    while grew:
        grew = False
        for n, b in bodies.items():
            if n in using or n in GUARD:
                continue
            if any(re.search(r"(?<![\w-])" + re.escape(u) + r"(?![\w-])", b) for u in using):
                using.add(n)
                grew = True
    refused, degraded = [], []
    for path in sorted(root.glob("*." + ext)):
        if path.name.startswith("_") or path.stem == "session-context":
            continue
        body = path.read_text(encoding="utf-8")
        if re.search(r"\baf_require_python\b", body):
            refused.append(path.stem)
        elif token in body or any(re.search(r"(?<![\w-])" + re.escape(u) + r"(?![\w-])", body) for u in using):
            degraded.append(path.stem)
    return {"refused": refused, "degraded": degraded}
print(json.dumps({
    "ps1": dialect("ps1", "_common.ps1", r"^function\s+([\w-]+)\s*\{(.*?)^\}", "AfPython"),
    "sh": dialect("sh", "_common.sh", r"^([a-z_]+)\(\)\s*\{(.*?)^\}", "AF_PYTHON"),
}))
'@

function Get-Notice([string]$Context) {
    $marker = 'no working Python interpreter'
    $count = ([regex]::Matches($Context, [regex]::Escape($marker))).Count
    $deg = [regex]::Match($Context, 'Running without their Python-backed check: ([^.]*)\.').Groups[1].Value
    $ref = [regex]::Match($Context, 'Refusing every call they guard: ([^.]*)\.').Groups[1].Value
    $split = { param($s) @($s -split ',\s*' | Where-Object { $_ -and $_ -ne 'none' } | Sort-Object) }
    return [pscustomobject]@{ Count = $count; Degraded = (& $split $deg); Refused = (& $split $ref) }
}

function Get-HookContext([string]$Raw) {
    try { return [string](($Raw | ConvertFrom-Json).hookSpecificOutput.additionalContext) } catch { return '' }
}

function Compare-List([string[]]$Expected, [string[]]$Actual) {
    return ((@($Expected | Sort-Object) -join ',') -eq (@($Actual | Sort-Object) -join ','))
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("af342-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $deriveFile = Join-Path $tmp 'derive.py'
    [IO.File]::WriteAllText($deriveFile, $derive)
    $ErrorActionPreference = 'Continue'
    $expected = & $python $deriveFile $hookDir 2>&1 | Out-String | ConvertFrom-Json
    $ErrorActionPreference = 'Stop'

    $psHook = Join-Path $hookDir 'session-context.ps1'
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $savedPath = $env:PATH
    $savedOverride = $env:AF_PYTHON_OVERRIDE
    try {
        # C:\Windows is left out on purpose: the py launcher lives there.
        $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
        $env:AF_PYTHON_OVERRIDE = ''
        $rawOff = '{}' | & $psExe -NoProfile -ExecutionPolicy Bypass -File $psHook 2>$null | Out-String
    } finally {
        $env:PATH = $savedPath
        $env:AF_PYTHON_OVERRIDE = $savedOverride
    }
    $rawOn = '{}' | & $psExe -NoProfile -ExecutionPolicy Bypass -File $psHook 2>$null | Out-String

    $off = Get-Notice (Get-HookContext $rawOff)
    Add-Result 'N1_ps1_announces_once_without_python' ($off.Count -eq 1) "count=$($off.Count) output=$($rawOff.Trim())"
    Add-Result 'N2_ps1_names_every_python_backed_hook' `
        ((Compare-List $expected.ps1.degraded $off.Degraded) -and (Compare-List $expected.ps1.refused $off.Refused)) `
        "expected degraded=[$($expected.ps1.degraded -join ', ')] refused=[$($expected.ps1.refused -join ', ')]; got degraded=[$($off.Degraded -join ', ')] refused=[$($off.Refused -join ', ')]"
    Add-Result 'N3_ps1_is_silent_with_python' ((Get-Notice (Get-HookContext $rawOn)).Count -eq 0 -and (Get-HookContext $rawOn)) "output=$($rawOn.Trim())"

    $bash = @('C:\Program Files\Git\bin\bash.exe', '/bin/bash', '/usr/bin/bash') | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($bash) {
        $shHook = (Join-Path $hookDir 'session-context.sh') -replace '\\', '/'
        $runner = Join-Path $tmp 'run.sh'
        [IO.File]::WriteAllText($runner, "export PATH=/usr/bin:/bin`nexport AF_PYTHON_OVERRIDE=`necho '{}' | bash `"$shHook`"`n")
        $shOff = & $bash ($runner -replace '\\', '/') 2>$null | Out-String
        $shNotice = Get-Notice (Get-HookContext $shOff)
        Add-Result 'N4_sh_announces_once_without_python' ($shNotice.Count -eq 1) "count=$($shNotice.Count) output=$($shOff.Trim())"
        Add-Result 'N5_sh_names_refusing_and_degraded_hooks' `
            ((Compare-List $expected.sh.degraded $shNotice.Degraded) -and (Compare-List $expected.sh.refused $shNotice.Refused)) `
            "expected degraded=[$($expected.sh.degraded -join ', ')] refused=[$($expected.sh.refused -join ', ')]; got degraded=[$($shNotice.Degraded -join ', ')] refused=[$($shNotice.Refused -join ', ')]"

        # #168: the git pre-commit stays fail-open without Python (#331), but must
        # name every guard it skipped -- a skipped guard otherwise looks like a pass.
        $gitHook = Join-Path (Split-Path -Parent $hookDir) 'git/pre-commit'
        $dispatch = [regex]::Match((Get-Content $gitHook -Raw), 'for checker in ([^;\r\n]+);').Groups[1].Value
        $guards = @($dispatch -split '\s+' | Where-Object { $_ -like '*.py' })
        $repo = Join-Path $tmp 'repo'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        $ErrorActionPreference = 'Continue'
        git -C $repo init -q 2>&1 | Out-Null
        $ErrorActionPreference = 'Stop'
        $commitRunner = Join-Path $tmp 'commit.sh'
        [IO.File]::WriteAllText($commitRunner, "export PATH=/usr/bin:/bin:/mingw64/bin`ncd `"$($repo -replace '\\', '/')`"`nsh `"$($gitHook -replace '\\', '/')`" 2>&1`necho `"EXIT=`$?`"`n")
        $commitOut = & $bash ($commitRunner -replace '\\', '/') 2>&1 | Out-String
        $missing = @($guards | Where-Object { $commitOut -notmatch [regex]::Escape($_) })
        Add-Result 'N6_git_precommit_names_every_skipped_guard_and_stays_open' `
            ($guards.Count -gt 0 -and $missing.Count -eq 0 -and $commitOut -match 'did NOT run' -and $commitOut -match 'EXIT=0') `
            "guards=[$($guards -join ', ')] missing=[$($missing -join ', ')] output=$($commitOut.Trim())"
    } else {
        Write-Output '  SKIP  N4/N5/N6 -- no bash on this machine'
    }
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output '===== python-missing notice tests (issue #342) ====='
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
