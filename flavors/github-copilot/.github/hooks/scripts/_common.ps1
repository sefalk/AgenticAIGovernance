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
#   $AfConfPath    absolute path to .github/af-env.conf
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

$script:AfConfPath = Join-Path $script:AfMainRoot '.github/af-env.conf'
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
