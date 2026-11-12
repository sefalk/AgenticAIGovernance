# AF #541: record-only role routing and a separate Copilot-native live check.
param(
    [string]$LogPath = '',
    [string[]]$SessionIds = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_suite_env.ps1')
$subject = Join-Path (Split-Path $PSScriptRoot) 'hooks\scripts\copilot-scoped-probe.py'
$template = Join-Path (Split-Path $PSScriptRoot) 'hooks\copilot-scoped-probe.json.template'
$results = [ordered]@{}

function Add-Result([string]$Name, [bool]$Ok) {
    $script:results[$Name] = $Ok
}

function Test-RecordShape($Record) {
    $keys = @($Record.PSObject.Properties.Name | Sort-Object)
    $expected = @('agent_id', 'agent_type', 'error', 'event', 'parent_agent_id',
        'probe', 'route', 'session_id', 'status', 'timestamp') | Sort-Object
    return (($keys -join ',') -eq ($expected -join ',')) -and
        ($Record.probe -eq 'AF541_NATIVE_EXEC')
}

if ($LogPath) {
    if ($SessionIds.Count -eq 0) { throw 'Live verification requires explicit root and child SessionIds.' }
    $records = @(Get-Content -LiteralPath $LogPath |
        ForEach-Object { $_ | ConvertFrom-Json } |
        Where-Object { $SessionIds -contains $_.session_id })
    Add-Result 'Live: correlated records exist' ($records.Count -gt 0)
    Add-Result 'Live: metadata only, no routing errors' (@($records | Where-Object {
        (-not (Test-RecordShape $_)) -or $_.status -eq 'error' -or $null -ne $_.error
    }).Count -eq 0)
    Add-Result 'Live: main is not inferred as coordinator' (@($records | Where-Object {
        $_.status -eq 'main-unscoped' -and $null -eq $_.route
    }).Count -gt 0)
    Add-Result 'Live: coordinator pre route' (@($records | Where-Object {
        $_.route -eq 'coordinator-pretooluse'
    }).Count -gt 0)
    Add-Result 'Live: coordinator post route' (@($records | Where-Object {
        $_.route -eq 'coordinator-posttooluse'
    }).Count -gt 0)
    Add-Result 'Live: coordinator stop route' (@($records | Where-Object {
        $_.event -eq 'subagentStop' -and $_.route -eq 'coordinator-postmerge' -and $_.agent_id
    }).Count -gt 0)
    Add-Result 'Live: implementer stop route' (@($records | Where-Object {
        $_.event -eq 'subagentStop' -and $_.route -eq 'implementer-stop' -and $_.agent_id
    }).Count -gt 0)
    $stops = @($records | Where-Object { $_.route -and $_.event -eq 'subagentStop' })
    $repeats = @($stops | Group-Object session_id, agent_id | Where-Object { $_.Count -ne 1 })
    Add-Result 'Live: one stop route per observed child' ($stops.Count -gt 0 -and $repeats.Count -eq 0)
    $missing = @($SessionIds | Select-Object -Skip 1 | Where-Object {
        $childId = $_
        @($stops | Where-Object {
            $_.agent_id -eq $childId -or $_.session_id -eq $childId
        }).Count -ne 1
    })
    Add-Result 'Live: every requested child has exactly one stop route' ($missing.Count -eq 0)
    Add-Result 'Live: no agentStop role route' (@($records | Where-Object {
        $_.event -eq 'agentStop' -and $_.route
    }).Count -eq 0)
} else {
    $python = Get-AfSuitePython
    if (-not $python) { throw 'Python 3 is required; no tests were executed.' }
    $fixtureDir = Join-Path ([IO.Path]::GetTempPath()) ('af541-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixtureDir | Out-Null

    function Invoke-Probe([string]$Event, [string]$Payload) {
        $log = Join-Path $fixtureDir ([guid]::NewGuid().ToString('N') + '.jsonl')
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo.FileName = $python
        $p.StartInfo.Arguments = '"{0}" --event "{1}" --log "{2}"' -f $subject, $Event, $log
        $p.StartInfo.UseShellExecute = $false
        $p.StartInfo.RedirectStandardInput = $true
        $p.StartInfo.RedirectStandardOutput = $true
        $p.StartInfo.RedirectStandardError = $true
        $p.StartInfo.CreateNoWindow = $true
        try {
            [void]$p.Start()
            $p.StandardInput.Write($Payload)
            $p.StandardInput.Close()
            $stdout = $p.StandardOutput.ReadToEnd()
            $stderr = $p.StandardError.ReadToEnd()
            $p.WaitForExit()
            $rows = @()
            if (Test-Path -LiteralPath $log) {
                $rows = @(Get-Content -LiteralPath $log | ForEach-Object { $_ | ConvertFrom-Json })
            }
            return [pscustomobject]@{
                Exit = $p.ExitCode; Stdout = $stdout.Trim(); Stderr = $stderr; Rows = $rows
            }
        } finally { $p.Dispose() }
    }

    try {
        $cases = @(
            @{ Name = 'camel coordinator pre'; Event = 'preToolUse'; Payload = '{"agentType":"coordinator","sessionId":"root-1","agentId":"child-1","parentAgentId":"root-1"}'; Route = 'coordinator-pretooluse'; Status = 'routed' },
            @{ Name = 'snake coordinator post'; Event = 'postToolUse'; Payload = '{"agent_type":"coordinator","session_id":"root-1","agent_id":"child-1","parent_agent_id":"root-1"}'; Route = 'coordinator-posttooluse'; Status = 'routed' },
            @{ Name = 'equal aliases'; Event = 'subagentStop'; Payload = '{"agentType":"coordinator","agent_type":"coordinator"}'; Route = 'coordinator-postmerge'; Status = 'routed' },
            @{ Name = 'implementer stop'; Event = 'subagentStop'; Payload = '{"agentType":"implementer"}'; Route = 'implementer-stop'; Status = 'routed' },
            @{ Name = 'test writer stop'; Event = 'subagentStop'; Payload = '{"agent_type":"test-writer"}'; Route = 'test-writer-stop'; Status = 'routed' },
            @{ Name = 'refactorer stop'; Event = 'subagentStop'; Payload = '{"agentType":"refactorer"}'; Route = 'refactorer-stop'; Status = 'routed' },
            @{ Name = 'documenter stop'; Event = 'subagentStop'; Payload = '{"agentType":"documenter"}'; Route = 'documenter-stop'; Status = 'routed' },
            @{ Name = 'compliance stop'; Event = 'subagentStop'; Payload = '{"agentType":"compliance-checker"}'; Route = 'compliance-checker-stop'; Status = 'routed' },
            @{ Name = 'child agentStop is not a second gate'; Event = 'agentStop'; Payload = '{"agentType":"implementer","agentId":"child-1"}'; Route = $null; Status = 'event-unscoped' },
            @{ Name = 'main has no guessed role'; Event = 'preToolUse'; Payload = '{}'; Route = $null; Status = 'main-unscoped' },
            @{ Name = 'non-allowlisted role'; Event = 'subagentStop'; Payload = '{"agentType":"foreign-worker"}'; Route = $null; Status = 'role-not-allowlisted' },
            @{ Name = 'unmapped event'; Event = 'preToolUse'; Payload = '{"agentType":"implementer"}'; Route = $null; Status = 'event-unscoped' }
        )
        foreach ($case in $cases) {
            $r = Invoke-Probe $case.Event $case.Payload
            Add-Result $case.Name ($r.Exit -eq 0 -and $r.Stdout -eq '{}' -and
                -not $r.Stderr -and $r.Rows.Count -eq 1 -and
                (Test-RecordShape $r.Rows[0]) -and
                $r.Rows[0].route -eq $case.Route -and $r.Rows[0].status -eq $case.Status)
        }
        $errors = @(
            '{"agentType":"coordinator","agent_type":"implementer"}',
            '{"agentType":null}', '{"agentType":[]}', '{"agentType":""}',
            '{"agentType":"C:\\Users\\PRIVATE"}', '[]', '{broken',
            '{"agentType":"implementer","agentId":"child-1","agent_id":"other"}'
        )
        foreach ($payload in $errors) {
            $r = Invoke-Probe 'preToolUse' $payload
            Add-Result ('Explicit error ' + $results.Count) ($r.Exit -eq 0 -and
                $r.Stdout -eq '{}' -and $r.Stderr -match 'AF541 routing error:' -and
                $r.Rows.Count -eq 1 -and $r.Rows[0].status -eq 'error' -and
                $r.Rows[0].error -and $null -eq $r.Rows[0].route)
        }
        $private = '{"agentType":"coordinator","toolArgs":{"command":"ARG_MUST_NOT_LOG"},"toolResult":"RESULT_MUST_NOT_LOG","prompt":"PROMPT_MUST_NOT_LOG","cwd":"PATH_MUST_NOT_LOG","sessionId":"root-1","agentId":"child-1","parentAgentId":"parent-1"}'
        $r = Invoke-Probe 'postToolUse' $private
        $logged = $r.Rows | ConvertTo-Json -Depth 6 -Compress
        Add-Result 'Correlation without private fields' ($r.Rows.Count -eq 1 -and
            (Test-RecordShape $r.Rows[0]) -and $logged -notmatch 'MUST_NOT_LOG' -and
            $r.Rows[0].session_id -eq 'root-1' -and $r.Rows[0].agent_id -eq 'child-1' -and
            $r.Rows[0].parent_agent_id -eq 'parent-1')

        $configured = $false
        if (Test-Path -LiteralPath $template) {
            $config = Get-Content -LiteralPath $template -Raw | ConvertFrom-Json
            $events = @($config.hooks.PSObject.Properties.Name | Sort-Object)
            $commands = @($config.hooks.PSObject.Properties | ForEach-Object { $_.Value })
            $bad = @($commands | Where-Object {
                $_.exec -ne 'python' -or $_.type -ne 'command' -or $_.args.Count -ne 5 -or
                @($_.PSObject.Properties.Name | Where-Object {
                    $_ -in @('command', 'bash', 'powershell', 'windows', 'linux', 'osx')
                }).Count -gt 0
            })
            $configured = $config.version -eq 1 -and
                ($events -join ',') -eq 'postToolUse,preToolUse,subagentStop' -and $bad.Count -eq 0
        }
        Add-Result 'Inactive native template with one stop registration' $configured
    } finally {
        foreach ($f in Get-ChildItem -LiteralPath $fixtureDir -File) {
            Remove-Item -LiteralPath $f.FullName
        }
        Remove-Item -LiteralPath $fixtureDir
    }
}

$failed = @($results.Values | Where-Object { -not $_ }).Count
foreach ($name in $results.Keys) {
    $status = if ($results[$name]) { 'PASS' } else { 'FAIL' }
    Write-Output "  $status  $name"
}
Write-Output "AF541: $($results.Count - $failed)/$($results.Count) passed"
if ($failed) { exit 1 }
exit 0
