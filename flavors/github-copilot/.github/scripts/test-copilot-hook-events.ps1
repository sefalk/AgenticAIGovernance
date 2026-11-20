# Copilot session evidence: selection, lifecycle integrity and privacy (#553).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_suite_env.ps1')
$python = Get-AfSuitePython
if (-not $python) { throw 'Python 3 is required; no tests were executed.' }
$subject = Join-Path $PSScriptRoot 'check-copilot-hook-events.py'
if (-not (Test-Path -LiteralPath $subject)) {
    Write-Output 'FAIL  Copilot evidence reader is missing (#553 Red).'
    exit 1
}

$probe = @'
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

subject = sys.argv.pop()
shell = sys.argv.pop()


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="af553-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        self.sessions = self.root / "sessions"
        self.sessions.mkdir()
        self.marker = "PRIVATE-CONTENT-MUST-NOT-BE-PRINTED"
        self.events = [self.event("session.start", {
            "sessionId": "session-a", "context": {"cwd": str(self.workspace)}
        }, 0)]
        for i, kind in enumerate(("sessionStart", "preToolUse", "postToolUse")):
            self.events.extend([
                self.event("hook.start", {
                    "hookInvocationId": f"inv-{i}", "hookType": kind,
                    "input": {"private": self.marker, "cwd": str(self.workspace)}
                }, 1 + i * 2),
                self.event("hook.end", {
                    "hookInvocationId": f"inv-{i}", "hookType": kind, "success": True
                }, 2 + i * 2)
            ])

    def event(self, kind, data, second):
        return {"type": kind, "timestamp": f"2026-11-20T10:00:{second:02d}Z", "data": data}

    def write(self, name="session-a", events=None):
        folder = self.sessions / name
        folder.mkdir(exist_ok=True)
        path = folder / "events.jsonl"
        rows = self.events if events is None else events
        path.write_text("".join(json.dumps(e) + "\n" for e in rows), encoding="utf-8")
        return path

    def invoke(self, expected, *args, workspace=None):
        result = subprocess.run([
            sys.executable, subject, "--workspace", str(workspace or self.workspace),
            "--session-state-root", str(self.sessions), *args
        ], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        self.assertNotIn(self.marker, result.stdout + result.stderr)
        self.assertNotIn(str(self.workspace), result.stdout + result.stderr)
        self.assertNotIn(str(self.root), result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")
        output = json.loads(result.stdout)
        self.assertEqual(output["status"], {0: "pass", 1: "fail", 2: "inconclusive"}[expected])
        return output

    def test_complete_lifecycle_counts_durations_and_ask_requests(self):
        self.events.extend([
            self.event("hook.start", {
                "hookInvocationId": "extra-pre", "hookType": "preToolUse", "input": {}}, 7),
            self.event("hook.end", {
                "hookInvocationId": "extra-pre", "hookType": "preToolUse", "success": True}, 10),
            self.event("permission.requested", {
                "permissionRequest": {"kind": "hook", "reason": self.marker}}, 11),
            self.event("permission.requested", {
                "permissionRequest": {"kind": self.marker, "command": self.marker}}, 12),
            self.event("tool.execution_complete", {"result": self.marker}, 13)
        ])
        self.write()
        output = self.invoke(0)
        self.assertEqual(output["session_id"], "session-a")
        self.assertEqual(output["ask_requests"], 1)
        self.assertEqual(output["failure_count"], 0)
        self.assertEqual(output["hooks"]["preToolUse"], {
            "started": 2, "completed": 2, "failed": 0,
            "duration_ms": {"total": 4000.0, "max": 3000.0}
        })
        self.assertEqual(output["limits"]["verdicts"], "not_observable")
        self.assertEqual(output["limits"]["script_identity"], "not_observable")
        self.assertEqual(output["limits"]["timeouts"], "not_observable")

    def test_foreign_newest_file_cannot_attest_this_workspace(self):
        good = self.write()
        foreign = copy.deepcopy(self.events)
        foreign[0]["data"]["context"]["cwd"] = str(self.root / "foreign")
        bad = self.write("session-b", foreign)
        os.utime(good, (100, 100))
        os.utime(bad, (200, 200))
        self.assertEqual(self.invoke(0)["session_id"], "session-a")
        good.unlink()
        self.invoke(2)
        self.invoke(2, "--session-id", "session-b")

    def test_ambiguity_requires_explicit_session_and_checks_its_identity(self):
        self.write()
        other = copy.deepcopy(self.events)
        other[0]["data"]["sessionId"] = "session-b"
        self.write("session-b", other)
        self.invoke(2)
        self.invoke(0, "--session-id", "session-a")
        other[0]["data"]["sessionId"] = "wrong-session"
        self.write("session-b", other)
        self.invoke(2, "--session-id", "session-b")

    def test_missing_and_traversal_ids_never_fall_back(self):
        self.write()
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "events.jsonl").write_text(
            "".join(json.dumps(e) + "\n" for e in self.events), encoding="utf-8")
        nested = self.sessions / "nested"
        nested.mkdir()
        (nested / "child").mkdir()
        (nested / "child" / "events.jsonl").write_text(
            (outside / "events.jsonl").read_text(encoding="utf-8"), encoding="utf-8")
        for value in ("absent", "..", "../outside", r"..\outside", str(outside), "nested/child",
                      r"nested\child", self.marker + "/../session-a"):
            with self.subTest(value=value):
                self.invoke(2, "--session-id", value)

    def test_workspace_comparison_is_exact_but_accepts_trailing_separator(self):
        for cwd in (str(self.workspace) + "-evil", str(self.workspace / "child"), str(self.root)):
            with self.subTest(cwd=cwd):
                rows = copy.deepcopy(self.events)
                rows[0]["data"]["context"]["cwd"] = cwd
                self.write(events=rows)
                self.invoke(2)
        rows[0]["data"]["context"]["cwd"] = str(self.workspace) + os.sep
        self.write(events=rows)
        self.invoke(0)

    def test_fractional_offset_and_zero_durations(self):
        self.events[1]["timestamp"] = "2026-11-20T10:00:01.123000+00:00"
        self.events[2]["timestamp"] = "2026-11-20T10:00:01.123500Z"
        self.events[4]["timestamp"] = self.events[3]["timestamp"]
        self.write()
        output = self.invoke(0)
        self.assertEqual(output["hooks"]["sessionStart"]["duration_ms"]["total"], 0.5)
        self.assertEqual(output["hooks"]["preToolUse"]["duration_ms"]["total"], 0)

    def test_observed_false_fails_but_string_false_is_invalid(self):
        self.events[2]["data"]["success"] = False
        self.write()
        result = self.invoke(1)
        self.assertEqual(result["failure_count"], 1)
        self.assertEqual(result["hooks"]["sessionStart"]["failed"], 1)
        self.events[2]["data"]["success"] = "false"
        self.write()
        self.invoke(2)

    def test_incomplete_duplicate_and_mismatched_invocations_do_not_pass(self):
        cases = {
            "unmatched_start": self.events[:-1],
            "unmatched_end": self.events[:1] + self.events[2:],
            "duplicate_start": self.events + [self.events[1]],
            "duplicate_end": self.events + [self.events[2]],
        }
        for label, rows in cases.items():
            with self.subTest(case=label):
                self.write(events=rows)
                self.invoke(2)
        rows = copy.deepcopy(self.events)
        rows[2]["data"]["hookType"] = "preToolUse"
        self.write(events=rows)
        self.invoke(2)
        rows = copy.deepcopy(self.events)
        del rows[2]["data"]["hookInvocationId"]
        self.write(events=rows)
        self.invoke(2)

    def test_bad_timestamps_and_negative_duration_do_not_pass(self):
        for value in (None, "not-a-time", "2026-11-20T10:00:00", "2026-11-20T09:00:00Z"):
            with self.subTest(value=value):
                rows = copy.deepcopy(self.events)
                rows[2]["timestamp"] = value
                self.write(events=rows)
                self.invoke(2)

    def test_zero_hooks_missing_required_lifecycle_and_missing_session_start(self):
        cases = [self.events[:1], self.events[1:]]
        for kind in ("sessionStart", "preToolUse", "postToolUse"):
            cases.append([e for e in self.events if e["data"].get("hookType") != kind])
        for rows in cases:
            with self.subTest(size=len(rows)):
                self.write(events=rows)
                self.invoke(2)

    def test_malformed_truncated_and_non_object_records_are_explicit_non_passes(self):
        deep = '{"type":"tool.execution_complete","data":' + "[" * 10000 + "0\n"
        for index, suffix in enumerate(('{"type":', "[]\n", '{"type":"hook.start","data":null}\n', deep)):
            with self.subTest(case=index):
                path = self.write()
                with path.open("a", encoding="utf-8") as handle:
                    handle.write(suffix)
                self.invoke(2)

    def test_duplicate_session_header_and_unknown_hook_type_cannot_forge_lifecycle(self):
        self.write(events=self.events + [self.events[0]])
        self.invoke(2)
        rows = copy.deepcopy(self.events)
        rows[1]["data"]["hookType"] = self.marker
        rows[2]["data"]["hookType"] = self.marker
        self.write(events=rows)
        self.invoke(2)

    def test_missing_root_and_invalid_utf8_do_not_leak_paths(self):
        self.invoke(2)
        path = self.write()
        with path.open("ab") as handle:
            handle.write(b"\xff")
        self.invoke(2)
        self.sessions.rename(self.root / "moved")
        self.invoke(2)

    def test_invalid_recorded_path_is_inconclusive_and_does_not_poison_discovery(self):
        broken = copy.deepcopy(self.events)
        broken[0]["data"]["sessionId"] = "broken"
        broken[0]["data"]["context"]["cwd"] = str(self.workspace) + os.sep + "\0" + self.marker
        self.write("broken", broken)
        self.invoke(2, "--session-id", "broken")
        self.write()
        self.assertEqual(self.invoke(0)["session_id"], "session-a")

    def test_missing_arguments_return_private_json_not_usage_or_traceback(self):
        result = subprocess.run([sys.executable, subject], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stdout)["status"], "inconclusive")
        self.assertEqual(result.stderr, "")

    def test_powershell_wrapper_preserves_selection_and_exit_codes(self):
        self.write()
        wrapper = Path(subject).with_name("test-hooks-integration.ps1")
        for workspace, expected in ((self.workspace, 0), (self.root / "foreign", 2)):
            with self.subTest(expected=expected):
                result = subprocess.run([
                    shell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                    "-File", str(wrapper), "-Workspace", str(workspace),
                    "-SessionStateRoot", str(self.sessions), "-SessionId", "session-a"
                ], capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                self.assertEqual(json.loads(result.stdout)["status"],
                                 "pass" if expected == 0 else "inconclusive")
                self.assertEqual(result.stderr, "")


unittest.main(testRunner=unittest.TextTestRunner(stream=sys.stdout, verbosity=2))
'@

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('af553-tests-' + [guid]::NewGuid().ToString('N') + '.py')
try {
    [IO.File]::WriteAllText($fixture, $probe)
    $ErrorActionPreference = 'Continue'
    $hostExecutable = (Get-Process -Id $PID).Path
    $output = & $python $fixture $hostExecutable $subject 2>&1 | Out-String
    $code = $LASTEXITCODE
    Write-Output $output
} finally {
    Remove-Item -LiteralPath $fixture -ErrorAction SilentlyContinue
}
if ($code -ne 0) { exit 1 }
Write-Output 'PASS  Copilot evidence fixture scenarios'
exit 0
