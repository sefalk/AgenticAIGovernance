# Regression tests for the Python quality gate's diff scope (issue #45).
#
# The defect: the gate's wording is function-scoped -- "verify changed public
# functions include non-trivial docstrings" -- but check-python-quality.py walks
# the whole module AST. Touching one function in a file therefore demanded
# docstrings and annotations for every other public function in it. In WIT #3105
# that forced ~90 lines onto six unrelated methods and left no correct path:
# either edit out of scope, or bypass a HARD gate.
#
# What is under test is the checker itself, driven in throwaway git repos with
# real commits and a real base branch. Asserting against this checkout would
# repeat the #37 mistake: a test that inherits the developer's working tree
# proves nothing about the gate.
#
# Run from anywhere:
#   powershell .github/scripts/test-quality-gate.ps1
# Exits non-zero if any scenario fails (CI-friendly).

$ErrorActionPreference = 'Continue'

$scriptDir = Split-Path -Parent $PSCommandPath
$ghRoot    = (Resolve-Path (Join-Path $scriptDir '..')).Path
$repoRoot  = (Resolve-Path (Join-Path $ghRoot '..')).Path
$checker   = Join-Path $ghRoot 'scripts/check-python-quality.py'

function Resolve-Python {
    foreach ($c in @(
        (Join-Path $repoRoot '.venv/Scripts/python.exe'),
        (Join-Path $repoRoot '.venv/bin/python')
    )) { if (Test-Path $c) { return $c } }
    foreach ($name in @('python3', 'python')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            $v = & $cmd.Source --version 2>&1
            if ($LASTEXITCODE -eq 0 -and $v -match 'Python 3') { return $cmd.Source }
        }
    }
    return $null
}

$python = Resolve-Python
if (-not $python) {
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run quality gate tests.'
    exit 0
}

$script:passed = 0
$script:failed = 0

# ---------------------------------------------------------------- fixtures --

# Ten public functions with neither annotations nor docstrings. Whole-file
# scanning reports all of them; diff scoping must report none.
$UNTOUCHED_HELPERS = (1..10 | ForEach-Object {
    "def helper$_(x):`n    return x + $_`n"
}) -join "`n"

$DOCUMENTED_TOUCHED = @'
def touched(a: int, b: int) -> int:
    """Combine two operands.

    Parameters
    ----------
    a : int
        First operand.
    b : int
        Second operand.

    Returns
    -------
    int
        The combination.
    """
    return a + b
'@

$DOCUMENTED_TOUCHED_EDITED = $DOCUMENTED_TOUCHED -replace 'return a \+ b', 'return b + a'

$MODULE_HEADER = @'
"""Sample module."""
# copilot:generated | tester | 2026-08-04


'@

function New-Module {
    param([string]$Touched, [string]$Extra = '')
    $body = $MODULE_HEADER + $Touched + "`n`n" + $UNTOUCHED_HELPERS
    if ($Extra) { $body += "`n" + $Extra }
    return $body
}

