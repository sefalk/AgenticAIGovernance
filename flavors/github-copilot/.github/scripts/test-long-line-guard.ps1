# Regression suite: a long line in a large tool result is announced, and a
# lossless copy is offered (#341).
#
# Copilot Chat writes any tool result over its spill threshold (8 KiB by
# default) to a file and hands the model only the path. The model then has to
# use read_file, which cuts every line over 2,000 characters. A work-item
# description is often one HTML line, so it arrived cut mid-sentence and the
# agent noticed only because the text stopped.
#
# read_file itself cannot be watched: its tool_response reaches hooks empty.
# The tool that PRODUCED the long result can -- PostToolUse sees the full text
# before the spill. So the check rides in the existing PostToolUse process and
# answers with additionalContext, which stays inline as its own text part.
#
# Payloads are sent as raw UTF-8 bytes, the way the harness sends them: a
# PowerShell pipeline would re-encode them and hide the loss this suite guards.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ghDir = Split-Path -Parent $scriptDir
$hookScripts = Join-Path $ghDir 'hooks/scripts'
$psHook = Join-Path $hookScripts 'scan-secrets.ps1'
$shHook = Join-Path $hookScripts 'scan-secrets.sh'
$limitsFile = Join-Path $hookScripts 'tool-limits.json'
$skillFiles = @((Join-Path $ghDir 'skills/ado-shared/SKILL.md'), (Join-Path $ghDir 'skills/ado-workitem/SKILL.md'))

$results = [ordered]@{}
$details = [ordered]@{}
$notes = @()

