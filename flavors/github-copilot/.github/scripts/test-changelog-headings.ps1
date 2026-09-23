# Regression tests for the CHANGELOG heading guard (issue #322).
#
# The defect the guard exists to stop is a loop, not five typos. The correct
# way to add an entry is to append under the existing `###` heading of that
# kind. In a 6,800-line file nothing tells an author that the heading already
# exists 1,300 lines up, so a second one gets created; the next author now
# faces an ambiguous "the existing heading" and picks either, which makes the
# third. `[1.22.0]` reached six `### Changed` that way. Deleting the six fixes
# six instances and prevents none.
#
# The decision the issue left open -- what to do about already-released
# sections -- is answered here as neither of its two options but as the
# combination that dominates both:
#
#   [Unreleased]        strict. Zero duplicates, zero non-Keep-a-Changelog
#                       kinds. This is the only section anyone writes into,
#                       so this is where the loop can be cut.
#   released sections   ratchet. A released section is a record of what
#                       shipped; rewriting its structure is a different
#                       decision from preventing new duplicates. The counts
#                       are a ceiling that may fall and never rise.
#
# "Unreleased-only" was rejected because it stops asserting anything the
# moment a release is cut -- and 1.22.0 accumulated its six while it *was*
# [Unreleased]. Under the rule above that cannot recur: a section is strict
# for its whole writable life and enters the ratchet at zero.
#
# Run from anywhere:
#   powershell -File .github/scripts/test-changelog-headings.ps1
# Exits non-zero if any scenario fails (CI-friendly).
$ErrorActionPreference = 'Continue'

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRootAF = (Resolve-Path (Join-Path $scriptDir '..' | Join-Path -ChildPath '..')).Path
$checker = Join-Path $scriptDir 'check-changelog-headings.py'
$shippedChangelog = Join-Path $repoRootAF 'CHANGELOG.md'

# Recorded ceilings. These live in the test rather than only in the checker so
# that raising one costs an edit a reviewer sees in the diff of a *test*.
$maxDuplicateSections = 4
$maxNonStandardKinds = 19

function Resolve-Python {
    foreach ($c in @((Join-Path $repoRootAF '.venv/Scripts/python.exe'),
                     (Join-Path $repoRootAF '.venv/bin/python'))) {
        if (Test-Path $c) { return @($c) }
    }
    foreach ($name in @('python3', 'python')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            $v = & $cmd.Source --version 2>&1
            if ($LASTEXITCODE -eq 0 -and $v -match 'Python 3') { return @($cmd.Source) }
        }
    }
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) { return @($py.Source, '-3') }
    return $null
}

$python = @(Resolve-Python)
if ($python.Count -eq 0 -or -not $python[0]) {
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run CHANGELOG heading tests.'
    exit 0
}
$pyExe = $python[0]
$pyPre = if ($python.Count -gt 1) { $python[1..($python.Count - 1)] } else { @() }

$results = [ordered]@{}
$details = [ordered]@{}
$fixtures = @()

