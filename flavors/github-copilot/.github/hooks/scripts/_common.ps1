# Shared resolution preamble for AF hooks (PowerShell side).
#
# DOT-SOURCE this file, never call it:
#
#     . "$PSScriptRoot/_common.ps1"
#
# Provides:
#   $AfScriptDir   directory this file lives in
#   $AfMainRoot    checkout where .github/ is deployed
#   $AfCodeRoot    active worktree if the sentinel points at one, else MAIN
#   $AfConfPath    absolute path to the config: $env:AF_CONF_PATH if set,
#                  else .github/af-env.conf
#   $AfConfFound   $true if that file exists
#   $AfPython      an interpreter that was proven to run, or ''
#   Get-AfConfig -Key <name> [-Default <value>]
#
# Why this exists: every value is derived from this file's own location, never
# from the current working directory. `Join-Path (Get-Location) '.github/...'`
# resolves to nothing whenever the agent process is not sitting at the repo
# root, and an unread config is indistinguishable from an empty one.

$script:AfScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
$script:AfMainRoot = Split-Path (Split-Path (Split-Path $script:AfScriptDir))

$script:AfCodeRoot = $script:AfMainRoot
$afSentinel = Join-Path $script:AfMainRoot '.github/.active-worktree'
if (Test-Path $afSentinel) {
    $afWt = (Get-Content $afSentinel -Raw -ErrorAction SilentlyContinue)
    if ($afWt) { $afWt = $afWt.Trim() }
    if ($afWt -and (Test-Path $afWt)) { $script:AfCodeRoot = $afWt }
}

# AF_CONF_PATH names the config for this process, overriding the deployed one
# (issue #108). It exists so a test can state the policy it asserts under: a
# suite that reads whatever af-env.conf the consumer happens to ship reports
# that consumer's settings as failures, and teaches people to revert a
# legitimate policy choice to make a test pass.
#
# A path that does not exist counts as NO config, not as a fallback to the
# deployed one. Falling back would put the consumer's file back in play behind
# a typo -- the exact confusion this variable removes -- and the caller who set
# it would never learn that its file was missed.
#
# It cannot lift a hard-deny: the deny tier in block-dangerous is hardcoded and
# runs before any category is consulted. Policy widens or narrows the ask/auto
# boundary only. Anyone able to set this variable on the hook process already
# controls that process; the hook is started by the extension host, so a
# $env: assignment in an agent terminal does not reach it.
$script:AfConfPath = if ($env:AF_CONF_PATH) {
    $env:AF_CONF_PATH
} else {
    Join-Path $script:AfMainRoot '.github/af-env.conf'
}
$script:AfConfFound = Test-Path $script:AfConfPath

function Get-AfConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [string]$Default = ''
    )
    if (-not $script:AfConfFound) { return $Default }
    $pattern = '^{0}=(.+)$' -f [regex]::Escape($Key)
    $m = Select-String -Path $script:AfConfPath -Pattern $pattern -ErrorAction SilentlyContinue
    if ($m) {
        $v = $m.Matches[0].Groups[1].Value.Trim()
        if ($v) { return $v }
    }
    return $Default
}

# The retro destination is configurable (issue #117), so every gate has to
# derive it the same way. A hook that kept the old path hardcoded would report
# a missing artifact the documenter had correctly written somewhere else --
# the gate would be wrong and the agent would be blamed.
#
# Normalised so `docs/retros/`, `docs\retros` and `docs/retros` are one value.
# A trailing slash yields `docs/retros//id.md`, which Test-Path accepts and
# string comparison does not, so the path a gate reports would stop matching
# the path it checked.
function Get-AfRetroDir {
    $dir = Get-AfConfig -Key 'RETRO_DIR' -Default '.github/retros/auto'
    $dir = ($dir -replace '\\', '/') -replace '/+$', ''
    if (-not $dir) { return '.github/retros/auto' }
    return $dir
}

