# Regression suite: no shipped file trips the secret gate on its own (#350).
#
# Since #339 the gate blocks, and a file that matches is refused on every edit
# -- including the suites that test the gate, whose fixtures were literals. An
# agent told to "remove the secret" would delete the fixture and disarm the
# test. So fixtures are assembled at run time, and this suite proves both
# halves: no shipped file matches, and every assembled fixture still does.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$githubDir = Split-Path -Parent $scriptDir
$core = Join-Path $githubDir 'hooks/scripts/scan-secrets.py'

. (Join-Path $scriptDir '_suite_env.ps1')
$python = Get-AfSuitePython $scriptDir
if (-not $python) {
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run the secret core.'
    exit 0
}

$results = [ordered]@{}
$details = [ordered]@{}
function Add-Result([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

# The patterns come from the core itself, so this suite cannot drift from the gate.
$probe = @'
import importlib.util, json, pathlib, sys
core, *roots = sys.argv[1:]
sys.path.insert(0, str(pathlib.Path(core).parent))
spec = importlib.util.spec_from_file_location("scan_secrets", core)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
skip = {"logs", "retros", "__pycache__", ".venv", "node_modules"}
hits = []
for root in map(pathlib.Path, roots):
    files = [root] if root.is_file() else sorted(p for p in root.rglob("*") if p.is_file())
    for path in files:
        if skip & set(path.parts):
            continue
        text = mod.read_text(str(path))
        if text is None:
            continue
        for number, line in enumerate(text.splitlines(), 1):
            names = [name for name, pattern in mod.SECRET_PATTERNS if pattern.search(line)]
            if names:
                hits.append(f"{path.as_posix()}:{number} {', '.join(names)}")
fixtures = json.loads(sys.stdin.read() or "{}")
flagged = {kind: [n for n, p in mod.SECRET_PATTERNS if p.search(text)] for kind, text in fixtures.items()}
print(json.dumps({"hits": hits, "fixtures": flagged}))
'@

$roots = @($githubDir)
if (Test-AfSourceTree $scriptDir) {
    $payloadRoot = Split-Path -Parent $githubDir
    $roots += @('deploy.ps1', 'deploy.sh') | ForEach-Object { Join-Path $payloadRoot $_ } | Where-Object { Test-Path $_ }
}

$kinds = [ordered]@{
    password = 'Generic Secret'
    apikey   = 'Generic Secret'
    aws      = 'AWS Key'
    conn     = 'Connection String'
    privkey  = 'Private Key'
}
$fixtures = [ordered]@{}
foreach ($k in $kinds.Keys) {
    $fixtures[$k] = if (Get-Command Get-AfSecretFixture -ErrorAction SilentlyContinue) { Get-AfSecretFixture $k } else { '' }
}

$probeFile = Join-Path ([IO.Path]::GetTempPath()) ("af350-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.py')
try {
    [IO.File]::WriteAllText($probeFile, $probe)
    $ErrorActionPreference = 'Continue'
    $raw = ($fixtures | ConvertTo-Json -Compress) | & $python $probeFile $core @roots 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
} finally {
    Remove-Item $probeFile -ErrorAction SilentlyContinue
}
$out = $null
try { $out = $raw | ConvertFrom-Json } catch { $out = $null }

if (-not $out) {
    Add-Result 'S0_the_secret_core_can_be_probed' $false "output: $($raw.Trim())"
} else {
    $hits = @($out.hits)
    Add-Result 'S1_no_shipped_file_trips_the_secret_gate' ($hits.Count -eq 0) ("flagged: " + ($hits -join '; '))
    foreach ($k in $kinds.Keys) {
        $got = @($out.fixtures.$k)
        Add-Result "S2_${k}_fixture_is_still_flagged_as_$($kinds[$k] -replace ' ', '_')" ($got -contains $kinds[$k]) "flagged as: $($got -join ', ')"
    }
}

Write-Output '===== secret fixture tests (issue #350) ====='
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
