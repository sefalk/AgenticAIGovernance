"""pytest plugin: write `.github/test-log.json` for every pytest invocation (#180).

The log is the cross-agent record of test runs and carries the per-workflow
budget. Only `run-tests.ps1/.sh` wrote it, so a run through the VS Code
`runTests` tool, Test Explorer or a bare `pytest` left no entry -- and a missing
entry reads exactly like "never run". Loaded from the project's
`pyproject.toml`, this plugin makes logging a property of pytest itself:

    [tool.pytest.ini_options]
    pythonpath = [".github/scripts"]
    addopts = "-p af_test_log"

Entry shape and keys match the wrappers. A run of `tests` (or no arguments with
`testpaths = ["tests"]`) is `all`, a run of `tests/<scope>` is that scope, and
anything narrower -- a file, a node id, several paths, `-k` or `-m` -- is
`partial`, never a scope (#303). The entry is claimed as `running` before the
first test, so an interrupted run never leaves yesterday's green standing (#179).

The wrappers write their own entry and set `AF_TEST_LOG_BY_WRAPPER=1`, which
switches this plugin off for their runs: they also record the failures that
happen before pytest ever starts, which no plugin can see.
"""

# copilot:generated | coordinator | 2026-10-20

from __future__ import annotations

import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

import pytest

SCOPES = ("domain", "adapters", "properties", "contracts")
RUN_BY = "pytest-plugin"


def _now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat()


class _TestLog:
    def __init__(self, config: pytest.Config) -> None:
        self.path = Path(config.rootpath) / ".github" / "test-log.json"
        self.key, self.target, self.selector = self._classify(config)
        self.started = _now()
        self.t0 = time.monotonic()
        self.counts = {"passed": 0, "failed": 0, "errors": 0}

    @staticmethod
    def _classify(config: pytest.Config) -> tuple[str, str, str | None]:
        root = Path(config.rootpath)
        args = [a for a in config.args if a]
        if not args or [str(Path(a)) for a in args] == [str(root)]:
            args = list(config.getini("testpaths")) or ["."]
        rel = []
        for a in args:
            p = Path(a) if Path(a).is_absolute() else root / a
            try:
                rel.append(p.resolve().relative_to(root.resolve()).as_posix())
            except ValueError:
                rel.append(a)
        selector = config.getoption("keyword") or config.getoption("markexpr") or None
        target = " ".join(rel)
        if selector or len(rel) != 1:
            return "partial", target, selector
        if rel[0] == "tests":
            return "all", target, None
        for scope in SCOPES:
            if rel[0] == f"tests/{scope}":
                return scope, target, None
        return "partial", target, None

    def _write(self, entry: dict) -> None:
        log: dict = {}
        if self.path.is_file():
            try:
                log = json.loads(self.path.read_text(encoding="utf-8-sig"))
            except (OSError, ValueError):
                # An unreadable log is evidence; keep it rather than overwrite it.
                self.path.with_suffix(".json.unreadable").write_bytes(self.path.read_bytes())
                log = {}
        log[self.key] = entry
        self.path.write_text(json.dumps(log, indent=2) + "\n", encoding="utf-8")

    def entry(self, status: str, exit_code: int | None) -> dict:
        done = status != "running"
        return {
            "last_run": _now(),
            "started": self.started,
            "passed": self.counts["passed"] if done else None,
            "failed": self.counts["failed"] if done else None,
            "errors": self.counts["errors"] if done else None,
            "total": sum(self.counts.values()) if done else None,
            "runtime_seconds": round(time.monotonic() - self.t0, 2) if done else None,
            "run_by": RUN_BY,
            "exit_code": exit_code,
            "coverage_percent": None,
            "status": status,
            "partial": self.key == "partial",
            "target": self.target,
            "selector": self.selector,
        }

    def pytest_runtest_logreport(self, report: pytest.TestReport) -> None:
        if report.when == "call":
            if report.passed:
                self.counts["passed"] += 1
            elif report.failed:
                self.counts["failed"] += 1
        elif report.failed:
            self.counts["errors"] += 1

    def pytest_collectreport(self, report: pytest.CollectReport) -> None:
        if report.failed:
            self.counts["errors"] += 1

    def pytest_sessionfinish(self, session: pytest.Session, exitstatus: int) -> None:
        self._write(self.entry("ok", int(exitstatus)))


def pytest_configure(config: pytest.Config) -> None:
    if os.environ.get("AF_TEST_LOG_BY_WRAPPER") == "1" or hasattr(config, "workerinput"):
        return
    if not (Path(config.rootpath) / ".github").is_dir():
        return
    log = _TestLog(config)
    log._write(log.entry("running", None))
    config.pluginmanager.register(log, "af_test_log_writer")