# A resolvable interpreter is not a working one: on Windows `python3` is an
# App Execution Alias that is on PATH, runs nothing and exits non-zero.
# Probe each candidate instead of trusting the lookup.
function Find-AfPython {
    foreach ($candidate in @($env:AF_PYTHON_OVERRIDE, 'python3', 'python', 'py')) {
        if (-not $candidate) { continue }
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if (-not $cmd -or -not $cmd.Source) { continue }
        # 'pass', not '': PowerShell 5.1 silently drops empty-string arguments
        # to native commands, so `-c ''` reaches python as a bare -c and every
        # candidate would fail the probe -- including the working ones.
        & $cmd.Source -c 'pass' *> $null
        if ($LASTEXITCODE -eq 0) { return $cmd.Source }
    }
    return ''
}

$script:AfPython = Find-AfPython

# ── Workflow lifecycle ───────────────────────────────────────────────────
#
# Get-AfPlanLifecycle -WorkflowId <id> [-Root <path>]
#
# Returns @{ Found = <bool>; Status = <string>; Path = <string> } for the plan
# file that belongs to this workflow.
#
# Why a plan file: a Stop hook receives session_id and transcript_path, never
# the delegation prompt. Whether an agent was called mid-workflow or to
# finalise is therefore not knowable from stdin -- it has to be read off the
# repository. The plan file is the honest signal, because setting its status
# to COMPLETED IS the documenter's declaration that it finalised (issue #72).
#
# Two things this deliberately does not do:
#   * It does not match the raw text. `templates/PLAN.md` ships
#     `**Status:** <!-- DRAFT | APPROVED | IN_PROGRESS | COMPLETED -->`, so a
#     grep for COMPLETED calls an untouched template a finished workflow.
#     HTML comments are stripped before anything is matched.
#   * It does not accept any plan in the directory. A plan speaks for one
#     workflow only, the one whose branch it names.
function Get-AfPlanLifecycle {
    param(
        [Parameter(Mandatory = $true)][string]$WorkflowId,
        [string]$Root = '.'
    )

    $result = @{ Found = $false; Status = ''; Path = '' }

    $planDir = Join-Path $Root 'docs/plans'
    if (-not (Test-Path $planDir)) { $planDir = Join-Path $Root 'docs' }
    if (-not (Test-Path $planDir)) { return $result }

    $files = Get-ChildItem -Path $planDir -Filter '*.md' -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'WIP.md' }
    if (-not $files) { return $result }

    # `agent/72-x` must not be satisfied by `agent/72-x-followup`.
    $branchPattern = 'agent/{0}(?![\w-])' -f [regex]::Escape($WorkflowId)

    foreach ($f in $files) {
        $raw = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $raw) { continue }
        $text = [regex]::Replace($raw, '(?s)<!--.*?-->', '')
        if ($text -notmatch $branchPattern) { continue }

        $result.Found = $true
        $result.Path = $f.FullName
        if ($text -match '(?im)^[^\S\r\n]*[*_#\s]*status[*_\s]*:\s*[*_`\s]*([A-Za-z_]+)') {
            $result.Status = $Matches[1].ToUpperInvariant()
        }
        return $result
    }

    return $result
}

