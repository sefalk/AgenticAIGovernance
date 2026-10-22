"""Tests for the command server's MCP tools (#60, slice 3)."""

# copilot:generated | coordinator | 2026-10-19

from __future__ import annotations

from pathlib import Path

import anyio
import pytest
import tomllib

pytest.importorskip("mcp")

from mcp.server.elicitation import AcceptedElicitation, DeclinedElicitation  # noqa: E402
from mcp.types import ClientCapabilities, ElicitationCapability  # noqa: E402

from af_deploy_mcp import command_server as cs  # noqa: E402

AGENT_DIR = ".github/scripts/agent"
MCP_DEPLOY = Path(__file__).resolve().parents[1]
ALLOW_HOOK_PS1 = "$null = [Console]::In.ReadToEnd()\n'{}'\n"
ALLOW_HOOK_SH = "#!/usr/bin/env bash\ncat >/dev/null\necho '{}'\n"


class FakeCtx:
    """The slice of ``Context`` the tools use: capabilities, elicit, report_progress."""

    def __init__(self, answer: bool | None = True, elicitation: bool = True) -> None:
        self.client_capabilities = ClientCapabilities(elicitation=ElicitationCapability() if elicitation else None)
        self.answer = answer
        self.prompts: list[str] = []
        self.progress: list[tuple[float, str | None]] = []

    async def elicit(self, message: str, schema: type):
        self.prompts.append(message)
        if self.answer is None:
            raise RuntimeError("client went away")
        if not self.answer:
            return DeclinedElicitation()
        return AcceptedElicitation(data=schema(approve=True))

    async def report_progress(self, progress: float, total: float | None = None, message: str | None = None) -> None:
        self.progress.append((progress, message))