# Builds the workflow topology: a `dev` base commit, then a feature branch
# checked out on top. -NoBaseBranch leaves the base ref unresolvable so the
# fallback path can be exercised; -NoGit skips git entirely.
function New-QualityRepo {
    param(
        [hashtable]$BaseFiles,
        [switch]$NoBaseBranch,
        [switch]$NoGit
    )

    $repo = Join-Path ([IO.Path]::GetTempPath()) ("qualgate-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $repo 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo '.github') -Force | Out-Null
    "SRC_DIR=src`nBASE_BRANCH=dev" | Set-Content (Join-Path $repo '.github/af-env.conf') -Encoding utf8

    foreach ($k in $BaseFiles.Keys) {
        $full = Join-Path $repo $k
        New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
        [IO.File]::WriteAllText($full, $BaseFiles[$k])
    }

    if ($NoGit) { return $repo }

    Push-Location $repo
    git init -q 2>&1 | Out-Null
    # Without this every fixture write emits a CRLF warning on stderr, which
    # buries the actual test output.
    git config core.autocrlf false 2>&1 | Out-Null
    git config core.safecrlf false 2>&1 | Out-Null
    git checkout -q -b dev 2>&1 | Out-Null
    git add -A 2>&1 | Out-Null
    git -c user.email=fixture@local -c user.name=fixture commit -q -m 'base' 2>&1 | Out-Null
    if ($NoBaseBranch) {
        git branch -m dev main 2>&1 | Out-Null
    }
    git checkout -q -b agent/45-fixture 2>&1 | Out-Null
    Pop-Location
    return $repo
}

function Set-RepoFile {
    param([string]$Repo, [string]$Path, [string]$Content)
    [IO.File]::WriteAllText((Join-Path $Repo $Path), $Content)
}

function Add-RepoCommit {
    param([string]$Repo, [string]$Message = 'phase')
    Push-Location $Repo
    git add -A 2>&1 | Out-Null
    git -c user.email=fixture@local -c user.name=fixture commit -q -m $Message 2>&1 | Out-Null
    Pop-Location
}

function Invoke-Quality {
    param(
        [string]$Repo,
        [string[]]$Files,
        [string]$DiffBase,
        [string]$Checks = 'all'
    )
    $argv = @($checker, '--files') + $Files
    if ($DiffBase) { $argv += @('--diff-base', $DiffBase) }
    if ($Checks -ne 'all') { $argv += @('--checks', $Checks) }

    Push-Location $Repo
    $out = & $python @argv 2>&1 | Out-String
    $code = $LASTEXITCODE
    Pop-Location
    return [pscustomobject]@{ Output = $out; Exit = $code }
}

# -------------------------------------------------------------- assertions --

function Assert-Case {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    if ($Ok) {
        Write-Host "  PASS  $Name"
        $script:passed++
    } else {
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        if ($Detail) { Write-Host ($Detail -split "`n" | Select-Object -First 12 | Out-String) }
        $script:failed++
    }
}

function Assert-GatePass {
    param([string]$Name, $Result)
    Assert-Case $Name ($Result.Exit -eq 0 -and $Result.Output -match 'PYTHON_QUALITY_GATE_PASS') $Result.Output
}

function Assert-GateFail {
    param([string]$Name, $Result, [string]$Mentions)
    $ok = ($Result.Exit -ne 0) -and ($Result.Output -match 'PYTHON_QUALITY_GATE_FAIL')
    if ($ok -and $Mentions) { $ok = $Result.Output -match [regex]::Escape($Mentions) }
    Assert-Case $Name $ok $Result.Output
}

Write-Host ''
Write-Host 'Python quality gate -- diff scope (issue #45)'
Write-Host '============================================='

# ------------------------------------------------------------------- tests --

# 1. The WIT #3105 shape: one function edited, ten untouched and undocumented.
$repo = New-QualityRepo @{ 'src/app.py' = (New-Module $DOCUMENTED_TOUCHED) }
Set-RepoFile $repo 'src/app.py' (New-Module $DOCUMENTED_TOUCHED_EDITED)
Assert-GatePass 'untouched undocumented functions are out of scope' `
    (Invoke-Quality -Repo $repo -Files @('src/app.py') -DiffBase 'dev')

# 2. Without --diff-base the whole-file behaviour is unchanged. A caller that
#    forgets the flag must not silently get a weaker gate.
Assert-GateFail 'no --diff-base still scans the whole file' `
    (Invoke-Quality -Repo $repo -Files @('src/app.py')) 'helper1'

# 3. A function the branch adds is in scope even though the rest is not.
$repo = New-QualityRepo @{ 'src/app.py' = (New-Module $DOCUMENTED_TOUCHED) }
Set-RepoFile $repo 'src/app.py' (New-Module $DOCUMENTED_TOUCHED "def added(x):`n    return x`n")
Assert-GateFail 'newly added public function is in scope' `
    (Invoke-Quality -Repo $repo -Files @('src/app.py') -DiffBase 'dev') 'added'

# 4. A changed function that loses its docstring still fails.
$repo = New-QualityRepo @{ 'src/app.py' = (New-Module $DOCUMENTED_TOUCHED) }
$stripped = "def touched(a: int, b: int) -> int:`n    return b + a`n"
Set-RepoFile $repo 'src/app.py' (New-Module $stripped)
Assert-GateFail 'changed function with no docstring fails' `
    (Invoke-Quality -Repo $repo -Files @('src/app.py') -DiffBase 'dev') 'touched'

# 5. Structure is still enforced on a changed function, not just presence.
$repo = New-QualityRepo @{ 'src/app.py' = (New-Module $DOCUMENTED_TOUCHED) }
$unstructured = "def touched(a: int, b: int) -> int:`n    `"`"`"Combine two operands together.`"`"`"`n    return b + a`n"
Set-RepoFile $repo 'src/app.py' (New-Module $unstructured)
Assert-GateFail 'changed function with unstructured docstring fails' `
    (Invoke-Quality -Repo $repo -Files @('src/app.py') -DiffBase 'dev') 'parameter section'

# 6. Missing annotations on a changed function still fail.
$repo = New-QualityRepo @{ 'src/app.py' = (New-Module $DOCUMENTED_TOUCHED) }
$unannotated = $DOCUMENTED_TOUCHED -replace 'def touched\(a: int, b: int\) -> int:', 'def touched(a, b):'
Set-RepoFile $repo 'src/app.py' (New-Module ($unannotated -replace 'return a \+ b', 'return b + a'))
Assert-GateFail 'changed function without annotations fails' `
    (Invoke-Quality -Repo $repo -Files @('src/app.py') -DiffBase 'dev') 'annotations'

# 7. A file the branch adds has no counterpart in the base: all of it is new.
$repo = New-QualityRepo @{ 'src/app.py' = (New-Module $DOCUMENTED_TOUCHED) }
Set-RepoFile $repo 'src/new_mod.py' "`"`"`"New module.`"`"`"`n# copilot:generated | tester | 2026-08-04`n`n`ndef fresh(x):`n    return x`n"
Assert-GateFail 'untracked new file is entirely in scope' `
    (Invoke-Quality -Repo $repo -Files @('src/new_mod.py') -DiffBase 'dev') 'fresh'

# 8. Changing only a decorator changes the function. The fixture used to make
#    that change by appending a comment, which #86 showed is not a change at
#    all -- comments leave no trace in an AST -- so it now swaps the decorator.
$decorated = @'
def _deco(f):
    return f


def _deco2(f):
    return f


@_deco
def decorated(x):
    return x
'@
$repo = New-QualityRepo @{ 'src/app.py' = ($MODULE_HEADER + $decorated + "`n") }
Set-RepoFile $repo 'src/app.py' ($MODULE_HEADER + ($decorated -replace '(?m)^@_deco$', '@_deco2') + "`n")
Assert-GateFail 'decorator-only change puts the function in scope' `
    (Invoke-Quality -Repo $repo -Files @('src/app.py') -DiffBase 'dev') 'decorated'

# 9. Unresolvable base: fall back to whole-file and say so. Failing wide is the
#    safe direction -- a gate that evaporates when git cannot answer is worse
#    than one that over-reports.
$repo = New-QualityRepo -BaseFiles @{ 'src/app.py' = (New-Module $DOCUMENTED_TOUCHED) } -NoBaseBranch
Set-RepoFile $repo 'src/app.py' (New-Module $DOCUMENTED_TOUCHED_EDITED)
$r = Invoke-Quality -Repo $repo -Files @('src/app.py') -DiffBase 'dev'
Assert-Case 'unresolvable base falls back to whole-file with a notice' `
    (($r.Exit -ne 0) -and ($r.Output -match 'helper1') -and ($r.Output -match 'NOTICE')) $r.Output

# 10. Same fallback outside a git repository.
$repo = New-QualityRepo -BaseFiles @{ 'src/app.py' = (New-Module $DOCUMENTED_TOUCHED_EDITED) } -NoGit
$r = Invoke-Quality -Repo $repo -Files @('src/app.py') -DiffBase 'dev'
Assert-Case 'no git repository falls back to whole-file with a notice' `
    (($r.Exit -ne 0) -and ($r.Output -match 'helper1') -and ($r.Output -match 'NOTICE')) $r.Output

# 11. A suppression the branch adds is still a hard failure.
$repo = New-QualityRepo @{ 'src/app.py' = (New-Module $DOCUMENTED_TOUCHED) }
Set-RepoFile $repo 'src/app.py' (($MODULE_HEADER -replace '# copilot:generated', "import os  # noqa`n# copilot:generated") + $DOCUMENTED_TOUCHED + "`n")
Assert-GateFail 'suppression added by the branch fails' `
    (Invoke-Quality -Repo $repo -Files @('src/app.py') -DiffBase 'dev') 'noqa'

# 12. A suppression the branch inherited is reported, not enforced (decision c).
$inherited = ($MODULE_HEADER -replace '# copilot:generated', "import os  # noqa`n# copilot:generated") + $DOCUMENTED_TOUCHED + "`n"
$repo = New-QualityRepo @{ 'src/app.py' = $inherited }
Set-RepoFile $repo 'src/app.py' ($inherited -replace 'return a \+ b', 'return b + a')
$r = Invoke-Quality -Repo $repo -Files @('src/app.py') -DiffBase 'dev'
Assert-Case 'inherited suppression is ADVISORY, not a failure' `
    (($r.Exit -eq 0) -and ($r.Output -match 'ADVISORY') -and ($r.Output -match 'noqa')) $r.Output

# 13. --checks ignore-hygiene (the tests/ path) honours the same scope.
$repo = New-QualityRepo @{ 'tests/test_app.py' = $inherited }
Set-RepoFile $repo 'tests/test_app.py' ($inherited -replace 'return a \+ b', 'return b + a')
$r = Invoke-Quality -Repo $repo -Files @('tests/test_app.py') -DiffBase 'dev' -Checks 'ignore-hygiene'
Assert-Case 'ignore-hygiene mode honours the diff scope' `
    (($r.Exit -eq 0) -and ($r.Output -match 'ADVISORY')) $r.Output

# 14. A pure deletion produces a `+N,0` hunk with no added lines. Gutting a
#     function must still put it in scope, or removing a body would go unseen.
$gap = "def gap(x):`n    x = x + 1`n    return x`n"
$gapGutted = "def gap(x):`n    return x`n"
$repo = New-QualityRepo @{ 'src/app.py' = ($MODULE_HEADER + $DOCUMENTED_TOUCHED + "`n`n" + $gap) }
Set-RepoFile $repo 'src/app.py' ($MODULE_HEADER + $DOCUMENTED_TOUCHED + "`n`n" + $gapGutted)
Assert-GateFail 'pure deletion puts the surrounding function in scope' `
    (Invoke-Quality -Repo $repo -Files @('src/app.py') -DiffBase 'dev') 'gap'

# 15. A file added and COMMITTED in an earlier phase of this branch is invisible
#     to a HEAD-relative diff, but the merge still ships it. This is the #13
#     defect class, and it is what separates a base-relative diff from a lazy
#     HEAD-relative one -- a mutant swapping the two survived without it.
$repo = New-QualityRepo @{ 'src/app.py' = (New-Module $DOCUMENTED_TOUCHED) }
Set-RepoFile $repo 'src/phase1.py' "`"`"`"Red phase module.`"`"`"`n# copilot:generated | tester | 2026-08-04`n`n`ndef early(x):`n    return x`n"
Add-RepoCommit $repo 'red phase'
Set-RepoFile $repo 'src/app.py' (New-Module $DOCUMENTED_TOUCHED_EDITED)
Assert-GateFail 'file committed in an earlier phase is still in scope' `
    (Invoke-Quality -Repo $repo -Files @('src/phase1.py') -DiffBase 'dev') 'early'

# ===================================================================
# Authored change vs mechanical change (issue #86)
# ===================================================================
#
# Diff scope answers "did the branch touch these lines". A formatter touches
# every line, so the answer is yes for a file the agent never wrote a word of.
# In WIT #3121 -- `ruff format` across 80 files -- that turned a mechanical
# commit into 72 provenance markers, 35 authored docstring sections and 9
# suppression justifications, none of them reviewed, all of them added purely
# to get past a gate. The question the docstring and provenance gates need
# answered is not "did these lines move" but "did the agent author anything".
#
# `ruff format` cannot change an AST. So a file whose AST -- modulo docstring
# whitespace, which the formatter does re-indent -- matches the base is
# mechanical, and the authorship-scoped gates have nothing to say about it.
#
# Two things this must NOT become: an excuse to skip linting (a violation is
# real no matter who wrote it), and an excuse to skip suppression hygiene
# (comments are absent from the AST, so a smuggled `# noqa` looks mechanical).

Write-Host ''
Write-Host 'Authored vs mechanical change (issue #86)'
Write-Host '========================================='

function Invoke-Authored {
    param([string]$Repo, [string[]]$Files, [string]$DiffBase)
    $argv = @($checker, '--list-authored', '--files') + $Files
    if ($DiffBase) { $argv += @('--diff-base', $DiffBase) }

    Push-Location $Repo
    $out = & $python @argv 2>&1 | Out-String
    $code = $LASTEXITCODE
    Pop-Location
    return [pscustomobject]@{ Output = $out; Exit = $code }
}

# A non-zero exit means the query itself failed -- an unimplemented flag makes
# argparse exit 2 -- so every case demands 0. Without that, "the path is not in
# the output" would pass against a checker that produces no output at all.
function Assert-Authored {
    param([string]$Name, $Result, [string]$Path)
    Assert-Case $Name (($Result.Exit -eq 0) -and ($Result.Output -match [regex]::Escape($Path))) $Result.Output
}

function Assert-Mechanical {
    param([string]$Name, $Result, [string]$Path)
    Assert-Case $Name (($Result.Exit -eq 0) -and ($Result.Output -notmatch [regex]::Escape($Path))) $Result.Output
}

# Undocumented, unannotated, and formatted onto one line: exactly the shape the
# docstring gate objects to, so any file it stays in scope for will fail loudly.
$WIDGET_TIGHT = @'
def widget(x, y):
    return {"a": x, "b": y}
'@

# The same function as a formatter would leave it: exploded across lines with a
# magic trailing comma. Different text, identical AST.
$WIDGET_REFLOWED = @'
def widget(x, y):
    return {
        "a": x,
        "b": y,
    }
'@

$SPUN_DOC = @'
def spun(a: int) -> int:
    """Do a thing with the operand.

    Parameters
    ----------
    a : int
        Operand.

    Returns
    -------
    int
        Result.
    """
    return a
'@

# 16. The formatter case itself: text differs on every line of the function,
#     yet nothing was authored.
$repo = New-QualityRepo @{ 'src/app.py' = ($MODULE_HEADER + $WIDGET_TIGHT + "`n") }
Set-RepoFile $repo 'src/app.py' ($MODULE_HEADER + $WIDGET_REFLOWED + "`n")
Assert-Mechanical 'a reformatted file is not authored' `
    (Invoke-Authored -Repo $repo -Files @('src/app.py') -DiffBase 'dev') 'src/app.py'

# 17. A docstring lives in the AST as a string constant, so re-indenting one
#     shifts the tree. Formatters do exactly that, hence "modulo whitespace".
$repo = New-QualityRepo @{ 'src/app.py' = ($MODULE_HEADER + $SPUN_DOC + "`n") }
$reindented = $SPUN_DOC -replace '(?m)^    (?=\S|$)', '        ' -replace '(?m)^        def ', 'def '
Set-RepoFile $repo 'src/app.py' ($MODULE_HEADER + $reindented + "`n")
Assert-Mechanical 'docstring re-indentation alone is not authored' `
    (Invoke-Authored -Repo $repo -Files @('src/app.py') -DiffBase 'dev') 'src/app.py'

# 18. Docstring *content* is the thing the incident smuggled through. Normalising
#     whitespace must not normalise away the words.
$repo = New-QualityRepo @{ 'src/app.py' = ($MODULE_HEADER + $SPUN_DOC + "`n") }
Set-RepoFile $repo 'src/app.py' ($MODULE_HEADER + ($SPUN_DOC -replace 'Do a thing with the operand\.', 'Do a thing with the operand. Never returns zero.') + "`n")
Assert-Authored 'a docstring content change is authored' `
    (Invoke-Authored -Repo $repo -Files @('src/app.py') -DiffBase 'dev') 'src/app.py'

# 19. The obvious direction, asserted so the filter cannot quietly become a
#     blanket bypass.
$repo = New-QualityRepo @{ 'src/app.py' = ($MODULE_HEADER + $WIDGET_TIGHT + "`n") }
Set-RepoFile $repo 'src/app.py' ($MODULE_HEADER + ($WIDGET_TIGHT -replace '"b": y', '"b": y + 1') + "`n")
Assert-Authored 'a code change is authored' `
    (Invoke-Authored -Repo $repo -Files @('src/app.py') -DiffBase 'dev') 'src/app.py'

# 20. No base blob means nothing to compare against. A new file is authored.
$repo = New-QualityRepo @{ 'src/app.py' = ($MODULE_HEADER + $WIDGET_TIGHT + "`n") }
Set-RepoFile $repo 'src/fresh.py' ($MODULE_HEADER + $WIDGET_TIGHT + "`n")
Assert-Authored 'a file absent from the base is authored' `
    (Invoke-Authored -Repo $repo -Files @('src/fresh.py') -DiffBase 'dev') 'src/fresh.py'

# 21. An unparseable file has no AST to compare. Undecidable must mean authored:
#     a filter that fails open would hand every gate an off switch.
$repo = New-QualityRepo @{ 'src/app.py' = ($MODULE_HEADER + $WIDGET_TIGHT + "`n") }
Set-RepoFile $repo 'src/app.py' ($MODULE_HEADER + "def widget(x, y:`n")
Assert-Authored 'an unparseable file is authored' `
    (Invoke-Authored -Repo $repo -Files @('src/app.py') -DiffBase 'dev') 'src/app.py'

# 22. Without a base there is no mechanical/authored distinction to draw.
$repo = New-QualityRepo @{ 'src/app.py' = ($MODULE_HEADER + $WIDGET_TIGHT + "`n") }
Set-RepoFile $repo 'src/app.py' ($MODULE_HEADER + $WIDGET_REFLOWED + "`n")
Assert-Authored 'without --diff-base every file is authored' `
    (Invoke-Authored -Repo $repo -Files @('src/app.py')) 'src/app.py'

# 23. The gate itself. `widget` has no docstring and no annotations and the
#     reformat puts it squarely in the changed ranges -- diff scope alone
#     cannot save it, only authorship can.
$repo = New-QualityRepo @{ 'src/app.py' = ($MODULE_HEADER + $WIDGET_TIGHT + "`n") }
Set-RepoFile $repo 'src/app.py' ($MODULE_HEADER + $WIDGET_REFLOWED + "`n")
Assert-GatePass 'a reformatted file is out of scope for the docstring gate' `
    (Invoke-Quality -Repo $repo -Files @('src/app.py') -DiffBase 'dev')

# 24. Same file, same function, one authored character: the gate is back.
$repo = New-QualityRepo @{ 'src/app.py' = ($MODULE_HEADER + $WIDGET_TIGHT + "`n") }
Set-RepoFile $repo 'src/app.py' ($MODULE_HEADER + ($WIDGET_REFLOWED -replace '"b": y', '"b": y + 1') + "`n")
Assert-GateFail 'a reformat carrying one real edit is still in scope' `
    (Invoke-Quality -Repo $repo -Files @('src/app.py') -DiffBase 'dev') 'widget'

# 25. The hole the AST filter opens if it is applied indiscriminately: comments
#     are not in the tree, so a suppression smuggled into a "formatting only"
#     commit would read as mechanical. Hygiene must not consult authorship.
$repo = New-QualityRepo @{ 'src/app.py' = ($MODULE_HEADER + $WIDGET_TIGHT + "`n") }
Set-RepoFile $repo 'src/app.py' ($MODULE_HEADER + ($WIDGET_REFLOWED -replace 'return \{', 'return {  # noqa') + "`n")
Assert-GateFail 'a suppression added to a mechanical change still fails' `
    (Invoke-Quality -Repo $repo -Files @('src/app.py') -DiffBase 'dev') 'noqa'

# 26. And the converse, which is what made hygiene misfire in the incident: a
#     reformat rewrites the line an inherited suppression sits on, so line-range
#     scoping calls it branch-owned. Inheritance is about the suppression, not
#     about which lines moved.
$inheritedNoqa = @'
"""Sample module."""
# copilot:generated | tester | 2026-08-04

import  os  # noqa


'@
$repo = New-QualityRepo @{ 'src/app.py' = ($inheritedNoqa + $WIDGET_TIGHT + "`n") }
Set-RepoFile $repo 'src/app.py' (($inheritedNoqa -replace 'import  os', 'import os') + $WIDGET_TIGHT + "`n")
$r = Invoke-Quality -Repo $repo -Files @('src/app.py') -DiffBase 'dev'
Assert-Case 'a reformatted inherited suppression stays ADVISORY' `
    (($r.Exit -eq 0) -and ($r.Output -match 'ADVISORY') -and ($r.Output -match 'noqa')) $r.Output

# 27. Same rule on the tests/ path, which runs hygiene on its own.
$repo = New-QualityRepo @{ 'tests/test_app.py' = ($inheritedNoqa + $WIDGET_TIGHT + "`n") }
Set-RepoFile $repo 'tests/test_app.py' (($inheritedNoqa -replace 'import  os', 'import os') + $WIDGET_REFLOWED + "`n")
$r = Invoke-Quality -Repo $repo -Files @('tests/test_app.py') -DiffBase 'dev' -Checks 'ignore-hygiene'
Assert-Case 'ignore-hygiene keeps a reformatted inherited suppression advisory' `
    (($r.Exit -eq 0) -and ($r.Output -match 'ADVISORY')) $r.Output

# ------------------------------------------------------------------ report --

Write-Host ''
Write-Host "$script:passed passed, $script:failed failed"
if ($script:failed -gt 0) { exit 1 }
exit 0