# ── Is a retro snippet owed for this workflow? (issue #27) ───────────────
#
# The retro used to be unconditional, so a clean run produced a file recording
# that nothing happened -- and the next workflow read it back as input.
#
# The condition is derived here, from the workflow log, and never from the
# documenter's account of its own run: "it was clean, so I skipped it" is the
# self-report channel #91 closed for timestamps.
#
# The default is REQUIRED. Skipping needs positive evidence -- counters that
# actually read zero, a COMPLETED status, no adverse verdict. A log that is
# missing, unreadable, or still carrying the unfilled `retries: <number>`
# template establishes nothing, and absence of evidence is not evidence of a
# clean run.
#
# Every condition matches a FIELD, not a word: the log quotes the user request
# verbatim in `trigger:`, so "blocked" and "rejected" can appear in it as prose.
function Get-AfRetroRequirement {
    param(
        [Parameter(Mandatory = $true)][string]$WorkflowId,
        [string]$Root = '.'
    )

    $result = @{ Required = $true; Reason = 'the workflow log could not be read, so a clean run is not established' }

    $log = $null
    foreach ($ext in @('yaml', 'yml')) {
        $p = Join-Path $Root ".github/logs/$WorkflowId.$ext"
        if (Test-Path $p) {
            $log = Get-Content $p -Raw -ErrorAction SilentlyContinue
            break
        }
    }
    if (-not $log) { return $result }

    if ($log -notmatch '(?im)^[^\S\r\n]*retries:[^\S\r\n]*0\s*$') {
        $result.Reason = 'the log does not record `retries: 0`'
        return $result
    }
    if ($log -notmatch '(?im)^[^\S\r\n]*escalations:[^\S\r\n]*0\s*$') {
        $result.Reason = 'the log does not record `escalations: 0`'
        return $result
    }
    if ($log -notmatch '(?im)^[^\S\r\n]*status:[^\S\r\n]*"?COMPLETED') {
        $result.Reason = 'the workflow status is not COMPLETED'
        return $result
    }
    if ($log -match '(?im)^[^\S\r\n]*verdict:[^\S\r\n]*"?[^\S\r\n]*(REJECTED|ESCALATE|BLOCKED)') {
        $result.Reason = "a step verdict was $($Matches[1])"
        return $result
    }
    if ($log -match '(?im)^escalation:[^\S\r\n]*$') {
        $result.Reason = 'the log carries an escalation block'
        return $result
    }

    $result.Required = $false
    $result.Reason = 'retries 0, escalations 0, status COMPLETED, no adverse verdict'
    return $result
}

# ── Write-tool classification ────────────────────────────────────────────
#
# Which tool calls write to the workspace, and where they keep their paths.
#
# The names below were read out of captured PreToolUse payloads, not out of
# tool documentation (issue #69). Every file gate in this directory used to
# match camelCase names -- editFiles, createFile, createDirectory -- that no
# client has ever sent. The gates therefore returned {} on every write and
# nobody noticed, because {} is also what a gate says when it approves.
#
# Observed names: create_file, replace_string_in_file,
# multi_replace_string_in_file. The camelCase spellings are kept so a client
# that does send them is still judged rather than waved through.
$script:AfWriteToolNames = @(
    'create_file'
    'replace_string_in_file'
    'multi_replace_string_in_file'
    'create_directory'
    'edit_notebook_file'
    'create_new_jupyter_notebook'
    'editFiles', 'editFile', 'createFile', 'createDirectory', 'createDir'
    'editNotebook', 'writeFile', 'applyPatch', 'insertEdit'
)

function Test-AfWriteTool {
    <#
    .SYNOPSIS
        True if the tool call modifies files or directories in the workspace.
    #>
    param([string]$ToolName)

    if (-not $ToolName) { return $false }
    if ($script:AfWriteToolNames -contains $ToolName) { return $true }

    # An exact list cannot recognise a tool that does not exist yet, and a
    # gate that has never heard of a tool fails open -- the #69 defect again.
    # A verb that denotes writing plus a noun that denotes a file is enough
    # to take the call seriously. `read_file` carries no verb and
    # `create_and_run_task` carries no file noun, so neither is caught here.
    if ($ToolName -match '(create|write|edit|insert|apply|replace)' -and
        $ToolName -match '(file|notebook|dir)') {
        return $true
    }
    return $false
}

function Get-AfWritePaths {
    <#
    .SYNOPSIS
        Every workspace path a write-tool payload refers to.
    .DESCRIPTION
        Flat payloads keep their path in `filePath`. `multi_replace_string_in_file`
        keeps none at the top level -- its paths sit in `replacements[].filePath`,
        the same one-level-down shape that made the researcher's URL gate inert
        in #64. A gate that only reads the flat key sees an empty batch edit.
    #>
    param($ToolInput)

    $paths = New-Object System.Collections.Generic.List[string]
    if (-not $ToolInput) { return @() }

    foreach ($key in @('filePath', 'path', 'dirPath', 'notebookUri', 'uri')) {
        $value = $ToolInput.$key
        if ($value -is [string] -and $value) { $paths.Add($value) }
    }

    if ($ToolInput.replacements) {
        foreach ($replacement in @($ToolInput.replacements)) {
            $value = $replacement.filePath
            if ($value -is [string] -and $value) { $paths.Add($value) }
        }
    }

    return @($paths | Select-Object -Unique)
}

