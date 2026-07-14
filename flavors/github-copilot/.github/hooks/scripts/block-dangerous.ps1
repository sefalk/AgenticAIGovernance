# PreToolUse hook: three-tier terminal command classifier (allow / ask / deny).
#
# Tiers:
#   deny  -> hard-block destructive/irreversible commands (+ agent notice)
#   allow -> auto-approve safe commands (read-only, tests, feature-branch git),
#            gated by AUTONOMY_LEVEL / AUTONOMY_CAT_* in .github/af-env.conf
#   ask   -> prompt for durable-change commands
#   {}    -> defer to the user's approval settings (fail-safe default)
#
# Fail-safe: on any parse ambiguity or unexpected shape the hook returns {}
# (prompt) -- it never accidentally auto-approves.

$ErrorActionPreference = 'SilentlyContinue'

# Read and parse stdin
$raw = [Console]::In.ReadToEnd()
try {
    $inputData = $raw | ConvertFrom-Json
} catch {
    Write-Output '{}'
    exit 0
}

# Only inspect terminal tool calls
$toolName = $inputData.tool_name
if ($toolName -notmatch 'terminal|Terminal') {
    Write-Output '{}'
    exit 0
}

# Extract the command string
$command = [string]$inputData.tool_input.command
if (-not $command) {
    Write-Output '{}'
    exit 0
}

# ---------------------------------------------------------------------------
# Load autonomy config from .github/af-env.conf (read once).
# ---------------------------------------------------------------------------
$repo = (git rev-parse --show-toplevel 2>$null)
$confLines = @()
if ($repo) {
    $conf = Join-Path $repo '.github/af-env.conf'
    if (Test-Path $conf) { $confLines = Get-Content $conf }
}
function Get-AfEnv([string]$key, [string]$default) {
    foreach ($l in $confLines) {
        if ($l -match "^\s*$([regex]::Escape($key))=(.*)$") { return $Matches[1].Trim() }
    }
    return $default
}

$level = (Get-AfEnv 'AUTONOMY_LEVEL' 'balanced').ToLower()
$protected = @((Get-AfEnv 'PROTECTED_BRANCHES' 'main,master,dev') -split ',' |
    ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($protected.Count -eq 0) { $protected = @('main', 'master', 'dev') }
$protAlt = ($protected | ForEach-Object { [regex]::Escape($_) }) -join '|'
$curBranch = (git rev-parse --abbrev-ref HEAD 2>$null)
# Optional executable path prefix (e.g. .venv\Scripts\, ./, /usr/bin/) and .exe suffix,
# so path-invoked tools like `.venv\Scripts\pytest.exe` are recognised.
$pathPfx = '([^\s]*[\\/])?'
$exe = '(\.exe)?'

# Category defaults per level. Per-category overrides win when non-empty.
$levelDefaults = @{
    conservative = @{ git_read = 'auto'; fs_read = 'auto'; fs_write = 'ask';  tests = 'ask';  git_feature = 'ask';  git_merge = 'ask';  pkg = 'ask';  databricks = 'ask'; cloud_read = 'ask'  }
    balanced     = @{ git_read = 'auto'; fs_read = 'auto'; fs_write = 'ask';  tests = 'auto'; git_feature = 'auto'; git_merge = 'auto'; pkg = 'ask';  databricks = 'ask'; cloud_read = 'auto' }
    autonomous   = @{ git_read = 'auto'; fs_read = 'auto'; fs_write = 'auto'; tests = 'auto'; git_feature = 'auto'; git_merge = 'auto'; pkg = 'auto'; databricks = 'ask'; cloud_read = 'auto' }
}
if (-not $levelDefaults.ContainsKey($level)) { $level = 'balanced' }
function Resolve-Category([string]$name, [string]$envKey) {
    $ov = Get-AfEnv $envKey ''
    if ($ov) { return $ov.ToLower() }
    return $levelDefaults[$level][$name]
}
$catGitRead    = Resolve-Category 'git_read'    'AUTONOMY_CAT_GIT_READ'
$catGitFeature = Resolve-Category 'git_feature' 'AUTONOMY_CAT_GIT_FEATURE'
$catGitMerge   = Resolve-Category 'git_merge'   'AUTONOMY_CAT_GIT_MERGE'
$catTests      = Resolve-Category 'tests'       'AUTONOMY_CAT_TESTS'
$catFsRead     = Resolve-Category 'fs_read'     'AUTONOMY_CAT_FS_READ'
$catPkg        = Resolve-Category 'pkg'         'AUTONOMY_CAT_PKG_INSTALL'
$catDatabricks = Resolve-Category 'databricks'  'AUTONOMY_CAT_DATABRICKS'
$catCloudRead  = Resolve-Category 'cloud_read'  'AUTONOMY_CAT_CLOUD_READ'
$catFsWrite    = Resolve-Category 'fs_write'    'AUTONOMY_CAT_FS_WRITE'

# Split a command into top-level segments on ; && || | and newlines, honoring
# single/double quotes so separators INSIDE a quoted string (e.g. a commit
# message or a -Pattern 'a|b') do not split the command.
function Split-TopLevel([string]$cmd) {
    $segs = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    $q = [char]0
    for ($i = 0; $i -lt $cmd.Length; $i++) {
        $c = $cmd[$i]
        if ($q -ne [char]0) {
            [void]$sb.Append($c)
            if ($c -eq $q) { $q = [char]0 }
            continue
        }
        if ($c -eq '"' -or $c -eq "'") { $q = $c; [void]$sb.Append($c); continue }
        $n = if ($i + 1 -lt $cmd.Length) { $cmd[$i + 1] } else { [char]0 }
        if (($c -eq '&' -and $n -eq '&') -or ($c -eq '|' -and $n -eq '|')) {
            $segs.Add($sb.ToString()); [void]$sb.Clear(); $i++; continue
        }
        if ($c -eq ';' -or $c -eq '|' -or $c -eq "`n") {
            $segs.Add($sb.ToString()); [void]$sb.Clear(); continue
        }
        if ($c -eq "`r") { continue }
        [void]$sb.Append($c)
    }
    $segs.Add($sb.ToString())
    return , $segs.ToArray()
}

function Emit([string]$decision, [string]$reason) {
    @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = $decision
            permissionDecisionReason = $reason
        }
    } | ConvertTo-Json -Depth 3 -Compress
    exit 0
}

