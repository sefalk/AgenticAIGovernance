# Session-start validity check for AF_GH_TOKEN (#563).
#
# Renewing a fine-grained PAT issues a new value; the old one fails at once
# with 401. Readiness only ever checked that a token variable was present, so
# the af-github MCP server broke with no session-start signal. These cases run
# the checker against a local HTTP stub -- no network, no real token -- and the
# readiness hook in place, which must carry the result to the model.
# Run from anywhere:
#   powershell -File .github/scripts/test-gh-token-check.ps1
$ErrorActionPreference = 'Continue'

$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir '_suite_env.ps1')
$hooksDir = (Resolve-Path (Join-Path $scriptDir '..\hooks\scripts')).Path
$checker = Join-Path $hooksDir '_gh_token_check.py'
$python = Get-AfSuitePython -ScriptsDir $scriptDir
if (-not $python) { Write-Host 'FAIL python -- no Python 3 interpreter for the checker'; exit 1 }

$results = [ordered]@{}
$work = Join-Path ([IO.Path]::GetTempPath()) ("af-gh-token-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $work | Out-Null
$token = 'af563-fixture-' + [guid]::NewGuid().ToString('N')

# Stub API: /<scenario>/user answers like GET /user does, and only for the
# expected bearer token, so a checker that drops the header reads as rejected.
$stub = Join-Path $work 'stub.py'
Set-Content -Path $stub -Encoding ascii -Value @'
import datetime, http.server, json, sys, time
TOKEN, PORTFILE = sys.argv[1], sys.argv[2]
def stamp(days):
    d = datetime.date.today() + datetime.timedelta(days=days)
    return d.isoformat() + " 12:00:00 +0100"
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        scenario = self.path.strip("/").split("/")[0]
        if scenario == "slow": time.sleep(8)
        if scenario == "err": return self.reply(500, {}, {})
        if self.headers.get("Authorization") != "Bearer " + TOKEN or scenario == "bad":
            return self.reply(401, {"message": "Bad credentials"}, {})
        headers = {}
        if scenario in ("ok", "slow"): headers["github-authentication-token-expiration"] = stamp(40)
        if scenario == "soon": headers["github-authentication-token-expiration"] = stamp(5)
        if scenario == "edge13": headers["github-authentication-token-expiration"] = stamp(13)
        if scenario == "edge14": headers["github-authentication-token-expiration"] = stamp(14)
        if scenario == "utc": headers["github-authentication-token-expiration"] = (datetime.date.today() + datetime.timedelta(days=40)).isoformat() + " 09:00:00 UTC"
        self.reply(200, {"login": "probe-user"}, headers)
    def reply(self, code, body, headers):
        data = json.dumps(body).encode()
        self.send_response(code)
        for k, v in headers.items(): self.send_header(k, v)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(PORTFILE, "w").write(str(srv.server_address[1]))
srv.serve_forever()
'@
$portFile = Join-Path $work 'port.txt'
$server = Start-Process -FilePath $python -ArgumentList @("`"$stub`"", $token, "`"$portFile`"") -PassThru -WindowStyle Hidden
$deadline = (Get-Date).AddSeconds(15)
while (-not (Test-Path $portFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
Start-Sleep -Milliseconds 200
$port = if (Test-Path $portFile) { (Get-Content $portFile -Raw).Trim() } else { '' }
if (-not $port) { Write-Host 'FAIL stub -- the local API stub did not start'; Stop-Process -Id $server.Id -ErrorAction SilentlyContinue; exit 1 }
$base = "http://127.0.0.1:$port"

$root = Join-Path $work 'project'
New-Item -ItemType Directory -Force $root | Out-Null

function Invoke-Check([string]$scenario, [string]$tok, [string]$projectRoot = $root) {
    $saved = @{ T = $env:AF_GH_TOKEN; U = $env:AF_GH_API_URL }
    $env:AF_GH_TOKEN = $tok
    $env:AF_GH_API_URL = "$base/$scenario"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { $out = & $python $checker --root $projectRoot 2>&1 | Out-String; $code = $LASTEXITCODE }
    finally { $env:AF_GH_TOKEN = $saved.T; $env:AF_GH_API_URL = $saved.U }
    $sw.Stop()
    return [pscustomobject]@{ Out = $out.Trim(); Code = $code; Secs = $sw.Elapsed.TotalSeconds }
}

$all = New-Object System.Collections.Generic.List[string]
function Track($r) { $all.Add($r.Out); return $r }

$in40 = (Get-Date).Date.AddDays(40).ToString('yyyy-MM-dd')
$in5 = (Get-Date).Date.AddDays(5).ToString('yyyy-MM-dd')

# A: a valid token reports login and expiry, and is no warning.
$r = Track (Invoke-Check 'ok' $token)
$results['A_valid_reports_login_and_expiry'] = ($r.Code -eq 0 -and $r.Out -match 'AF_GH_TOKEN' -and $r.Out -match 'valid' -and $r.Out -match 'login=probe-user' -and $r.Out -match [regex]::Escape($in40) -and $r.Out -match 'in 40 days')
$results['A_valid_is_not_a_warning'] = ($r.Out -notmatch 'WARNING')

# B: expiry inside 14 days is a visible warning naming the date.
$r = Track (Invoke-Check 'soon' $token)
$results['B_expiring_warns'] = ($r.Code -eq 0 -and $r.Out -match '^WARNING' -and $r.Out -match [regex]::Escape($in5) -and $r.Out -match 'in 5 days')
$r13 = Track (Invoke-Check 'edge13' $token); $r14 = Track (Invoke-Check 'edge14' $token)
$results['B_threshold_is_14_days'] = ($r13.Out -match '^WARNING' -and $r14.Out -notmatch 'WARNING' -and $r14.Out -match 'in 14 days')

# C: a rejected token is a visible warning that says what breaks.
$r = Track (Invoke-Check 'bad' $token)
$results['C_rejected_warns'] = ($r.Code -eq 0 -and $r.Out -match '^WARNING' -and $r.Out -match '401' -and $r.Out -match 'af-github')

# D: the expiry header in its UTC form parses too; a missing header is said.
$r = Track (Invoke-Check 'utc' $token)
$results['D_utc_expiry_parsed'] = ($r.Out -match [regex]::Escape($in40) -and $r.Out -notmatch 'WARNING')
$r = Track (Invoke-Check 'noexp' $token)
$results['D_no_expiry_reported'] = ($r.Out -match 'valid' -and $r.Out -match 'expires=not reported' -and $r.Out -notmatch 'WARNING')

# E: an unreachable or failing API is "not verified" -- not valid, not rejected.
$r = Track (Invoke-Check 'err' $token)
$results['E_server_error_not_verified'] = ($r.Code -eq 0 -and $r.Out -match 'not verified' -and $r.Out -match '500' -and $r.Out -notmatch 'valid \|')
$saved = $base; $base = 'http://127.0.0.1:9'
$r = Track (Invoke-Check 'ok' $token)
$base = $saved
$results['E_unreachable_not_verified'] = ($r.Code -eq 0 -and $r.Out -match 'not verified')

# F: a slow API cannot hold the session start hostage.
$r = Track (Invoke-Check 'slow' $token)
$results['F_slow_api_times_out'] = ($r.Code -eq 0 -and $r.Out -match 'not verified' -and $r.Secs -lt 7)

# G: no token and no consumer is silence; no token with a consumer is a warning.
$r = Track (Invoke-Check 'ok' '')
$results['G_unset_unreferenced_silent'] = ($r.Code -eq 0 -and $r.Out -eq '')
$consumer = Join-Path $work 'consumer'
New-Item -ItemType Directory -Force $consumer | Out-Null
Set-Content -Path (Join-Path $consumer '.mcp.json') -Encoding ascii -Value '{"mcpServers":{"af-github":{"headers":{"Authorization":"Bearer ${AF_GH_TOKEN}"}}}}'
$r = Track (Invoke-Check 'ok' '' $consumer)
$results['G_unset_referenced_warns'] = ($r.Code -eq 0 -and $r.Out -match '^WARNING' -and $r.Out -match 'AF_GH_TOKEN is not set' -and $r.Out -match '\.mcp\.json')

# H: the readiness hook carries the line to the model, top level and nested.
$savedT = $env:AF_GH_TOKEN; $savedU = $env:AF_GH_API_URL
$env:AF_GH_TOKEN = $token; $env:AF_GH_API_URL = "$base/bad"
try { $hookOut = '{}' | powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hooksDir 'session-mcp-readiness.ps1') 2>$null | Out-String }
finally { $env:AF_GH_TOKEN = $savedT; $env:AF_GH_API_URL = $savedU }
$all.Add($hookOut)
$j = $null; try { $j = $hookOut | ConvertFrom-Json } catch {}
$results['H_hook_carries_warning'] = ($j -and $j.hookSpecificOutput.additionalContext -match 'WARNING: GitHub token' -and $j.hookSpecificOutput.additionalContext -match 'ADO MCP readiness')
$results['H_hook_top_level_context'] = ($j -and $j.additionalContext -and $j.additionalContext -eq $j.hookSpecificOutput.additionalContext)

# I: the token value never appears in any output.
$results['I_token_never_printed'] = -not ($all | Where-Object { $_ -and $_.Contains($token) })

Stop-Process -Id $server.Id -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

Write-Host '===== AF_GH_TOKEN validity check tests ====='
$allPass = $true
foreach ($k in $results.Keys) {
    if (-not $results[$k]) { $allPass = $false }
    Write-Host ("  {0,-36} {1}" -f $k, $(if ($results[$k]) { 'PASS' } else { 'FAIL' }))
}
Write-Host '============================================'
if ($allPass) { Write-Host 'RESULT: ALL GREEN'; exit 0 }
else { Write-Host 'RESULT: FAILURES PRESENT'; exit 1 }
