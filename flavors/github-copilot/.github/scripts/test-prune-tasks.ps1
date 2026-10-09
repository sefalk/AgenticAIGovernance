# Regression suite for prune-tasks.py (#396).
#
# createAndRunTask writes only label/type/command/args/isBackground/
# problemMatcher/group, never `detail`, so a task without `detail` was minted by
# an agent. The MP project held 227 tasks, 196 of them agent-minted. The prune
# removes those and keeps every curated task, by default as a dry run.

# Continue, not Stop: PowerShell 5.1 turns a native command's stderr into a
# terminating error under Stop, and case C asserts on exactly that stderr.
$ErrorActionPreference = 'Continue'
$scriptDir = $PSScriptRoot
$prune = Join-Path $scriptDir 'prune-tasks.py'

$py = $null
foreach ($c in @('python', 'python3', 'py')) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { $py = $c; break }
}
if (-not $py) { Write-Output 'BLOCKED: no python on PATH'; exit 2 }

$results = [ordered]@{}
$details = @{}

$curated = @{ label = 'lint: changed files'; type = 'shell'; command = '.github/scripts/run-lint.ps1'; args = @('-Scope', 'changed'); detail = 'curated' }
$minted = @{ label = 'lint: changed scope (wit9999)'; type = 'shell'; command = '.github/scripts/run-lint.ps1'; args = @('-Scope', 'changed') }
$mintedDep = @{ label = 'prepare (wit9999)'; type = 'shell'; command = '.github/scripts/run-tests.ps1' }
$curatedDep = @{ label = 'tests: after prepare'; type = 'shell'; command = '.github/scripts/run-tests.ps1'; detail = 'curated'; dependsOn = 'prepare (wit9999)' }

function New-Workspace([string]$Json) {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "af-prune-$(Get-Random)"
    New-Item -ItemType Directory -Path (Join-Path $dir '.vscode') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dir '.vscode/tasks.json'), $Json)
    return $dir
}

function Invoke-Prune([string]$Dir, [string[]]$Extra) {
    $out = & $py $prune --workspace $Dir @Extra 2>&1 | Out-String
    return @{ Output = $out; Exit = $LASTEXITCODE }
}

function Get-Labels([string]$Dir) {
    $j = Get-Content (Join-Path $Dir '.vscode/tasks.json') -Raw | ConvertFrom-Json
    return @($j.tasks | ForEach-Object { $_.label })
}

$doc = @{ version = '2.0.0'; tasks = @($curated, $minted, $mintedDep, $curatedDep); inputs = @(@{ id = 'x'; type = 'promptString'; description = 'kept' }) } |
    ConvertTo-Json -Depth 6

# A. The default is a dry run: it names what would go and touches nothing.
$ws = New-Workspace $doc
try {
    $before = [System.IO.File]::ReadAllBytes((Join-Path $ws '.vscode/tasks.json'))
    $r = Invoke-Prune $ws @()
    $after = [System.IO.File]::ReadAllBytes((Join-Path $ws '.vscode/tasks.json'))
    $results['A1_dry_run_exits_zero'] = ($r.Exit -eq 0)
    $results['A2_dry_run_names_the_minted_task'] = ($r.Output -match [regex]::Escape('lint: changed scope (wit9999)'))
    $results['A3_dry_run_changes_nothing'] = ([Convert]::ToBase64String($before) -eq [Convert]::ToBase64String($after))
    $results['A4_no_backup_on_a_dry_run'] = (@(Get-ChildItem (Join-Path $ws '.vscode') -Filter 'tasks.json.bak-*').Count -eq 0)
    $details['A2_dry_run_names_the_minted_task'] = $r.Output
} finally { Remove-Item $ws -Recurse -Force -ErrorAction SilentlyContinue }

# B. --apply removes agent-minted tasks, keeps curated ones and other keys, backs up.
$ws = New-Workspace $doc
try {
    $before = [System.IO.File]::ReadAllText((Join-Path $ws '.vscode/tasks.json'))
    $r = Invoke-Prune $ws @('--apply')
    $labels = Get-Labels $ws
    $j = Get-Content (Join-Path $ws '.vscode/tasks.json') -Raw | ConvertFrom-Json
    $bak = @(Get-ChildItem (Join-Path $ws '.vscode') -Filter 'tasks.json.bak-*')
    $results['B1_apply_exits_zero'] = ($r.Exit -eq 0)
    $results['B2_minted_task_removed'] = ($labels -notcontains 'lint: changed scope (wit9999)')
    $results['B3_curated_tasks_kept'] = ($labels -contains 'lint: changed files' -and $labels -contains 'tests: after prepare')
    # A curated task that depends on a minted one would break if its dependency went.
    $results['B4_a_dependency_of_a_kept_task_is_kept'] = ($labels -contains 'prepare (wit9999)')
    $results['B5_other_top_level_keys_kept'] = ($j.inputs.Count -eq 1 -and $j.version -eq '2.0.0')
    $results['B6_backup_holds_the_original'] = ($bak.Count -eq 1 -and [System.IO.File]::ReadAllText($bak[0].FullName) -eq $before)
    $details['B3_curated_tasks_kept'] = ($labels -join ' | ')
} finally { Remove-Item $ws -Recurse -Force -ErrorAction SilentlyContinue }

# C. A file it cannot parse is reported and left alone, never rewritten.
$ws = New-Workspace ("// comment`n" + $doc)
try {
    $before = [System.IO.File]::ReadAllText((Join-Path $ws '.vscode/tasks.json'))
    $r = Invoke-Prune $ws @('--apply')
    $results['C1_unparsable_file_fails_loudly'] = ($r.Exit -ne 0 -and $r.Output -match 'JSON')
    $results['C2_unparsable_file_untouched'] = ([System.IO.File]::ReadAllText((Join-Path $ws '.vscode/tasks.json')) -eq $before)
    $details['C1_unparsable_file_fails_loudly'] = "exit $($r.Exit): $($r.Output)"
} finally { Remove-Item $ws -Recurse -Force -ErrorAction SilentlyContinue }

# D. Nothing to prune is a clean no-op, not a rewrite.
$ws = New-Workspace (@{ version = '2.0.0'; tasks = @($curated) } | ConvertTo-Json -Depth 6)
try {
    $r = Invoke-Prune $ws @('--apply')
    $results['D1_nothing_to_prune_writes_no_backup'] = ($r.Exit -eq 0 -and @(Get-ChildItem (Join-Path $ws '.vscode') -Filter 'tasks.json.bak-*').Count -eq 0)
} finally { Remove-Item $ws -Recurse -Force -ErrorAction SilentlyContinue }

$failed = 0
foreach ($k in $results.Keys) {
    if ($results[$k]) { Write-Output "PASS  $k" }
    else {
        $failed++
        Write-Output "FAIL  $k"
        if ($details[$k]) { Write-Output "      $($details[$k])" }
    }
}
Write-Output "----- $($results.Count - $failed)/$($results.Count) passed -----"
if ($failed -gt 0) { exit 1 }
exit 0
