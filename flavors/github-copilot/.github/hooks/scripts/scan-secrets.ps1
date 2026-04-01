# PostToolUse hook: Scan edited files for hardcoded secrets.
#
# Checks for common secret patterns in files touched by file-editor tools.
# Uses gitleaks if available, falls back to regex pattern matching.
# Blocking -- exits with code 1 when secrets are detected (HARD gate).

$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot/hook-utils.ps1"

# Read and parse stdin
$raw = [Console]::In.ReadToEnd()
try {
    $inputData = $raw | ConvertFrom-Json
} catch {
    Write-Output '{}'
    exit 0
}

# Only inspect file-editor tool calls
$toolName = $inputData.tool_name
if ($toolName -notmatch 'editFile|createFile|editNotebook|writeFile') {
    Write-Output '{}'
    exit 0
}

# Extract file path
$filePath = $inputData.tool_input.filePath
if (-not $filePath -or -not (Test-Path $filePath)) {
    Write-Output '{}'
    exit 0
}

# Skip non-text files
$ext = [System.IO.Path]::GetExtension($filePath)
$textExts = @('.py', '.md', '.yaml', '.yml', '.json', '.jsonc', '.toml', '.cfg', '.ini', '.sh', '.ps1', '.txt', '.env')
if ($ext -and $ext -notin $textExts) {
    Write-Output '{}'
    exit 0
}

# Try gitleaks first
$gitleaks = Get-Command gitleaks -ErrorAction SilentlyContinue
if ($gitleaks) {
    $result = & gitleaks detect --no-git --source $filePath --no-color 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-HookTrace -Hook 'scan-secrets' -Event 'block' -Tool $toolName -Detail "gitleaks: $filePath"
        $output = @{
            gate = "secret-scan"
            status = "FAIL"
            tool = "gitleaks"
            file = $filePath
            detail = ($result | Out-String).Trim()
        } | ConvertTo-Json -Compress
        Write-Output $output
        exit 1
    }
    Write-Output '{}'
    exit 0
}

# Fallback: regex pattern matching
$content = Get-Content $filePath -Raw -ErrorAction SilentlyContinue
if (-not $content) {
    Write-Output '{}'
    exit 0
}

$secretPatterns = @(
    @{ name = "AWS Key"; pattern = 'AKIA[0-9A-Z]{16}' }
    @{ name = "Generic Secret"; pattern = '(?i)(password|secret|token|api_key|apikey)\s*[:=]\s*["\x27][^\s"'']{8,}' }
    @{ name = "Private Key"; pattern = '-----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----' }
    @{ name = "Connection String"; pattern = '(?i)(Server|Data Source)=.+;(User Id|Password)=' }
)

$findings = @()
foreach ($p in $secretPatterns) {
    if ($content -match $p.pattern) {
        $findings += $p.name
    }
}

if ($findings.Count -gt 0) {
    Write-HookTrace -Hook 'scan-secrets' -Event 'block' -Tool $toolName -Detail "regex: $($findings -join ', ') in $filePath"
    $output = @{
        gate = "secret-scan"
        status = "FAIL"
        tool = "regex-fallback"
        file = $filePath
        patterns = $findings -join ", "
    } | ConvertTo-Json -Compress
    Write-Output $output
    exit 1
}

# --- Provenance marker check (SOFT advisory -- Idea 37a) ---
# Check if new/modified Python files have required copilot: provenance markers.
# Advisory only -- does not block. Documenter post-flight is the HARD gate.
if ($ext -eq '.py') {
    $firstLines = Get-Content $filePath -TotalCount 5 -ErrorAction SilentlyContinue | Out-String
    if ($firstLines -and $firstLines -notmatch 'copilot:(generated|modified)') {
        $advisory = @{
            gate = "provenance-check"
            status = "WARN"
            file = $filePath
            detail = "No copilot:generated or copilot:modified marker found in first 5 lines. " +
                "If this file was created or substantially modified by an agent, add a provenance marker. " +
                "See instructions/provenance.instructions.md."
        } | ConvertTo-Json -Compress
        Write-Output $advisory
        exit 0
    }
}

Write-Output '{}'
exit 0