# A path with a space in it, because a guard that only works on tidy paths is
# a guard that stops working the day someone checks out under "My Documents".
function New-Fixture {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("af322 fixture " + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $script:fixtures += $dir
    return $dir
}

function Write-Text([string]$Path, [string]$Text) {
    $clean = $Text -replace "`r", ''
    [System.IO.File]::WriteAllText($Path, $clean, (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-Checker([string[]]$ArgList) {
    $out = & $pyExe @pyPre $checker @ArgList 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}

try {
    # ── A. the guard is present and agrees with the repository it ships in ──

    $results['A1_checker_ships_with_the_suite'] = (Test-Path $checker)
    $details['A1_checker_ships_with_the_suite'] = "expected $checker"

    $shipped = Invoke-Checker @($shippedChangelog)
    $results['A2_shipped_changelog_passes'] = ($shipped.Code -eq 0)
    $details['A2_shipped_changelog_passes'] = "exit $($shipped.Code): $($shipped.Out)"

    # The ratchet is only a ratchet if [Unreleased] contributes nothing to it.
    # A section that is allowed to carry legacy duplicates while it is still
    # being written is how 1.22.0 got six.
    $results['A10_unreleased_contributes_nothing_to_the_baseline'] =
        ($shipped.Out -notmatch '(?m)^CH00\d \[Unreleased\]')
    $details['A10_unreleased_contributes_nothing_to_the_baseline'] = $shipped.Out

    $base = Invoke-Checker @('--print-baseline')
    $dupCeiling = if ($base.Out -match 'duplicate-sections=(\d+)') { [int]$Matches[1] } else { -1 }
    $kindCeiling = if ($base.Out -match 'nonstandard-kinds=(\d+)') { [int]$Matches[1] } else { -1 }
    $results['A9_legacy_ceilings_never_grow'] =
        ($dupCeiling -ge 0 -and $dupCeiling -le $maxDuplicateSections -and
         $kindCeiling -ge 0 -and $kindCeiling -le $maxNonStandardKinds)
    $details['A9_legacy_ceilings_never_grow'] =
        "duplicate-sections=$dupCeiling (max $maxDuplicateSections), nonstandard-kinds=$kindCeiling (max $maxNonStandardKinds)"

    # ── B. what the guard must reject ──────────────────────────────────────

    $dir = New-Fixture

    $clean = @'
# Changelog

## [Unreleased]

### Added

- one

### Fixed

- two

## [1.0.0] -- 2026-01-01

### Added

- three
'@
    # Normalise first: this file is stored with CRLF, and `(?m)$` in .NET
    # matches before the `\n`, so every `^...$` below would silently fail to
    # match with the `\r` still in place -- and a fixture that was never
    # modified makes the rejection cases pass against clean input.
    $clean = $clean -replace "`r", ''
    $cleanPath = Join-Path $dir 'clean.md'
    Write-Text $cleanPath $clean
    $r = Invoke-Checker @($cleanPath)
    $results['B1_clean_changelog_passes'] = ($r.Code -eq 0)
    $details['B1_clean_changelog_passes'] = "exit $($r.Code): $($r.Out)"

    $dupUnreleased = $clean -replace '(?m)^## \[1\.0\.0\] -- 2026-01-01$', "### Added`n`n- four`n`n## [1.0.0] -- 2026-01-01"
    $dupPath = Join-Path $dir 'dup-unreleased.md'
    Write-Text $dupPath $dupUnreleased
    $r = Invoke-Checker @($dupPath)
    $results['B2_duplicate_kind_in_unreleased_is_rejected'] = ($r.Code -ne 0 -and $r.Out -match 'CH001')
    $details['B2_duplicate_kind_in_unreleased_is_rejected'] = "exit $($r.Code): $($r.Out)"

    # The report has to be actionable: section, kind and EVERY line number.
    # "there is a duplicate somewhere in a 6,800-line file" is not a finding.
    $results['B3_report_names_section_kind_and_every_line'] =
        ($r.Out -match '\[Unreleased\]' -and $r.Out -match 'Added' -and $r.Out -match '\b5\b' -and $r.Out -match '\b13\b')
    $details['B3_report_names_section_kind_and_every_line'] = $r.Out

    $badKind = $clean -replace '(?m)^### Fixed$', '### Notes'
    $badKindPath = Join-Path $dir 'bad-kind.md'
    Write-Text $badKindPath $badKind
    $r = Invoke-Checker @($badKindPath)
    $results['B4_non_keepachangelog_kind_in_unreleased_is_rejected'] = ($r.Code -ne 0 -and $r.Out -match 'CH002')
    $details['B4_non_keepachangelog_kind_in_unreleased_is_rejected'] = "exit $($r.Code): $($r.Out)"

    # ── C. the ratchet: released sections are counted, not forbidden ────────

    $oneLegacy = $clean -replace '(?m)^- three$', "- three`n`n### Added`n`n- four"
    $oneLegacyPath = Join-Path $dir 'one-legacy.md'
    Write-Text $oneLegacyPath $oneLegacy
    $r = Invoke-Checker @($oneLegacyPath)
    $results['C1_released_duplicate_within_the_ceiling_passes'] = ($r.Code -eq 0)
    $details['C1_released_duplicate_within_the_ceiling_passes'] = "exit $($r.Code): $($r.Out)"

    $many = "# Changelog`n`n## [Unreleased]`n`n### Added`n`n- one`n"
    foreach ($n in 1..($maxDuplicateSections + 1)) {
        $many += "`n## [0.$n.0] -- 2026-01-0$n`n`n### Added`n`n- a`n`n### Added`n`n- b`n"
    }
    $manyPath = Join-Path $dir 'over-ceiling.md'
    Write-Text $manyPath $many
    $r = Invoke-Checker @($manyPath)
    $results['C2_released_duplicates_above_the_ceiling_are_rejected'] = ($r.Code -ne 0)
    $details['C2_released_duplicates_above_the_ceiling_are_rejected'] = "exit $($r.Code): $($r.Out)"

    # ── D. the guard must not be fooled, and must not crash ─────────────────

    # A CHANGELOG documents code, so it contains fenced blocks, and a fenced
    # block can contain a line starting with `### `. Counting those as
    # headings would make the guard report findings nobody can fix.
    $fenced = @'
# Changelog

## [Unreleased]

### Added

- one

```markdown
### Added
### Fixed
```
'@
    $fencedPath = Join-Path $dir 'fenced.md'
    Write-Text $fencedPath $fenced
    $r = Invoke-Checker @($fencedPath)
    $results['D1_heading_inside_a_fenced_block_is_not_a_heading'] = ($r.Code -eq 0)
    $details['D1_heading_inside_a_fenced_block_is_not_a_heading'] = "exit $($r.Code): $($r.Out)"

    $emptyPath = Join-Path $dir 'no-headings.md'
    Write-Text $emptyPath "# Changelog`n`n## [Unreleased]`n`nNothing yet.`n"
    $r = Invoke-Checker @($emptyPath)
    $results['D2_section_without_headings_does_not_crash'] = ($r.Code -eq 0 -and $r.Out -notmatch 'Traceback')
    $details['D2_section_without_headings_does_not_crash'] = "exit $($r.Code): $($r.Out)"

    # A guard that cannot read its input refuses rather than waves through
    # (#251) -- but it says so in one line instead of a stack trace.
    $r = Invoke-Checker @((Join-Path $dir 'does-not-exist.md'))
    $results['D3_missing_file_refuses_without_a_traceback'] = ($r.Code -ne 0 -and $r.Out -notmatch 'Traceback')
    $details['D3_missing_file_refuses_without_a_traceback'] = "exit $($r.Code): $($r.Out)"

    # Negative control (#112 shape): the shipped CHANGELOG with one duplicate
    # injected into [Unreleased] must fail. Without this, a guard that was
    # accidentally emptied would pass A2 and look healthy.
    $injected = Join-Path $dir 'injected.md'
    $shippedText = [System.IO.File]::ReadAllText($shippedChangelog)
    $marker = "`n### Changed`n`n- injected duplicate, negative control`n"
    $idx = $shippedText.IndexOf("`n## [1.23.0]")
    if ($idx -lt 0) { $idx = $shippedText.Length }
    Write-Text $injected ($shippedText.Substring(0, $idx) + $marker + $shippedText.Substring($idx))
    $r = Invoke-Checker @($injected)
    $results['D4_negative_control_known_bad_input_fails'] = ($r.Code -ne 0 -and $r.Out -match 'CH001')
    $details['D4_negative_control_known_bad_input_fails'] = "exit $($r.Code): $($r.Out)"
}
finally {
    foreach ($f in $fixtures) { Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host '===== CHANGELOG heading guard tests (issue #322) ====='
$allPass = $true
foreach ($k in $results.Keys) {
    if ($results[$k]) {
        Write-Host ("PASS  {0}" -f $k)
    } else {
        $allPass = $false
        Write-Host ("FAIL  {0}" -f $k)
        if ($details[$k]) { Write-Host ("      {0}" -f $details[$k]) }
    }
}
$passCount = @($results.Values | Where-Object { $_ }).Count
Write-Host ("----- {0}/{1} passed -----" -f $passCount, $results.Count)
if (-not $allPass) { exit 1 }
exit 0
