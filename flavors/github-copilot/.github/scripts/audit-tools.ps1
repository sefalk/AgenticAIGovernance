# Agent Tool Audit Script
# copilot:generated | implementer | 2026-03-31
#
# Compares agent tool assignments against the tools-reference.txt baseline
# and TOOLS.md matrix. Reports:
#   - Unknown tools (in agents but not in reference)
#   - Missing from TOOLS.md (in agents but not documented)
#   - Documented but unassigned (in TOOLS.md matrix but no agent has it)
#   - MCP tools (listed separately, not validated against reference)
#
# Usage:
#   .github/scripts/audit-tools.ps1              # Full audit
#   .github/scripts/audit-tools.ps1 -Verbose     # Include per-agent details

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = (Resolve-Path "$PSScriptRoot/../..").Path
$agentsDir = Join-Path $workspaceRoot '.github/agents'
$refFile = Join-Path $workspaceRoot '.github/scripts/tools-reference.txt'
$toolsDoc = Join-Path $workspaceRoot '.github/TOOLS.md'

# ── Step 1: Load reference baseline ──────────────────────────────────────

if (-not (Test-Path $refFile)) {
    Write-Output "ERROR: tools-reference.txt not found at $refFile"
    exit 1
}

$referenceTools = Get-Content $refFile |
    Where-Object { $_ -and -not $_.StartsWith('#') } |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ }

Write-Output "=== Agent Tool Audit ==="
Write-Output ""
Write-Output "Reference baseline: $($referenceTools.Count) built-in tools"

# ── Step 2: Parse agent frontmatter ──────────────────────────────────────

$agentFiles = Get-ChildItem -Path $agentsDir -Filter '*.agent.md' -ErrorAction SilentlyContinue
if (-not $agentFiles) {
    Write-Output "ERROR: No .agent.md files found in $agentsDir"
    exit 1
}

$agentTools = @{}       # agent name -> tool list
$allAgentTools = @{}    # tool -> list of agents using it
$mcpTools = @{}         # mcp tool -> list of agents using it

