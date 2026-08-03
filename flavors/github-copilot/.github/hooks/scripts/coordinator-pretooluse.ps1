# Agent-scoped PreToolUse hook for the coordinator agent.
#
# DELEGATION ENFORCEMENT (HARD -- blocks coordinator from editing/creating files)
# TEST TOOL ENFORCEMENT (HARD -- blocks pytest via terminal, must use runTests)
#
# The coordinator must delegate all file modifications to subagents.
# This hook blocks edit/create tool calls. Defence-in-depth with the
# coordinator PostToolUse detective check (git status after terminal commands).
#
# It also blocks pytest invocations via terminal -- the coordinator must
# use execute/runTests or predefined tasks (tests: domain, tests: all).
#
# Fires only when the coordinator agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'

# Read and parse stdin
$raw = [Console]::In.ReadToEnd()
try {
    $inputData = $raw | ConvertFrom-Json
} catch {
    Write-Output '{}'
    exit 0
}

# Allow read-only and search tools unconditionally
$toolName = $inputData.tool_name
if ($toolName -match 'read|search|find|list|get|problems') {
    Write-Output '{}'
    exit 0
}

# Intercept terminal commands: bootstrap env (configurable), block terminal pytest,
# and enforce git command quality gates.
if ($toolName -match 'terminal') {
    $command = $inputData.tool_input.command
    # Fallback: tool_input may arrive as a JSON string
    if (-not $command -and $inputData.tool_input -is [string]) {
        try { $ti = $inputData.tool_input | ConvertFrom-Json; $command = $ti.command } catch {}
    }

    # Config: PROJECT_LANGUAGE and PY_ENV_BOOTSTRAP from af-env.conf
    $projectLanguage = 'python'
    $bootstrapMode = 'ask'
    $confPath = Join-Path (Get-Location) '.github/af-env.conf'
    if (Test-Path $confPath) {
        $m = Select-String -Path $confPath -Pattern '^PROJECT_LANGUAGE=(.+)$'
        if ($m) { $projectLanguage = $m.Matches[0].Groups[1].Value.Trim().ToLower() }
        $m = Select-String -Path $confPath -Pattern '^PY_ENV_BOOTSTRAP=(.+)$'
        if ($m) { $bootstrapMode = $m.Matches[0].Groups[1].Value.Trim().ToLower() }
    }

    $isPyTerminalCommand = $command -match '(\.github/scripts/(run-tests|run-deps|run-metrics)\.ps1)|(\.venv/Scripts/python\.exe)|(^|\s)(python|pip|ruff|mypy)(\s|$)'
    $isPytestViaTerminal = $command -match '\bpytest\b|\bpy\.test\b'
    $venvPython = Join-Path (Get-Location) '.venv/Scripts/python.exe'

    # Bootstrap only for non-pytest Python commands; pytest via terminal is denied below anyway.
    if ($projectLanguage -eq 'python' -and -not $isPytestViaTerminal -and $isPyTerminalCommand -and -not (Test-Path $venvPython)) {
        if ($bootstrapMode -eq 'always') {
            $bootstrapScript = Join-Path (Get-Location) '.github/scripts/bootstrap-python-env.ps1'
            if (-not (Test-Path $bootstrapScript)) {
                @{
                    hookSpecificOutput = @{
                        hookEventName      = 'PreToolUse'
                        permissionDecision = 'deny'
                        permissionDecisionReason = "Python environment missing and bootstrap script not found at '.github/scripts/bootstrap-python-env.ps1'."
                    }
                } | ConvertTo-Json -Depth 3 -Compress
                exit 0
            }
            & $bootstrapScript 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $venvPython)) {
                @{
                    hookSpecificOutput = @{
                        hookEventName      = 'PreToolUse'
                        permissionDecision = 'deny'
                        permissionDecisionReason = "Python environment bootstrap failed. Run '.github/scripts/bootstrap-python-env.ps1' manually and retry."
                    }
                } | ConvertTo-Json -Depth 3 -Compress
                exit 0
            }
        } elseif ($bootstrapMode -eq 'ask') {
            @{
                hookSpecificOutput = @{
                    hookEventName      = 'PreToolUse'
                    permissionDecision = 'ask'
                    permissionDecisionReason = "Python environment (.venv) is missing. Allow running '.github/scripts/bootstrap-python-env.ps1' now to prepare venv + dependencies?"
                }
            } | ConvertTo-Json -Depth 3 -Compress
            exit 0
        }
    }

    if ($isPytestViaTerminal) {
        @{
            hookSpecificOutput = @{
                hookEventName      = 'PreToolUse'
                permissionDecision = 'deny'
                permissionDecisionReason = "Do not run tests via terminal. Use the execute/runTests tool (structured output, VS Code test integration) or the predefined task 'tests: domain' / 'tests: all' via execute/runTask."
            }
        } | ConvertTo-Json -Depth 3 -Compress
        exit 0
    }
    # Validate git worktree add preconditions
    if ($command -match 'git\s+worktree\s+add') {
        $WT_DIR = '../wt'
        $confPath = Join-Path (Get-Location) '.github/af-env.conf'
        if (Test-Path $confPath) {
            $m = Select-String -Path $confPath -Pattern '^WORKTREE_DIR=(.+)$'
            if ($m) { $WT_DIR = $m.Matches[0].Groups[1].Value.Trim() }
        }
        # Extract branch name: git worktree add <path> -b <branch> ...
        $branchMatch = $null
        if ($command -match '-b\s+(\S+)') { $branchMatch = $Matches[1] }
        elseif ($command -match 'worktree\s+add\s+\S+\s+(\S+)') { $branchMatch = $Matches[1] }
        if ($branchMatch -and $branchMatch -notmatch '^agent/[a-z0-9][a-z0-9-]*$') {
            @{
                hookSpecificOutput = @{
                    hookEventName      = 'PreToolUse'
                    permissionDecision = 'deny'
                    permissionDecisionReason = "Worktree branch name '$branchMatch' is invalid. Must match '^agent/[a-z0-9-]+' (e.g. agent/feat-auth, agent/fix-db-pool). See skills/git-worktrees/SKILL.md."
                }
            } | ConvertTo-Json -Depth 3 -Compress
            exit 0
        }
        # Extract worktree path and check for collision
        $pathMatch = $null
        if ($command -match 'worktree\s+add\s+(\S+)') { $pathMatch = $Matches[1] }
        if ($pathMatch) {
            try {
                $resolvedWt = [System.IO.Path]::GetFullPath($pathMatch)
                if (Test-Path $resolvedWt) {
                    @{
                        hookSpecificOutput = @{
                            hookEventName      = 'PreToolUse'
                            permissionDecision = 'deny'
                            permissionDecisionReason = "Worktree path '$pathMatch' already exists. An existing task may still be running. Run 'git worktree list' to check. Investigate before creating a new worktree at this path."
                        }
                    } | ConvertTo-Json -Depth 3 -Compress
                    exit 0
                }
            } catch {}
        }
        # Check repo health
        $gitStatus = git status --porcelain 2>$null
        if ($LASTEXITCODE -ne 0) {
            @{
                hookSpecificOutput = @{
                    hookEventName      = 'PreToolUse'
                    permissionDecision = 'deny'
                    permissionDecisionReason = "Main repository is not healthy ('git status' failed). Fix repository state before creating a worktree."
                }
            } | ConvertTo-Json -Depth 3 -Compress
            exit 0
        }
    }
    # Validate git commit message quality -- reject generic phase-only messages
    # Required format: [agent:name] phase: {description >= 10 chars}
    if ($command -match 'git\s+commit') {
        $commitMsg = $null
        if ($command -match '-m\s+"([^"]+)"') { $commitMsg = $Matches[1] }
        elseif ($command -match "-m\s+'([^']+)'") { $commitMsg = $Matches[1] }
        if ($null -ne $commitMsg) {
            $m = $commitMsg.Trim()
            $exempt = $m -match '^\[agent:[^\]]+\]\s+(WIP checkpoint|task cancelled|justify ignore)'
            $adequate = $m -match '^\[agent:[^\]]+\]\s+[^:]+:\s+.{10,}'
            if (-not $exempt -and -not $adequate) {
                @{
                    hookSpecificOutput = @{
                        hookEventName      = 'PreToolUse'
                        permissionDecision = 'deny'
                        permissionDecisionReason = "Commit message too generic. Required format: '[agent:name] phase: {description >= 10 chars}'. E.g.: '[agent:test-writer] failing tests: ColumnMeta validation -- null CRC and negative threshold edge cases'. See git-workflow.instructions.md Commit Rule 4."
                    }
                } | ConvertTo-Json -Depth 3 -Compress
                exit 0
            }
        }
    }
    # Terminal commands allowed (git, investigation, etc.)
    Write-Output '{}'
    exit 0
}

# Only inspect file-modifying tools — everything else passes
if ($toolName -notmatch 'editFile|createFile|createDir|editNotebook|writeFile') {
    Write-Output '{}'
    exit 0
}

# Block: coordinator must not edit or create files directly
$reason = "Coordinator delegation violation: The coordinator must not modify files directly. " +
    "Select the appropriate workflow and delegate to the correct subagent: " +
    "test-writer (Red phase, test files), implementer (Green phase, production code), " +
    "refactorer (Refactor phase, structural cleanup), documenter (logs and docs), " +
    "planner (plan files). Review your Cardinal Rules and Workflow Selection."

@{
    hookSpecificOutput = @{
        hookEventName      = 'PreToolUse'
        permissionDecision = 'deny'
        permissionDecisionReason = $reason
    }
} | ConvertTo-Json -Depth 3 -Compress
exit 0
