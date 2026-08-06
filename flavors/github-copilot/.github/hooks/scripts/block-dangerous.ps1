# PreToolUse hook: three-tier terminal command classifier (allow / ask / deny),
# plus two task-launch classifiers (creation and execution).
#
# Tiers (runInTerminal shape):
#   deny  -> hard-block destructive/irreversible commands (+ agent notice)
#   allow -> auto-approve safe commands (read-only, tests, feature-branch git),
#            gated by AUTONOMY_LEVEL / AUTONOMY_CAT_* in .github/af-env.conf
#   ask   -> prompt for durable-change commands
#   {}    -> defer to the user's approval settings (fail-safe default)
#
# A task is a second way to execute a command line, so it is classified twice,
# at both points where the danger can enter (issue #74):
#
#   CREATION -- `create_and_run_task` (the agent authors the task). Allowlist:
#     task.command must resolve (after path normalisation) inside a directory
#     listed in AF_TASK_SCRIPT_DIRS -- a bare binary (git, ruff, pytest, ...)
#     never can, since it has no path segment to match, so the hard-deny tier
#     is covered as a consequence. See the $isTaskShaped block below.
#
#   EXECUTION -- `run_task` (a task already in .vscode/tasks.json runs). The
#     payload carries only {id, workspaceFolder}: a name, not a command. The
#     task is resolved out of tasks.json and its reconstructed command line is
#     put through the SAME three tiers as a terminal command -- blocklist, not
#     the creation allowlist, because tasks.json is human-authored and
#     legitimately calls bare binaries. Checked separately from creation
#     because a task that was acceptable when written may not be acceptable
#     now: policy, protected branches and categories all move underneath it.
#
# Fail-safe: on any parse ambiguity or unexpected shape the hook returns {}
# (prompt) -- it never accidentally auto-approves. The creation allowlist is
# stricter still: any unrecognised task shape denies (fail closed). An
# unresolvable run_task answers 'ask', never silence: silence is what a gate
# that cannot run and a gate with nothing to say have in common (issue #68).

$ErrorActionPreference = 'SilentlyContinue'

# Root, config and interpreter come from this script's location, never from
# the cwd the agent happens to run in (issue #54).
. "$PSScriptRoot/_common.ps1"

# Read and parse stdin
$raw = [Console]::In.ReadToEnd()
try {
    $inputData = $raw | ConvertFrom-Json
} catch {
    Write-Output '{}'
    exit 0
}

# Only inspect terminal tool calls, or the two task-launch tools.
# `create_and_run_task` and `run_task` are the names VS Code actually sends;
# the camelCase spellings never occur in a captured payload and are kept only
# so a rename upstream degrades to a stale alias rather than to an inert gate.
$toolName = $inputData.tool_name
$isTaskShaped = ($toolName -eq 'create_and_run_task' -or $toolName -eq 'createAndRunTask')
$isTaskRun = ($toolName -eq 'run_task' -or $toolName -eq 'runTask')
if ($toolName -notmatch 'terminal|Terminal' -and -not $isTaskShaped -and -not $isTaskRun) {
    Write-Output '{}'
    exit 0
}