foreach ($file in $agentFiles) {
    $content = Get-Content $file.FullName -Raw
    $agentName = $file.BaseName -replace '\.agent$', ''

    # Extract YAML frontmatter between --- markers
    if ($content -match '(?s)^---\r?\n(.*?)\r?\n---') {
        $frontmatter = $Matches[1]

        # Extract tools list (simple YAML array parsing)
        $tools = @()
        $inTools = $false
        foreach ($line in ($frontmatter -split '\r?\n')) {
            if ($line -match '^\s*tools:\s*$') {
                $inTools = $true
                continue
            }
            if ($inTools) {
                if ($line -match '^\s+-\s+(.+)$') {
                    $tools += $Matches[1].Trim().Trim("'`"")
                } elseif ($line -match '^\s*\w+:') {
                    # New YAML key, stop parsing tools
                    $inTools = $false
                }
            }
        }

        $agentTools[$agentName] = $tools

        foreach ($tool in $tools) {
            if ($tool -match '^(pylance-mcp-server|mcp-)') {
                if (-not $mcpTools.ContainsKey($tool)) { $mcpTools[$tool] = @() }
                $mcpTools[$tool] += $agentName
            } else {
                if (-not $allAgentTools.ContainsKey($tool)) { $allAgentTools[$tool] = @() }
                $allAgentTools[$tool] += $agentName
            }
        }
    }
}

Write-Output "Agents scanned: $($agentTools.Count)"
Write-Output "Unique built-in tools in use: $($allAgentTools.Count)"
Write-Output "MCP tools in use: $($mcpTools.Count)"
Write-Output ""

# ── Step 3: Parse TOOLS.md matrix ────────────────────────────────────────

$documentedTools = @()
if (Test-Path $toolsDoc) {
    $matrixStarted = $false
    foreach ($line in (Get-Content $toolsDoc)) {
        # Detect table rows with tool identifiers (backtick-wrapped)
        if ($line -match '^\|\s*`([^`]+)`') {
            $toolId = $Matches[1]
            # Skip category headers and annotations
            if ($toolId -notmatch '^\*\*' -and $toolId -ne 'Tool (frontmatter key)') {
                # Strip trailing annotations like " (workers)" or " (invoke subagents)"
                $toolId = ($toolId -split '\s+\(')[0]
                $documentedTools += $toolId
            }
        }
    }
    Write-Output "TOOLS.md documents: $($documentedTools.Count) tools"
} else {
    Write-Output "WARNING: TOOLS.md not found -- skipping matrix comparison"
}
Write-Output ""

# ── Step 4: Compare and report ───────────────────────────────────────────

$issues = 0

# 4a: Unknown tools (in agents but not in reference and not MCP)
$unknownTools = $allAgentTools.Keys | Where-Object { $_ -notin $referenceTools }
if ($unknownTools) {
    Write-Output "## UNKNOWN TOOLS (in agents, not in reference baseline)"
    Write-Output "   These may be invalid identifiers or newly added tools."
    Write-Output "   If valid, add them to tools-reference.txt."
    Write-Output ""
    foreach ($tool in ($unknownTools | Sort-Object)) {
        $agents = ($allAgentTools[$tool] | Sort-Object) -join ', '
        Write-Output "   UNKNOWN: $tool"
        Write-Output "            Used by: $agents"
    }
    Write-Output ""
    $issues += $unknownTools.Count
}

# 4b: In agents but not documented in TOOLS.md
if ($documentedTools) {
    $undocumented = $allAgentTools.Keys | Where-Object { $_ -notin $documentedTools -and $_ -in $referenceTools }
    if ($undocumented) {
        Write-Output "## UNDOCUMENTED (in agents, valid, but not in TOOLS.md matrix)"
        Write-Output ""
        foreach ($tool in ($undocumented | Sort-Object)) {
            $agents = ($allAgentTools[$tool] | Sort-Object) -join ', '
            Write-Output "   UNDOCUMENTED: $tool"
            Write-Output "                 Used by: $agents"
        }
        Write-Output ""
        $issues += $undocumented.Count
    }
}

# 4c: In TOOLS.md matrix but no agent has it assigned
if ($documentedTools) {
    $orphaned = $documentedTools | Where-Object { $_ -notin $allAgentTools.Keys -and $_ -notin $mcpTools.Keys }
    if ($orphaned) {
        Write-Output "## DOCUMENTED BUT UNASSIGNED (in TOOLS.md but no agent uses it)"
        Write-Output "   These may be intentionally unassigned or out of date."
        Write-Output ""
        foreach ($tool in ($orphaned | Sort-Object)) {
            Write-Output "   ORPHANED: $tool"
        }
        Write-Output ""
        # Not counted as issues -- may be intentional
    }
}

# 4d: MCP tools summary
if ($mcpTools.Count -gt 0) {
    Write-Output "## MCP TOOLS (not validated against reference -- project-specific)"
    Write-Output ""
    foreach ($tool in ($mcpTools.Keys | Sort-Object)) {
        $agents = ($mcpTools[$tool] | Sort-Object) -join ', '
        Write-Output "   $tool"
        Write-Output "     Used by: $agents"
    }
    Write-Output ""
}

# ── Step 5: Per-agent detail (verbose) ───────────────────────────────────

if ($Verbose) {
    Write-Output "## PER-AGENT DETAILS"
    Write-Output ""
    foreach ($agent in ($agentTools.Keys | Sort-Object)) {
        $tools = $agentTools[$agent]
        $builtIn = $tools | Where-Object { $_ -notmatch '^(pylance-mcp-server|mcp-)' }
        $mcp = $tools | Where-Object { $_ -match '^(pylance-mcp-server|mcp-)' }
        $unknownCount = ($builtIn | Where-Object { $_ -notin $referenceTools }).Count

        Write-Output "   $agent ($($tools.Count) tools: $($builtIn.Count) built-in, $($mcp.Count) MCP)"
        if ($unknownCount -gt 0) {
            Write-Output "     WARNING: $unknownCount unknown tool(s)"
        }
    }
    Write-Output ""
}

# ── Summary ──────────────────────────────────────────────────────────────

Write-Output "=== Summary ==="
if ($issues -eq 0) {
    Write-Output "  OK All agent tools valid and documented"
    Write-Output "  Built-in: $($allAgentTools.Count) unique tools across $($agentTools.Count) agents"
    Write-Output "  MCP: $($mcpTools.Count) unique tools"
    exit 0
} else {
    Write-Output "  X $issues issue(s) found -- review above"
    exit 1
}