$denyTail = "The agent will not run this. If it is genuinely required, either (a) run it yourself " +
    "-- the agent can prepare the exact command for you to paste and execute -- or (b) make a conscious " +
    "decision to relax the autonomy policy in .github/af-env.conf."

# ===========================================================================
# TIER 1 -- DENY (hard, level-independent). Checked first.
# ===========================================================================
$denyRules = @(
    @{ p = 'git\s+push\b.*(--force|-f)\b';            why = 'force push (remote history rewrite)' }
    @{ p = "git\s+push\b.*(\s|:)($protAlt)(\s|$)";    why = 'push to a protected branch' }
    @{ p = 'git\s+reset\s+--hard';                    why = 'hard reset (state rewrite)' }
    @{ p = 'git\s+rebase\b';                          why = 'rebase (history rewrite)' }
    @{ p = 'git\s+branch\b.*--force\b';                why = 'force branch deletion (--force)' }
    @{ p = "git\s+branch\s+-d\b.*(\s|:)($protAlt)(\s|$)"; why = 'deleting a protected branch' }
    @{ p = 'git\s+add\s+(\S+\s+)*(--force|-f)(\s|$)'; why = 'git add --force (bypass .gitignore)' }
    @{ p = 'git\s+add\s+(-\S+\s+)*\.(\s|$)';          why = 'git add . (banned wildcard)' }
    @{ p = 'git\s+add\s+(\S+\s+)*-A(\s|$)';           why = 'git add -A (banned wildcard)' }
    @{ p = '--no-verify';                             why = 'bypassing git hooks' }
    @{ p = 'rm\s+-r[f ].*(\s|=)(/|~|\*)';             why = 'recursive delete of a broad path' }
    @{ p = 'Remove-Item.*-Recurse.*-Force';           why = 'recursive force delete' }
    @{ p = 'dd\s+if=.*of=/dev/';                      why = 'raw disk write' }
    @{ p = 'mkfs\.';                                  why = 'filesystem format' }
    @{ p = 'format\s+[A-Za-z]:';                      why = 'drive format' }
    @{ p = 'chmod\s+-R\s+777';                        why = 'world-writable permissions' }
    @{ p = '\|\s*(bash|sh|iex|Invoke-Expression)\b';  why = 'pipe-to-shell execution' }
    @{ p = 'DROP\s+(TABLE|DATABASE)';                 why = 'destructive SQL' }
    @{ p = 'TRUNCATE\s+TABLE';                        why = 'destructive SQL' }
)
foreach ($r in $denyRules) {
    if ($command -match $r.p) {
        Emit 'deny' ("Policy hard-deny: $($r.why). $denyTail")
    }
}
# Branch force-deletion (-D) needs a CASE-SENSITIVE check so that the safe
# lowercase -d (which git only allows for already-merged branches) is not denied.
if ($command -cmatch 'git\s+branch\s+(\S+\s+)*-D(\s|$)') {
    Emit 'deny' ("Policy hard-deny: force branch deletion (-D deletes unmerged commits). $denyTail")
}
# Category-scoped deny (when autonomy policy sets a category to 'deny').
if ($catPkg -eq 'deny' -and ($command -match '(?i)\bpip3?\s+(install|uninstall)\b' -or $command -match '(?i)\bconda\s+(install|remove)\b')) {
    Emit 'deny' ("Policy hard-deny: package management (AUTONOMY_CAT_PKG_INSTALL=deny). $denyTail")
}
if ($catDatabricks -eq 'deny' -and $command -match '(?i)\bdatabricks\b') {
    Emit 'deny' ("Policy hard-deny: Databricks CLI (AUTONOMY_CAT_DATABRICKS=deny). $denyTail")
}