@pytest.fixture
def ws(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    root = tmp_path / "ws"
    (root / AGENT_DIR).mkdir(parents=True)
    hooks = root / ".github" / "hooks" / "scripts"
    hooks.mkdir(parents=True)
    (hooks / "block-dangerous.ps1").write_text(ALLOW_HOOK_PS1, encoding="utf-8")
    (hooks / "block-dangerous.sh").write_text(ALLOW_HOOK_SH, encoding="utf-8")
    monkeypatch.setenv("AF_COMMAND_TRUST_DIR", str(tmp_path / "trust"))
    return root


def _conf(root: Path, text: str) -> None:
    (root / ".github" / "af-env.conf").write_text(text, encoding="utf-8")


def _script(root: Path, rel: str, body: str = "print('ok')\n") -> None:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(body, encoding="utf-8")


def _call(fn, *args, **kwargs):
    return anyio.run(lambda: fn(*args, **kwargs))


RESULT_KEYS = {"verdict", "exit_code", "duration_s", "walltime_s", "walltime_source", "tail", "log_path", "reason"}


def test_run_script_returns_the_documented_shape(ws: Path) -> None:
    _conf(ws, "AF_SCRIPT_APPROVAL=autonomous\n")
    _script(ws, f"{AGENT_DIR}/ok.py", "import sys\nprint('args', *sys.argv[1:])\n")
    result = _call(cs.run_script, str(ws), f"{AGENT_DIR}/ok.py", ["x", "y z"], None, FakeCtx())
    assert set(result) == RESULT_KEYS
    assert result["verdict"] == "PASS"
    assert "args x y z" in result["tail"]


def test_ask_elicits_once_then_runs_freely(ws: Path) -> None:
    _script(ws, f"{AGENT_DIR}/ok.py")
    ctx = FakeCtx(answer=True)
    first = _call(cs.run_script, str(ws), f"{AGENT_DIR}/ok.py", [], None, ctx)
    second = _call(cs.run_script, str(ws), f"{AGENT_DIR}/ok.py", ["other"], None, ctx)
    assert (first["verdict"], second["verdict"]) == ("PASS", "PASS")
    assert len(ctx.prompts) == 1


@pytest.mark.parametrize(
    ("ctx", "reason"),
    [
        (FakeCtx(elicitation=False), "elicitation"),
        (FakeCtx(answer=None), "elicitation failed"),
        (FakeCtx(answer=False), "declined"),
    ],
    ids=["no-capability", "elicit-raises", "declined"],
)
def test_ask_refuses_without_a_yes(ws: Path, ctx: FakeCtx, reason: str) -> None:
    _script(ws, f"{AGENT_DIR}/ok.py")
    result = _call(cs.run_script, str(ws), f"{AGENT_DIR}/ok.py", [], None, ctx)
    assert result["verdict"] == "REFUSED"
    assert reason in result["reason"]


def test_long_runs_report_progress(ws: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(cs, "PROGRESS_TICK_S", 0.3)
    _conf(ws, "AF_SCRIPT_APPROVAL=autonomous\n")
    _script(ws, f"{AGENT_DIR}/slow.py", "import time\nprint('working', flush=True)\ntime.sleep(1.5)\n")
    ctx = FakeCtx()
    assert _call(cs.run_script, str(ws), f"{AGENT_DIR}/slow.py", [], None, ctx)["verdict"] == "PASS"
    assert ctx.progress
    assert any(msg and "working" in msg for _, msg in ctx.progress)


def test_an_explicit_walltime_is_honoured(ws: Path) -> None:
    _conf(ws, "AF_SCRIPT_APPROVAL=autonomous\n")
    _script(ws, f"{AGENT_DIR}/hang.py", "import time\ntime.sleep(30)\n")
    result = _call(cs.run_script, str(ws), f"{AGENT_DIR}/hang.py", [], 2, FakeCtx())
    assert (result["verdict"], result["walltime_s"], result["walltime_source"]) == ("TIMEOUT", 2, "explicit")


def test_a_missing_workspace_is_an_error_not_a_crash(tmp_path: Path) -> None:
    result = _call(cs.run_script, str(tmp_path / "nope"), "x.py", [], None, FakeCtx())
    assert result["verdict"] == "REFUSED"
    assert "not a directory" in result["reason"]


def test_list_scripts_groups_scripts_by_folder_and_mode(ws: Path) -> None:
    _conf(ws, f"AF_SCRIPT_DIRS={AGENT_DIR},tools:autonomous\n")
    _script(ws, f"{AGENT_DIR}/a.py")
    _script(ws, f"{AGENT_DIR}/README.md", "# not a script\n")
    _script(ws, "tools/b.ps1", "")
    _script(ws, ".github/scripts/c.py")
    listing = cs.list_scripts(str(ws))
    folders = {f["folder"]: f for f in listing["folders"]}
    assert folders[AGENT_DIR]["mode"] == "ask"
    assert folders["tools"]["mode"] == "autonomous"
    assert folders[".github/scripts"]["mode"] == "reviewed"
    assert [s["path"] for s in folders[AGENT_DIR]["scripts"]] == [f"{AGENT_DIR}/a.py"]
    assert [s["path"] for s in folders[".github/scripts"]["scripts"]] == [".github/scripts/c.py"]
    assert folders["tools"]["scripts"][0]["default_walltime_s"] == 600


def test_list_scripts_publishes_the_header_schema(ws: Path) -> None:
    _script(ws, f"{AGENT_DIR}/lint.py", "# af-command: Lint files.\n# af-arg: FILE...  Files\n# af-arg: [--fix]  Fix\n")
    _script(ws, f"{AGENT_DIR}/bad.py", "# af-arg: FILE\n")
    _script(ws, f"{AGENT_DIR}/plain.py")
    scripts = {s["path"]: s for s in cs.list_scripts(str(ws))["folders"][0]["scripts"]}
    lint = scripts[f"{AGENT_DIR}/lint.py"]
    assert lint["description"] == "Lint files."
    assert lint["usage"] == "FILE... [--fix]"
    assert [a["name"] for a in lint["args"]] == ["FILE", "--fix"]
    assert "help" in scripts[f"{AGENT_DIR}/bad.py"]["header_error"]
    assert "usage" not in scripts[f"{AGENT_DIR}/plain.py"]


def test_only_list_scripts_claims_to_be_read_only() -> None:
    tools = {t.name: t for t in anyio.run(cs.mcp.list_tools)}
    assert set(tools) == {"run_script", "list_scripts"}
    assert tools["list_scripts"].annotations.read_only_hint is True
    run = tools["run_script"].annotations
    assert run is None or not run.read_only_hint


def test_a_trust_dir_inside_the_workspace_is_ignored(ws: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("AF_COMMAND_TRUST_DIR", str(ws / ".github" / "trust"))
    assert cs._trust_base(ws.resolve()) is None
    monkeypatch.setenv("AF_COMMAND_TRUST_DIR", str(tmp_path / "elsewhere"))
    assert cs._trust_base(ws.resolve()) == (tmp_path / "elsewhere").resolve()


def test_the_console_script_is_declared() -> None:
    scripts = tomllib.loads((MCP_DEPLOY / "pyproject.toml").read_text(encoding="utf-8"))["project"]["scripts"]
    assert scripts["af-command-mcp"] == "af_deploy_mcp.command_server:main"
    assert callable(cs.main)
