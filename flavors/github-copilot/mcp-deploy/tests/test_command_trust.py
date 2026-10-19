"""Tests for the command server's approval and trust layer (#60, slice 2)."""

# copilot:generated | coordinator | 2026-10-19

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

from af_deploy_mcp import command_core as cc
from af_deploy_mcp import command_trust as ct

AGENT_DIR = ".github/scripts/agent"


def _workspace(tmp_path: Path, conf: str = "") -> Path:
    root = tmp_path / "ws"
    (root / AGENT_DIR).mkdir(parents=True)
    (root / ".github" / "af-env.conf").write_text(conf, encoding="utf-8")
    return root


def _script(root: Path, rel: str, body: str = "print('ok')\n") -> Path:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(body, encoding="utf-8")
    return p


def _git(root: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True)


def _repo(root: Path) -> None:
    _git(root, "init", "-q")
    _git(root, "config", "user.email", "t@example.com")
    _git(root, "config", "user.name", "t")


class Elicit:
    """Records each prompt and answers from a fixed script."""

    def __init__(self, answer: bool | None) -> None:
        self.answer = answer
        self.prompts: list[str] = []

    def __call__(self, message: str) -> bool | None:
        self.prompts.append(message)
        return self.answer


SCAN_CALLS: list[Path] = []


def _approver(root: Path, tmp_path: Path, elicit: Elicit | None, scan_reason: str | None = None) -> ct.Approver:
    SCAN_CALLS.clear()

    def scanner(_root: Path, script: Path) -> str | None:
        SCAN_CALLS.append(script)
        return scan_reason

    return ct.Approver(root, ct.TrustStore(ct.store_path(root, tmp_path / "store")), elicit, scanner)


def _approve(approver: ct.Approver, root: Path, rel: str) -> str | None:
    config = cc.load_config(root)
    resolved = cc.resolve_script(root, config, rel)
    return approver(resolved, cc.content_hash(resolved.path), config)


# ── trust store ────────────────────────────────────────────────────────────


def test_the_store_lives_outside_the_workspace_and_is_per_repo(tmp_path: Path) -> None:
    base = tmp_path / "store"
    a = ct.store_path(tmp_path / "a", base)
    assert a.parent == base
    assert a != ct.store_path(tmp_path / "b", base)
    assert not str(ct.store_path(tmp_path / "a")).startswith(str(tmp_path / "a"))


def test_an_accepted_hash_survives_a_new_store_instance(tmp_path: Path) -> None:
    path = tmp_path / "store" / "x.json"
    ct.TrustStore(path).add(f"{AGENT_DIR}/a.py", "abc")
    store = ct.TrustStore(path)
    assert store.is_trusted(f"{AGENT_DIR}/a.py", "abc")
    assert not store.is_trusted(f"{AGENT_DIR}/a.py", "def")


# ── mode resolution ────────────────────────────────────────────────────────


def test_a_folder_mode_overrides_the_default(tmp_path: Path) -> None:
    root = _workspace(tmp_path, f"AF_SCRIPT_DIRS={AGENT_DIR},scripts/fast:autonomous\n")
    _script(root, "scripts/fast/a.py")
    _script(root, f"{AGENT_DIR}/b.py")
    config = cc.load_config(root)
    assert ct.effective_mode(root, cc.resolve_script(root, config, "scripts/fast/a.py"), config) == "autonomous"
    assert ct.effective_mode(root, cc.resolve_script(root, config, f"{AGENT_DIR}/b.py"), config) == "ask"


def test_reviewed_holds_only_for_a_committed_unchanged_script(tmp_path: Path) -> None:
    root = _workspace(tmp_path, "AF_SCRIPT_APPROVAL=ask-always\n")
    _repo(root)
    _script(root, ".github/scripts/clean.py")
    _script(root, ".github/scripts/dirty.py")
    _git(root, "add", "-A")
    _git(root, "commit", "-q", "-m", "init")
    _script(root, ".github/scripts/dirty.py", "print('edited')\n")
    _script(root, ".github/scripts/new.py")
    config = cc.load_config(root)

    def mode(rel: str) -> str:
        return ct.effective_mode(root, cc.resolve_script(root, config, rel), config)

    assert mode(".github/scripts/clean.py") == "reviewed"
    assert mode(".github/scripts/dirty.py") == "ask-always"
    assert mode(".github/scripts/new.py") == "ask-always"