# ===========================================================================
# TIER 2 -- ALLOW (auto-approve safe commands), segment-based & category gated.
#
# The command is split into segments on ; && || | and auto-approved only when
# EVERY segment is individually safe. This lets common composites through
# (e.g. `cd ... ; pytest ... 2>&1 | Select-Object -Last 30`) while still
# refusing anything with an unknown/mutating segment. Command substitution
# ($( ) / backticks) and file-write redirects (> file) are never auto-allowed.
# Note: DENY already scanned the whole string above, so hidden dangerous
# segments (e.g. `... ; rm -rf /`) are blocked before reaching here.
# ===========================================================================
function Test-WriteRedirect([string]$seg) {
    # File-write redirect (> file / >> file). Excludes fd duplication (2>&1, >&1).
    return ($seg -match '>>?\s*[^&\s>]')
}
function Test-SafeSegment([string]$seg) {
    $s = $seg.Trim()
    if (-not $s) { return $true }
    # strip a leading simple assignment ($x = ...) -- no side effect beyond its RHS
    if ($s -match '^\s*\$[\w:]+\s*=\s*(.+)$') { $s = $Matches[1].Trim() }
    # strip a leading call operator (& "path\tool" ...) -- benign invocation wrapper
    if ($s -match '^\s*&\s+(.+)$') { $s = $Matches[1].Trim() }
    if (Test-WriteRedirect $s) {
        if ($catFsWrite -ne 'auto') { return $false }
        # FS_WRITE=auto: a file redirect is allowed; strip it and vet the left command
        $s = ($s -replace '>>?\s*[^\s&>|]+', '').Trim()
        if (-not $s) { return $true }
    }
    # background / inline chaining operator ( & ) that the split does not handle;
    # ( & is not split on because it also appears in fd redirects like 2>&1 )
    if ($s -match '(?<![0-9>&])&(?!&)') { return $false }
    # navigation (no data change)
    if ($s -match '(?i)^(cd|Set-Location|pushd|popd|Push-Location|Pop-Location)\b') { return $true }
    # safe display / filter commands (typical pipe right-hand side)
    if ($s -match '(?i)^(Select-Object|Select-String|Sort-Object|Measure-Object|Out-String|Out-Host|Format-Table|Format-List|Get-Unique|Join-Path|Split-Path|Resolve-Path|more|wc|findstr|grep|ConvertFrom-Json|ConvertTo-Json)\b') { return $true }
    # version probes: <binary> [flags] --version (no positional file arg before it)
    if ($s -match '(?i)^\s*[\w./\\-]+(\s+-{1,2}[\w=.,-]+)*\s+--version\b') { return $true }
    # git read-only
    if ($catGitRead -eq 'auto') {
        if ($s -match '^\s*git\s+(status|diff|log|show|rev-parse|rev-list|remote|blame|describe|shortlog|for-each-ref|ls-files|config\s+--get|fetch)\b') { return $true }
        # read-only config access: only recognised read flags + at most one key,
        # nothing after (a trailing value token would make it a write).
        if ($s -match '^\s*git\s+config\s+(--(global|local|system|worktree|get|get-all|get-regexp|list|show-origin|show-scope)\s+)*[\w.-]*\s*$') { return $true }
        if ($s -match '^\s*git\s+stash\s+list\b') { return $true }
        # branch listing (creating a ref is harmless; delete/rename/copy excluded)
        if ($s -match '^\s*git\s+branch\b' -and $s -notmatch '\s-[dDmMcC]\b' -and $s -notmatch '--(delete|move|copy|force)\b') { return $true }
        # tag listing (create/delete/annotate/sign/force excluded)
        if ($s -match '^\s*git\s+tag\b' -and $s -notmatch '\s-[adfsm]\b' -and $s -notmatch '--(delete|force|sign|annotate)\b' -and $s -notmatch '^\s*git\s+tag\s+[^\s-]') { return $true }
    }
    # git feature-branch work
    if ($catGitFeature -eq 'auto') {
        if ($s -match '^\s*git\s+commit\b') { return $true }
        if ($s -match '^\s*git\s+add\s+\S') { return $true }
        if ($s -match '^\s*git\s+(checkout|switch)\s+-[bc]\s+agent/') { return $true }
        if ($s -match '^\s*git\s+(checkout|switch)\s+agent/') { return $true }
        # switch to a branch (never touches files, so always safe)
        if ($s -match '^\s*git\s+switch\s+[\w./-]+\s*$') { return $true }
        # checkout an existing ref (branch/tag/commit) -- verified so a file
        # pathspec (which would discard changes) is NOT auto-approved
        if ($s -match '^\s*git\s+checkout\s+([\w./-]+)\s*$' -and (git rev-parse --verify --quiet "$($Matches[1])^{commit}" 2>$null)) { return $true }
        # delete a merged, non-protected branch: `git branch -d` only removes a
        # branch git considers fully merged (it refuses otherwise) and the ref is
        # recreatable, so it is safe. Force (-D/--force) and protected are denied above.
        if ($s -match '^\s*git\s+branch\s+(\S+\s+)*-d(\s|$)' -and $s -cnotmatch '\s-D\b' -and $s -notmatch '--force\b' -and $s -notmatch "(\s|:)($protAlt)(\s|$)") { return $true }
        if ($s -match '^\s*git\s+push\b' -and $s -notmatch "(\s|:)($protAlt)(\s|$)") {
            if ($s -match 'agent/') { return $true }                                  # explicit feature target
            if ($curBranch -and ($protected -notcontains $curBranch)) { return $true } # bare push on a feature branch
        }
        if ($s -match '^\s*git\s+(restore|switch\s+agent/)\b') { return $true }
    }
    # reversible topology changes (pull / merge / cherry-pick / revert) --
    # recoverable via reflog / ORIG_HEAD, so safe to run autonomously.
    if ($catGitMerge -eq 'auto' -and $s -match '^\s*git\s+(pull|merge|cherry-pick|revert)\b') { return $true }
    # tests / lint / typecheck / static analysis (read-only, no durable change).
    # Accepts a path prefix so `.venv\Scripts\pytest.exe` etc. are recognised.
    if ($catTests -eq 'auto' -and (
            $s -match "(?i)^\s*$pathPfx(pytest|mypy|pyright|tox|nox|radon|bandit|flake8|pylint|vulture|pip-audit)$exe\b" -or
            $s -match "(?i)^\s*${pathPfx}python(\d)?$exe\s+-m\s+(pytest|mypy|pyright)\b" -or
            $s -match "(?i)^\s*${pathPfx}ruff$exe\s+(check|format\s+--check)\b" -or
            $s -match '(?i)run-tests')) { return $true }
    # read-only filesystem & info commands
    if ($catFsRead -eq 'auto' -and $s -match '(?i)^\s*(ls|dir|Get-ChildItem|cat|type|Get-Content|head|tail|Test-Path|pwd|Get-Location|where(\.exe)?|Get-Command|Get-Date|whoami|hostname|Get-Process|Get-Service|echo|Write-Output|Write-Host)\b') { return $true }
    # read-only package / environment queries
    if ($catFsRead -eq 'auto' -and ($s -match "(?i)^\s*${pathPfx}pip3?$exe\s+(list|show|freeze|check)\b" -or $s -match '(?i)^\s*"?(\S*[\\/])?python(\d)?(\.exe)?"?\s+-m\s+pip\s+(list|show|freeze|check)\b')) { return $true }
    # package managers (autonomy-gated)
    if ($catPkg -eq 'auto' -and ($s -match "(?i)^\s*${pathPfx}pip3?$exe\s+(install|uninstall)\b" -or $s -match '(?i)^\s*python(\d)?\s+-m\s+pip\s+(install|uninstall)\b' -or $s -match "(?i)^\s*${pathPfx}conda$exe\s+(install|remove)\b")) { return $true }
    # read-only cloud CLI queries (databricks list/get, az show/list).
    # Excludes anything touching secrets/credentials/tokens (would print them).
    if ($catCloudRead -eq 'auto' -and $s -notmatch '(?i)(secret|credential|token|password|keyvault|get-access-token)' -and ($s -match '(?i)^\s*databricks\s+[\w-]+\s+(list|get|ls|show)\b' -or $s -match '(?i)^\s*databricks\s+current-user\b' -or $s -match '(?i)^\s*az\s+.+\b(show|list)\b')) { return $true }
    # databricks CLI (autonomy-gated)
    if ($catDatabricks -eq 'auto' -and $s -match '(?i)^\s*databricks\b') { return $true }
    # local filesystem writes (opt-in via AUTONOMY_CAT_FS_WRITE). Recursive/force
    # deletes and broad rm are hard-denied above, so only the safe subset is here.
    if ($catFsWrite -eq 'auto') {
        if ($s -match '(?i)^\s*(Out-File|Set-Content|Add-Content|Tee-Object|New-Item|mkdir|md|Move-Item|Copy-Item|mv|cp|touch)\b') { return $true }
        if ($s -match '(?i)^\s*(Remove-Item|rm|del|erase)\b' -and $s -notmatch '(?i)(-recurse|-force|\*)' -and $s -notmatch '(^|\s)-[rf]{1,2}\b') { return $true }
    }
    return $false
}