# ── Provenance marker detection ──────────────────────────────────────────
#
# `instructions/provenance.instructions.md` puts a Python marker *after* the
# module docstring, and the marker for a modified function *inside that
# function's docstring*. Every gate here used to read the first five lines,
# so a module docstring of four lines or more put the instructed placement
# out of reach, and the function-level placement was unreachable by
# construction (issue #81). The block message quoted the instruction it
# contradicted, which left an agent no move that satisfied both.
#
# Two things this deliberately does not do:
#   * It does not judge *where* the marker sits. A marker's job is to be
#     found; prescribing its position is the instruction's job and checking
#     it is a reviewer's. A boolean gate that answers "is this file
#     attributed?" should not also be answering "is it attributed in the
#     spot I expected?" -- those are different questions and only the first
#     one has a defensible automatic answer.
#   * It does not tighten what counts as a marker. `-Kind generated` narrows
#     which marker kinds satisfy the caller, because test-writer's gate is
#     about authorship of a *new* file and `copilot:modified` must not
#     satisfy it. It does not additionally demand the full
#     `kind | agent | date` triple: widening where we look must not quietly
#     start blocking work that the old window would have passed.
function Test-AfProvenanceMarker {
    <#
    .SYNOPSIS
        Whether a file carries a Copilot provenance marker anywhere in it.
    .PARAMETER Path
        File to inspect. A path that does not exist, or cannot be read, is
        reported as unmarked rather than raising -- a gate must not turn an
        unreadable file into a crash.
    .PARAMETER Kind
        'any' accepts copilot:generated or copilot:modified (default).
        'generated' accepts only copilot:generated.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('any', 'generated')][string]$Kind = 'any'
    )

    if (-not $Path) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }

    $text = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if (-not $text) { return $false }

    $pattern = if ($Kind -eq 'generated') { 'copilot:generated' } else { 'copilot:(generated|modified)' }
    return [bool]($text -match $pattern)
}

# ── Files a concurrent peer agent edited (issue #101) ──────────────────
#
# Producer stop-hook gates scope themselves from `git diff`, which is global to
# the checkout. Two producers on one branch therefore see each other's in-flight
# edits, and the gate demands work on a file the agent was told not to touch --
# then the provenance gate makes it stamp an authorship marker recording the
# wrong agent.
#
# Returns the files a DIFFERENT subagent edited while this one was running, so
# the caller can drop them from its own scope. Every failure path returns an
# empty array: no stdin, no session id, no session directory, no interpreter,
# a non-zero exit. Subtracting nothing is exactly today's behaviour, which is
# the only direction this may fail in -- a watchdog that fails a legitimate
# workflow gets switched off (issue #108).
function Get-AfPeerEdits {
    param(
        [string]$StdinRaw,
        [string]$Agent,
        [string]$CodeRoot,
        [string]$MainRoot
    )

    if (-not $StdinRaw -or -not $Agent) { return @() }

    try { $payload = $StdinRaw | ConvertFrom-Json } catch { return @() }
    $sid = $payload.session_id
    $transcript = $payload.transcript_path
    if (-not $sid -or -not $transcript) { return @() }

    # <ws>/GitHub.copilot-chat/transcripts/<sid>.jsonl -> .../debug-logs/<sid>
    $chatDir = Split-Path -Parent (Split-Path -Parent $transcript)
    if (-not $chatDir) { return @() }
    $sessionDir = Join-Path (Join-Path $chatDir 'debug-logs') $sid
    if (-not (Test-Path $sessionDir)) { return @() }

    $reader = Join-Path $MainRoot '.github/hooks/scripts/concurrent-agent-edits.py'
    if (-not (Test-Path $reader)) { return @() }

    $python = Join-Path $CodeRoot '.venv/Scripts/python.exe'
    if (-not (Test-Path $python)) {
        $python = if ($AfPython) { $AfPython } else { $null }
    }
    if (-not $python) { return @() }

    $out = & $python $reader '--session-dir' $sessionDir '--agent' $Agent '--repo-root' $CodeRoot 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }

    return @($out | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
}