def test_reviewed_falls_back_outside_a_git_repo(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    _script(root, ".github/scripts/a.py")
    config = cc.load_config(root)
    assert ct.effective_mode(root, cc.resolve_script(root, config, ".github/scripts/a.py"), config) == "ask"


# ── approval matrix ────────────────────────────────────────────────────────


def test_off_refuses(tmp_path: Path) -> None:
    root = _workspace(tmp_path, "AF_SCRIPT_APPROVAL=off\n")
    _script(root, f"{AGENT_DIR}/a.py")
    assert "off" in _approve(_approver(root, tmp_path, Elicit(True)), root, f"{AGENT_DIR}/a.py")


def test_autonomous_runs_without_asking(tmp_path: Path) -> None:
    root = _workspace(tmp_path, "AF_SCRIPT_APPROVAL=autonomous\n")
    _script(root, f"{AGENT_DIR}/a.py")
    elicit = Elicit(False)
    assert _approve(_approver(root, tmp_path, elicit), root, f"{AGENT_DIR}/a.py") is None
    assert elicit.prompts == []


def test_ask_asks_once_per_content_and_again_after_an_edit(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    script = _script(root, f"{AGENT_DIR}/a.py")
    elicit = Elicit(True)
    approver = _approver(root, tmp_path, elicit)
    assert _approve(approver, root, f"{AGENT_DIR}/a.py") is None
    assert _approve(approver, root, f"{AGENT_DIR}/a.py") is None
    assert len(elicit.prompts) == 1
    assert f"{AGENT_DIR}/a.py" in elicit.prompts[0]
    script.write_text("print('changed')\n", encoding="utf-8")
    assert _approve(approver, root, f"{AGENT_DIR}/a.py") is None
    assert len(elicit.prompts) == 2


def test_ask_refuses_when_the_user_declines(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    _script(root, f"{AGENT_DIR}/a.py")
    approver = _approver(root, tmp_path, Elicit(False))
    assert "declined" in _approve(approver, root, f"{AGENT_DIR}/a.py")
    assert "declined" in _approve(approver, root, f"{AGENT_DIR}/a.py")


@pytest.mark.parametrize("elicit", [None, Elicit(None)], ids=["no-capability", "elicitation-failed"])
def test_ask_fails_closed_without_elicitation(tmp_path: Path, elicit: Elicit | None) -> None:
    root = _workspace(tmp_path)
    _script(root, f"{AGENT_DIR}/a.py")
    reason = _approve(_approver(root, tmp_path, elicit), root, f"{AGENT_DIR}/a.py")
    assert reason is not None
    assert "elicitation" in reason


def test_ask_always_asks_every_time(tmp_path: Path) -> None:
    root = _workspace(tmp_path, "AF_SCRIPT_APPROVAL=ask-always\n")
    _script(root, f"{AGENT_DIR}/a.py")
    elicit = Elicit(True)
    approver = _approver(root, tmp_path, elicit)
    _approve(approver, root, f"{AGENT_DIR}/a.py")
    _approve(approver, root, f"{AGENT_DIR}/a.py")
    assert len(elicit.prompts) == 2


def test_a_content_scan_deny_refuses_even_in_autonomous(tmp_path: Path) -> None:
    root = _workspace(tmp_path, "AF_SCRIPT_APPROVAL=autonomous\n")
    _script(root, f"{AGENT_DIR}/a.py")
    reason = _approve(_approver(root, tmp_path, None, scan_reason="force push"), root, f"{AGENT_DIR}/a.py")
    assert reason is not None
    assert "force push" in reason


def test_the_scan_runs_once_per_content(tmp_path: Path) -> None:
    root = _workspace(tmp_path, "AF_SCRIPT_APPROVAL=autonomous\n")
    _script(root, f"{AGENT_DIR}/a.py")
    approver = _approver(root, tmp_path, None)
    _approve(approver, root, f"{AGENT_DIR}/a.py")
    _approve(approver, root, f"{AGENT_DIR}/a.py")
    assert len(SCAN_CALLS) == 1


def test_a_reviewed_script_is_neither_scanned_nor_asked(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    _repo(root)
    _script(root, ".github/scripts/suite.py")
    _git(root, "add", "-A")
    _git(root, "commit", "-q", "-m", "init")
    elicit = Elicit(False)
    approver = _approver(root, tmp_path, elicit, scan_reason="would deny")
    assert _approve(approver, root, ".github/scripts/suite.py") is None
    assert elicit.prompts == []
    assert SCAN_CALLS == []


# ── the real hook ──────────────────────────────────────────────────────────


def _fixture_hook(root: Path) -> None:
    hooks = root / ".github" / "hooks" / "scripts"
    hooks.mkdir(parents=True)
    deny = (
        '{"hookSpecificOutput":{"hookEventName":"PreToolUse",'
        '"permissionDecision":"deny","permissionDecisionReason":"nope"}}'
    )
    (hooks / "block-dangerous.ps1").write_text(
        "$raw = [Console]::In.ReadToEnd()\n"
        f"if ($raw -match 'FORBIDDEN' -and $raw -match 'run_in_terminal') {{ '{deny}' }} else {{ '{{}}' }}\n",
        encoding="utf-8",
    )
    (hooks / "block-dangerous.sh").write_text(
        "#!/usr/bin/env bash\nraw=$(cat)\n"
        f"if [[ $raw == *FORBIDDEN* && $raw == *run_in_terminal* ]]; then echo '{deny}'; else echo '{{}}'; fi\n",
        encoding="utf-8",
    )


def test_the_hook_scan_denies_what_block_dangerous_denies(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    _fixture_hook(root)
    bad = _script(root, f"{AGENT_DIR}/bad.py", "print('FORBIDDEN')\n")
    good = _script(root, f"{AGENT_DIR}/good.py")
    assert "nope" in ct.hook_scan(root, bad)
    assert ct.hook_scan(root, good) is None


def test_a_missing_hook_fails_closed(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    script = _script(root, f"{AGENT_DIR}/a.py")
    reason = ct.hook_scan(root, script)
    assert reason is not None
    assert "content scan unavailable" in reason


# ── wired into run_script ──────────────────────────────────────────────────


def test_a_refusal_runs_nothing_and_is_logged(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    marker = tmp_path / "ran"
    _script(root, f"{AGENT_DIR}/a.py", f"open(r'{marker}', 'w').close()\n")
    result = cc.run_script(root, f"{AGENT_DIR}/a.py", [], approve=_approver(root, tmp_path, Elicit(False)))
    assert result["verdict"] == "REFUSED"
    assert "declined" in result["reason"]
    assert not marker.exists()
    log = (root / ".github" / "logs" / "command-runs.jsonl").read_text(encoding="utf-8")
    assert '"REFUSED"' in log


@pytest.mark.skipif(sys.platform != "win32", reason="LOCALAPPDATA layout")
def test_the_default_store_is_under_localappdata(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("LOCALAPPDATA", str(tmp_path / "lad"))
    assert ct.default_store_base() == tmp_path / "lad" / "af-command-mcp" / "trust"