# Suppress auto-allow when the command uses grouping / subexpression /
# scriptblock metacharacters OUTSIDE quotes -- e.g. `Write-Host (Remove-Item x)`
# executes the inner command (bash `(cmd)` is a subshell; PowerShell `(cmd)`
# is a sub-pipeline). Quote-strip first so conventional-commit messages like
# "fix(scope): ..." are not falsely suppressed.
$strippedForGuard = $command -replace '"[^"]*"', '' -replace "'[^']*'", ''
if ($strippedForGuard -notmatch '[`({]') {
    $segments = Split-TopLevel $command
    $anySeg = $false
    $allSafe = $true
    foreach ($seg in $segments) {
        if (-not $seg.Trim()) { continue }
        $anySeg = $true
        if (-not (Test-SafeSegment $seg)) { $allSafe = $false; break }
    }
    if ($anySeg -and $allSafe) {
        Emit 'allow' 'Safe: every command segment is read-only or a known-safe operation.'
    }
}

# ===========================================================================
# TIER 3 -- ASK (durable change, confirm).
# ===========================================================================
$askRules = @(
    'git\s+merge\b'
    'git\s+(checkout|switch)\b'
    'git\s+tag\b'
    '(?i)\bpip3?\s+(install|uninstall)\b'
    '(?i)\bconda\s+(install|remove)\b'
    '(?i)\bruff\s+format\b'
    '(?i)\bdatabricks\b.*\b(submit|run|create|update|delete|import|export|deploy)\b'
    '(?i)\baz\b.*\b(create|set|delete|update|deploy)\b'
    '(?i)Remove-Item\b'
    '(?i)(^|\s)rm\b'
    '(?i)(Move-Item|Copy-Item|New-Item|mkdir|mv|cp)\b'
)
# Scan the quote-stripped command so quoted literals (e.g. a commit message
# mentioning "databricks ... export") do not falsely trigger an ASK rule.
foreach ($p in $askRules) {
    if ($strippedForGuard -match $p) {
        Emit 'ask' 'This command makes a durable change. Please confirm it is intentional.'
    }
}

# Default: defer to the user's approval settings (fail-safe -- never auto-allow).
Write-Output '{}'