if ($isTaskShaped) {
    # -----------------------------------------------------------------------
    # createAndRunTask allowlist. A task's `command` must resolve, after path
    # normalisation, inside one of the AF_TASK_SCRIPT_DIRS directories -- a
    # bare binary (git, ruff, pytest, databricks, ...) never can, since it has
    # no path segment to match. An interpreter (powershell/cmd/bash/python/...)
    # is checked by its PAYLOAD instead (-File / -c / a positional script
    # path), because that is what actually runs and the interpreter binary
    # itself is never inside the repo. Everything unrecognised fails closed.
    # -----------------------------------------------------------------------
    function Emit-Task([string]$decision, [string]$reason) {
        @{
            hookSpecificOutput = @{
                hookEventName            = 'PreToolUse'
                permissionDecision       = $decision
                permissionDecisionReason = $reason
            }
        } | ConvertTo-Json -Depth 3 -Compress
        exit 0
    }

    $sanctioned = "Point 'command' at a reviewed script under AF_TASK_SCRIPT_DIRS (default .github/scripts), e.g. .github/scripts/run-tests.ps1, or run the command yourself in the terminal."

    # Whole-payload scan for interactive input variables -- these block on a
    # prompt an unattended agent can never answer. Scanned against the raw
    # stdin text (single-quoted match: a double-quoted literal containing
    # ${input: would interpolate as a drive-scoped variable and throw).
    foreach ($v in @('${input:', '${command:', '${config:')) {
        if ($raw.Contains($v)) {
            Emit-Task 'deny' ("Policy hard-deny: task payload contains a '$v...}' variable. Its value is produced elsewhere -- a prompt an agent cannot answer, a VS Code command that executes to yield it, or a setting -- so the payload cannot be classified. Pass a literal argument instead. $sanctioned")
        }
    }

    $task = $inputData.tool_input.task
    if (-not $task) {
        Emit-Task 'deny' ("Policy hard-deny: unrecognised task payload shape (no task object); fail-closed. $sanctioned")
    }

    # A folderOpen task executes later, outside any hook's view.
    if ($task.runOptions -and ([string]$task.runOptions.runOn) -eq 'folderOpen') {
        Emit-Task 'deny' ("Policy hard-deny: runOptions.runOn 'folderOpen' registers a task that runs automatically the next time the folder is opened, outside any hook's view. $sanctioned")
    }

    $taskRepo = $AfCodeRoot
    $taskConfLines = @()
    if ($AfConfFound) { $taskConfLines = Get-Content $AfConfPath }
    function Get-AfEnvTask([string]$key, [string]$default) {
        foreach ($l in $taskConfLines) {
            if ($l -match "^\s*$([regex]::Escape($key))=(.*)$") { return $Matches[1].Trim() }
        }
        return $default
    }
    $allowedDirsRaw = @((Get-AfEnvTask 'AF_TASK_SCRIPT_DIRS' '.github/scripts') -split ',' |
            ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($allowedDirsRaw.Count -eq 0) { $allowedDirsRaw = @('.github/scripts') }

    function Resolve-TaskPath([string]$p) {
        if (-not $taskRepo -or -not $p) { return $null }
        $expanded = [System.Environment]::ExpandEnvironmentVariables($p)
        $expanded = $expanded.Replace('${workspaceFolder}', $taskRepo).Replace('${workspaceRoot}', $taskRepo)
        try {
            # Substitution and %VAR% expansion both yield absolute paths, which
            # must not be joined onto the repo root again.
            if ([System.IO.Path]::IsPathRooted($expanded)) { return [System.IO.Path]::GetFullPath($expanded) }
            return [System.IO.Path]::GetFullPath((Join-Path $taskRepo $expanded))
        }
        catch { return $null }
    }
    $allowedDirsFull = @($allowedDirsRaw | ForEach-Object {
            $r = Resolve-TaskPath $_
            if ($r) { $r.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar }
        } | Where-Object { $_ })
    function Test-InAllowlist([string]$p) {
        $full = Resolve-TaskPath $p
        if (-not $full) { return $false }
        foreach ($dir in $allowedDirsFull) {
            if ($full.StartsWith($dir, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    }

    # Interpreters are classified by their PAYLOAD, not their own path -- the
    # binary itself (powershell, python, ...) is never inside the repo, so
    # requiring it to resolve inside AF_TASK_SCRIPT_DIRS would be meaningless.
    $interpreterNames = @('powershell', 'pwsh', 'cmd', 'bash', 'sh', 'zsh', 'python', 'python3', 'node', 'perl', 'ruby', 'wscript', 'cscript')

    # Returns a deny reason, or $null when the command/args pair is acceptable.
    function Get-CommandDenyReason([string]$cmd, $argList) {
        if (-not $cmd) {
            return "Policy hard-deny: unrecognised task payload shape (no usable 'command' found); fail-closed. $sanctioned"
        }
        # `type: shell` hands `command` to the shell verbatim, so it may be a
        # whole command line. Metacharacters survive path normalisation, which
        # would let anything ride along behind an allowlisted script name.
        if ($cmd -match '[;&|\r\n`]' -or $cmd.Contains('$(')) {
            return "Policy hard-deny: task command '$cmd' contains a shell metacharacter, so it is a command line rather than a path to a reviewed script. $sanctioned"
        }
        $taskArgs = @()
        if ($argList) { $taskArgs = @($argList) }
        $cmdBase = ([System.IO.Path]::GetFileNameWithoutExtension($cmd)).ToLower()

        if ($interpreterNames -contains $cmdBase) {
            $inlinePayload = $false
            $fileTarget = $null
            $sawFileFlag = $false
            for ($i = 0; $i -lt $taskArgs.Count; $i++) {
                $a = [string]$taskArgs[$i]
                if ($a -match '(?i)^(-Command|-c|/c|-EncodedCommand)$') { $inlinePayload = $true; break }
                if ($a -match '(?i)^-File$') {
                    $sawFileFlag = $true
                    if (($i + 1) -lt $taskArgs.Count) { $fileTarget = [string]$taskArgs[$i + 1] }
                    break
                }
            }
            if ($inlinePayload) {
                return "Policy hard-deny: '$cmd' invoked with an inline command payload (-Command/-c/-EncodedCommand) that is not visible to the task classifier. $sanctioned"
            }
            if (-not $sawFileFlag) {
                $fileTarget = $taskArgs | Where-Object { $_ -and -not ([string]$_).StartsWith('-') } | Select-Object -First 1
            }
            if (-not $fileTarget -or -not (Test-InAllowlist ([string]$fileTarget))) {
                return "Policy hard-deny: '$cmd' payload '$fileTarget' does not resolve inside an AF_TASK_SCRIPT_DIRS directory (unrecognised or external script). $sanctioned"
            }
            return $null
        }
        if (-not (Test-InAllowlist $cmd)) {
            return "Policy hard-deny: task command '$cmd' does not resolve inside an AF_TASK_SCRIPT_DIRS directory. $sanctioned"
        }
        return $null
    }

    # An OS-specific scope overrides the task scope, so every variant present
    # must clear the bar -- checking only `command` classifies a decoy.
    $scopes = @(@{ n = 'task'; o = $task })
    foreach ($os in @('windows', 'linux', 'osx')) {
        if ($task.$os) { $scopes += @{ n = $os; o = $task.$os } }
    }
    foreach ($s in $scopes) {
        $o = $s.o
        if ($o.options -and $o.options.shell) {
            Emit-Task 'deny' ("Policy hard-deny: the '$($s.n)' scope overrides options.shell, which moves the executed payload into the shell's own arguments where the task classifier cannot see it. $sanctioned")
        }
        $effectiveCmd = if ($o.command) { [string]$o.command } else { [string]$task.command }
        $effectiveArgs = if ($null -ne $o.args) { $o.args } else { $task.args }
        $reason = Get-CommandDenyReason $effectiveCmd $effectiveArgs
        if ($reason) {
            if ($s.n -ne 'task') { $reason = "[$($s.n) override] $reason" }
            Emit-Task 'deny' $reason
        }
    }
    Emit-Task 'allow' 'Safe: every task scope resolves to a reviewed script under AF_TASK_SCRIPT_DIRS.'
}

# Extract the command string (runInTerminal / terminal shape only, from here).
# For run_task the command is not in the payload at all -- it is resolved from
# tasks.json further down, once Emit is defined.
$command = [string]$inputData.tool_input.command
if (-not $command -and -not $isTaskRun) {
    Write-Output '{}'
    exit 0
}

# ---------------------------------------------------------------------------
# Load autonomy config (path resolved by the shared preamble, read once).
# ---------------------------------------------------------------------------
$repo = $AfMainRoot
$confLines = @()
if ($AfConfFound) { $confLines = Get-Content $AfConfPath }
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
# run_task -- resolve the launch into a command line before classifying it.
#
# The payload names a task; a name is not a command. The command lives in the
# project's .vscode/tasks.json, so it is read back here and every scope is
# reconstructed into a command line. From that point on a task launch is
# classified by exactly the same tiers as a terminal command -- which is the
# point: `run_task` was a hole straight through the classifier.
#
# Anything that cannot be resolved answers 'ask', never silence. The gate says
# "I could not judge this" instead of producing the same bytes as consent.
# ===========================================================================
if ($isTaskRun) {
    $askTail = "The task launch could not be classified, so this needs a human decision. Check what the task runs in .vscode/tasks.json."
    $wsFolder = [string]$inputData.tool_input.workspaceFolder
    $taskId = [string]$inputData.tool_input.id
    if (-not $wsFolder -or -not $taskId) {
        Emit 'ask' "Unclassified task launch: the payload carries no workspaceFolder/id, so the task cannot be looked up. $askTail"
    }
    $tasksPath = Join-Path $wsFolder '.vscode/tasks.json'
    if (-not (Test-Path $tasksPath)) {
        Emit 'ask' "Unclassified task launch: no .vscode/tasks.json under '$wsFolder', so task '$taskId' cannot be resolved to a command. $askTail"
    }
    $tasksDoc = $null
    try {
        $tasksDoc = (Get-Content $tasksPath -Raw -ErrorAction Stop) | ConvertFrom-Json -ErrorAction Stop
    } catch {
        # tasks.json accepts JSONC in VS Code, so a comment or trailing comma
        # parses here as nothing at all. Unreadable is not the same as safe.
        Emit 'ask' "Unclassified task launch: .vscode/tasks.json is not strict JSON (comments or trailing commas), so task '$taskId' cannot be resolved. $askTail"
    }
    # VS Code addresses a task as '{type}: {label}' -- captured ids look like
    # 'shell: tests: all'. Only the first type prefix is stripped; the label
    # itself may contain a colon.
    $bareId = $taskId -replace '^[A-Za-z]+:\s+', ''
    $taskDef = $null
    foreach ($t in @($tasksDoc.tasks)) {
        if (-not $t) { continue }
        $lbl = [string]$t.label
        if ($lbl -and ($lbl -eq $taskId -or $lbl -eq $bareId)) { $taskDef = $t; break }
    }
    if (-not $taskDef) {
        Emit 'ask' "Unclassified task launch: no task labelled '$bareId' in .vscode/tasks.json. $askTail"
    }
    # Variables whose value is produced elsewhere (a prompt, a VS Code command,
    # a setting) hide the payload from the classifier.
    $taskText = $taskDef | ConvertTo-Json -Depth 10 -Compress
    foreach ($v in @('${input:', '${command:', '${config:')) {
        if ($taskText.Contains($v)) {
            Emit 'ask' "Unclassified task launch: task '$bareId' contains a '$v...}' variable, so its effective command line is not visible here. $askTail"
        }
    }
    # An OS-specific scope overrides the task scope, so every variant present
    # must be classified -- reading only `command` classifies a decoy.
    $runScopes = @($taskDef)
    foreach ($os in @('windows', 'linux', 'osx')) {
        if ($taskDef.$os) { $runScopes += $taskDef.$os }
    }
    $cmdLines = @()
    foreach ($o in $runScopes) {
        if ($o.options -and $o.options.shell) {
            Emit 'ask' "Unclassified task launch: task '$bareId' overrides options.shell, which moves the executed payload into the shell's own arguments where it cannot be classified. $askTail"
        }
        $c = if ($o.command) { [string]$o.command } else { [string]$taskDef.command }
        $a = if ($null -ne $o.args) { $o.args } else { $taskDef.args }
        if (-not $c) { continue }
        $line = if ($a) { ($c + ' ' + ((@($a) | ForEach-Object { [string]$_ }) -join ' ')) } else { $c }
        $cmdLines += $line.Trim()
    }
    $cmdLines = @($cmdLines | Where-Object { $_ })
    if ($cmdLines.Count -eq 0) {
        Emit 'ask' "Unclassified task launch: task '$bareId' declares no command (composite or extension-provided task). $askTail"
    }
    # Newline-joined: the deny tier scans the whole string and the allow tier
    # splits on newlines, so every scope must clear the bar independently.
    $command = $cmdLines -join "`n"
}

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
#
# A confirmation prompt is a question put to a human, and a question that does
# not say what it is about cannot be answered -- it can only be waved through.
# The whole tier used to share one sentence ("This command makes a durable
# change") for eleven different rules, naming neither the rule that fired nor
# the command it fired on, while the deny tier next door has been specific all
# along (issue #78). Each rule now says what it will actually do, and the
# command is echoed so the answer is about the command rather than about the
# category.
# ===========================================================================
$askRules = @(
    @{ p = 'git\s+merge\b';      why = "'git merge' rewrites the working tree and may leave conflict markers in tracked files" }
    @{ p = 'git\s+(checkout|switch)\b'; why = "'git checkout'/'git switch' changes the checked-out branch, and with a path argument it discards uncommitted changes to that path" }
    @{ p = 'git\s+tag\b';        why = "'git tag' creates or moves a tag, which is a release marker others may already rely on" }
    @{ p = '(?i)\bpip3?\s+(install|uninstall)\b'; why = 'pip install/uninstall changes the environment for everything that uses it, not just this task' }
    @{ p = '(?i)\bconda\s+(install|remove)\b';    why = 'conda install/remove changes the environment for everything that uses it, not just this task' }
    @{ p = '(?i)\bruff\s+format\b'; why = "'ruff format' rewrites source files in place" }
    @{ p = '(?i)\bdatabricks\b.*\b(submit|run|create|update|delete|import|export|deploy)\b'; why = 'this Databricks CLI call acts on a remote workspace, where the effect is outside this repository and outside git' }
    @{ p = '(?i)\baz\b.*\b(create|set|delete|update|deploy)\b'; why = 'this Azure CLI call changes cloud resources, where the effect is outside this repository and may cost money' }
    @{ p = '(?i)Remove-Item\b';  why = "'Remove-Item' deletes files or directories" }
    @{ p = '(?i)(^|\s)rm\b';     why = "'rm' deletes files or directories" }
    @{ p = '(?i)(Move-Item|Copy-Item|New-Item|mkdir|mv|cp)\b'; why = 'this writes to the filesystem (creates, moves or copies files)' }
)
# Echoing the command is the point of the prompt, but an unbounded string in a
# dialog is its own way of hiding information.
$shown = $command -replace '\s+', ' '
if ($shown.Length -gt 300) { $shown = $shown.Substring(0, 297) + '...' }
# Scan the quote-stripped command so quoted literals (e.g. a commit message
# mentioning "databricks ... export") do not falsely trigger an ASK rule.
foreach ($r in $askRules) {
    if ($strippedForGuard -match $r.p) {
        Emit 'ask' ("Durable change: $($r.why). Confirm it is intentional. Command: $shown")
    }
}

# Default: defer to the user's approval settings (fail-safe -- never auto-allow).
Write-Output '{}'