function Add-Result([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

$bashExe = $null
foreach ($b in @('C:\Program Files\Git\bin\bash.exe', '/bin/bash')) {
    if (Test-Path $b) { $bashExe = $b; break }
}

# o-umlaut, sharp s, L-stroke: the last one has a byte (0x81) cp1252 cannot map.
$nonAscii = [string][char]0xF6 + [char]0xDF + [char]0x141
$utf8 = New-Object Text.UTF8Encoding $false

function Invoke-Hook {
    param([string]$Payload, [string]$Dialect = 'ps')
    if ($Dialect -eq 'sh') {
        $psi = New-Object Diagnostics.ProcessStartInfo $bashExe, ('"' + ($shHook -replace '\\', '/') + '"')
    } else {
        $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $psHook + '"')
    }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $bytes = $script:utf8.GetBytes($Payload)
    $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $p.StandardInput.Close()
    $ms = New-Object IO.MemoryStream
    $p.StandardOutput.BaseStream.CopyTo($ms)
    $p.WaitForExit()
    $null = $errTask.Result
    $out = $script:utf8.GetString($ms.ToArray()).Trim()
    $context = ''
    $copy = ''
    try {
        $parsed = $out | ConvertFrom-Json
        $hso = $parsed.PSObject.Properties['hookSpecificOutput']
        if ($hso -and $hso.Value.PSObject.Properties['additionalContext']) {
            $context = [string]$hso.Value.additionalContext
        }
        $ll = $parsed.PSObject.Properties['longLines']
        if ($ll -and $ll.Value.PSObject.Properties['copy']) { $copy = [string]$ll.Value.copy }
    } catch {
        $context = '<unparsable>'
    }
    return [pscustomobject]@{ Exit = $p.ExitCode; Out = $out; Context = $context; Copy = $copy }
}

function New-ToolPayload([string]$Tool, [string]$Response) {
    return (@{ tool_name = $Tool; tool_input = @{ id = 1 }; tool_response = $Response; tool_use_id = 'toolu_af341_' + [guid]::NewGuid().ToString('N').Substring(0, 8) } | ConvertTo-Json -Compress)
}

# A long line shaped like ADO's untrusted envelope: plain text, not JSON.
$longLine = ('<p>' + ('word ' * 700) + $nonAscii + ' end-of-description</p>')
$filler = (1..120 | ForEach-Object { "line $_ of ordinary width" }) -join "`n"
$textResponse = "[UNTRUSTED CONTENT]`n" + $filler + "`n" + $longLine + "`n" + $filler
$shortOnly = ((1..400 | ForEach-Object { "line $_ of ordinary width" }) -join "`n")
$smallLong = ('x' * 2500)
$jsonResponse = (@{ id = 3106; fields = @{ 'System.Title' = 't'; 'System.Description' = $longLine; 'System.History' = ($filler + "`n" + $filler) } } | ConvertTo-Json -Compress)

$tool = 'mcp_azure_devops__wit_work_item'
$copies = @()

try {
    $r = Invoke-Hook (New-ToolPayload $tool $textResponse)
    $copies += $r.Copy
    Add-Result 'L1_a_spilled_long_line_is_announced_with_its_length' `
        ($r.Exit -eq 0 -and $r.Context -match "\b$($longLine.Length)\b" -and $r.Context -match '2,?000') `
        "exit=$($r.Exit) context=$($r.Context) out=$($r.Out)"

    $copyText = if ($r.Copy -and (Test-Path $r.Copy)) { [IO.File]::ReadAllText($r.Copy, $utf8) } else { '' }
    $copyLines = @($copyText -split "`n")
    Add-Result 'L2_every_line_of_the_copy_fits_read_file' `
        ($copyText.Length -gt 0 -and @($copyLines | Where-Object { $_.Length -gt 2000 }).Count -eq 0) `
        "copy='$($r.Copy)' longest=$(($copyLines | Measure-Object Length -Maximum).Maximum)"

    $marker = ' <<AF-WRAP>>'
    $rejoined = ($copyText -replace [regex]::Escape($marker + "`n"), '')
    Add-Result 'L3_the_copy_is_lossless_including_non_ascii' `
        ($rejoined.Contains($longLine) -and $rejoined.Contains($nonAscii)) `
        "long line recovered=$($rejoined.Contains($longLine)) non-ascii recovered=$($rejoined.Contains($nonAscii))"

    $r = Invoke-Hook (New-ToolPayload $tool $shortOnly)
    Add-Result 'L4_a_large_result_with_short_lines_is_left_alone' ($r.Exit -eq 0 -and $r.Out -eq '{}') "out=$($r.Out)"

    $r = Invoke-Hook (New-ToolPayload $tool $smallLong)
    Add-Result 'L5_a_long_line_below_the_spill_threshold_is_left_alone' ($r.Exit -eq 0 -and $r.Out -eq '{}') "out=$($r.Out)"

    $r = Invoke-Hook (New-ToolPayload $tool $jsonResponse)
    $copies += $r.Copy
    Add-Result 'L6_a_json_result_is_judged_as_the_spill_pretty_prints_it_and_names_the_field' `
        ($r.Context -match 'System\.Description') "context=$($r.Context)"

    $r = Invoke-Hook (New-ToolPayload 'execution_subagent' $textResponse)
    Add-Result 'L7_a_tool_the_harness_never_spills_is_left_alone' ($r.Out -eq '{}') "out=$($r.Out)"

    if ($bashExe) {
        $r = Invoke-Hook (New-ToolPayload $tool $textResponse) 'sh'
        $copies += $r.Copy
        Add-Result 'L8_the_bash_twin_announces_the_same_line' `
            ($r.Context -match "\b$($longLine.Length)\b") "context=$($r.Context) out=$($r.Out)"
    } else {
        Add-Result 'L8_the_bash_twin_announces_the_same_line' $false 'no bash found -- this case would prove nothing'
    }

    $limits = $null
    try { $limits = Get-Content $limitsFile -Raw | ConvertFrom-Json } catch { $limits = $null }
    $shapeOk = $false
    if ($limits -and $limits.PSObject.Properties['limits']) {
        $shapeOk = $true
        foreach ($k in 'spill_threshold_chars', 'read_file_line_chars') {
            $e = $limits.limits.PSObject.Properties[$k]
            if (-not $e) { $shapeOk = $false; continue }
            foreach ($f in 'value', 'source', 'configurable', 'workaround') {
                if (-not $e.Value.PSObject.Properties[$f]) { $shapeOk = $false }
            }
        }
    }
    Add-Result 'L9_the_limits_are_a_structured_record' $shapeOk "file=$limitsFile"

    $skillText = ($skillFiles | Where-Object { Test-Path $_ } | ForEach-Object { Get-Content $_ -Raw }) -join "`n"
    Add-Result 'L10_the_ado_skills_point_at_the_record_and_the_narrow_read' `
        ($skillText.Contains('tool-limits.json') -and $skillText -match '"System\.Description"\]') 'skills must name tool-limits.json and a fields-scoped read'

    # Setting [Console]::*Encoding calls SetConsoleCP and flips the CALLER's
    # console too; its later pipes then carry a BOM and the secret scan answered
    # {} for every payload. Caught here during #341 before it shipped.
    $leaky = @(Get-ChildItem $hookScripts -Filter *.ps1 | Where-Object {
            (Get-Content $_.FullName -Raw) -match '\[Console\]::(Input|Output)Encoding\s*='
        } | Select-Object -ExpandProperty Name)
    Add-Result 'L11_no_hook_sets_the_console_encoding' ($leaky.Count -eq 0) "sets it: $($leaky -join ', ')"

    $cpBefore = (chcp) -replace '\D', ''
    '{"tool_name":"read_file","tool_input":{}}' | & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $psHook | Out-Null
    '{"tool_name":"read_file","tool_input":{}}' | & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $hookScripts 'block-dangerous.ps1') | Out-Null
    $cpAfter = (chcp) -replace '\D', ''
    Add-Result 'L12_a_hook_call_leaves_the_callers_code_page_alone' ($cpBefore -eq $cpAfter) "before=$cpBefore after=$cpAfter"

    # Drift: the record is only true for the extension it was measured on. CI
    # has no VS Code, so there the comparison is reported, never counted.
    $pkgs = @()
    foreach ($root in @((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code'), (Join-Path $env:USERPROFILE '.vscode\extensions'))) {
        if ($root -and (Test-Path $root)) {
            $pkgs += @(Get-ChildItem $root -Recurse -Depth 5 -Filter package.json -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match '[\\/](copilot|github\.copilot-chat-[^\\/]+)[\\/]package\.json$' })
        }
    }
    if (-not $limits) {
        Add-Result 'D1_the_record_matches_the_installed_extension' $false "no readable record at $limitsFile"
    } elseif ($pkgs.Count -eq 0) {
        $notes += 'D1 not measurable here: no installed Copilot Chat extension found.'
    } else {
        $pkg = $pkgs | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $text = [IO.File]::ReadAllText($pkg.FullName)
        $m = [regex]::Match($text, '"github\.copilot\.chat\.agent\.largeToolResultsToDisk\.thresholdBytes"\s*:\s*\{[^}]*"default"\s*:\s*(\d+)')
        $js = Join-Path (Split-Path $pkg.FullName) 'dist/extension.js'
        $cap = ''
        if (Test-Path $js) {
            $jsText = [IO.File]::ReadAllText($js)
            $v = [regex]::Match($jsText, 'long lines were truncated at \$\{(\w+)\}')
            if ($v.Success) {
                $c = [regex]::Match($jsText, '[,;\s]' + [regex]::Escape($v.Groups[1].Value) + '=(\d+(?:e\d+)?)[,;]')
                if ($c.Success) { $cap = [string][int][double]$c.Groups[1].Value }
            }
        }
        $want = "$($limits.limits.spill_threshold_chars.value)/$($limits.limits.read_file_line_chars.value)"
        $got = "$($m.Groups[1].Value)/$cap"
        Add-Result 'D1_the_record_matches_the_installed_extension' ($m.Success -and $got -eq $want) "record=$want installed=$got ($($pkg.FullName))"
    }
} finally {
    foreach ($c in $copies) { if ($c -and (Test-Path $c)) { Remove-Item $c -Force -ErrorAction SilentlyContinue } }
}

Write-Output '===== long-line safety net tests (issue #341) ====='
foreach ($n in $notes) { Write-Output "NOTE  $n" }
$failed = 0
foreach ($k in $results.Keys) {
    if ($results[$k]) {
        Write-Output "PASS  $k"
    } else {
        $failed++
        Write-Output "FAIL  $k"
        Write-Output "      $($details[$k])"
    }
}
Write-Output "----- $($results.Count - $failed)/$($results.Count) passed -----"
if ($failed -gt 0) { exit 1 }
exit 0
