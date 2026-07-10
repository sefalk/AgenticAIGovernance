"""Tests for the MCP tool/prompt wrappers in ``server.py``.

These exercise the thin FastMCP wrappers directly (FastMCP returns the original
function), covering the ``confirm`` guards, error paths, and payload resolution
via ``AF_SOURCE_ROOT``. Skipped cleanly if the ``mcp`` package is unavailable.
"""

# copilot:generated | test-writer | 2026-07-10

from __future__ import annotations

from pathlib import Path

import pytest

pytest.importorskip("mcp")

from af_deploy_mcp import server  # noqa: E402


def _write(p: Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8", newline="")


def _make_source(root: Path, version: str = "1.0.0") -> Path:
    """Build a minimal but valid framework payload."""
    _write(root / "VERSION", version + "\n")
    gh = root / ".github"
    _write(gh / ".af-manifest", "instructions/\naf-env.conf   [customizable]\n")
    _write(gh / "instructions" / "x.instructions.md", "# x\n")
    _write(gh / "af-env.conf", "SRC_DIR=src\n")
    return root


@pytest.fixture
def payload(tmp_path: Path, monkeypatch) -> Path:
    src = _make_source(tmp_path / "src")
    monkeypatch.setenv("AF_SOURCE_ROOT", str(src))
    return src


def test_status_not_deployed(payload: Path, tmp_path: Path) -> None:
    target = tmp_path / "proj"
    target.mkdir()
    result = server.status(str(target))
    assert result["state"] == "not-deployed"
    assert result["source_version"] == "1.0.0"


def test_status_invalid_target(payload: Path, tmp_path: Path) -> None:
    result = server.status(str(tmp_path / "does-not-exist"))
    assert "error" in result


def test_invalid_source_reported(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("AF_SOURCE_ROOT", str(tmp_path / "empty"))
    (tmp_path / "empty").mkdir()
    target = tmp_path / "proj"
    target.mkdir()
    result = server.status(str(target))
    assert "error" in result and "VERSION" in result["error"]


def test_dry_run_wrapper(payload: Path, tmp_path: Path) -> None:
    target = tmp_path / "proj"
    target.mkdir()
    result = server.dry_run(str(target))
    assert result["counts"].get("CREATE", 0) >= 1
    assert result["workspace_root"] == str(target)


def test_apply_guard_then_writes(payload: Path, tmp_path: Path) -> None:
    target = tmp_path / "proj"
    target.mkdir()
    guard = server.apply(str(target), confirm=False)
    assert guard["confirmation_required"] is True
    applied = server.apply(str(target), confirm=True)
    assert applied["applied_count"] >= 1
    assert (target / ".github" / "instructions" / "x.instructions.md").is_file()
    # Idempotent: a second dry-run has nothing to create/update.
    counts = server.dry_run(str(target))["counts"]
    assert "CREATE" not in counts and "UPDATE" not in counts


def test_write_resolved_guard_and_write(payload: Path, tmp_path: Path) -> None:
    target = tmp_path / "proj"
    (target / ".github").mkdir(parents=True)
    guard = server.write_resolved(str(target), "instructions/merged.md", "# merged\n", confirm=False)
    assert guard["confirmation_required"] is True
    out = server.write_resolved(str(target), "instructions/merged.md", "# merged\n", confirm=True)
    assert out["path"] == ".github/instructions/merged.md"
    assert (target / ".github" / "instructions" / "merged.md").read_text(encoding="utf-8") == "# merged\n"


def test_write_resolved_refuses_traversal(payload: Path, tmp_path: Path) -> None:
    target = tmp_path / "proj"
    (target / ".github").mkdir(parents=True)
    result = server.write_resolved(str(target), "../../evil.txt", "x", confirm=True)
    assert "error" in result


def test_conflict_diff_wrapper(payload: Path, tmp_path: Path) -> None:
    target = tmp_path / "proj"
    target.mkdir()
    server.apply(str(target), confirm=True)
    # Change the deployed file so a diff exists.
    _write(target / ".github" / "instructions" / "x.instructions.md", "# x CHANGED\n")
    result = server.conflict_diff(str(target), "instructions/x.instructions.md")
    assert "x CHANGED" in result["diff"]


def test_update_hashes_and_prune_guards(payload: Path, tmp_path: Path) -> None:
    target = tmp_path / "proj"
    target.mkdir()
    server.apply(str(target), confirm=True)
    assert server.update_hashes(str(target), confirm=False)["confirmation_required"] is True
    assert server.update_hashes(str(target), confirm=True)["entries"] >= 1
    assert server.prune_backups(str(target), confirm=False)["confirmation_required"] is True
    assert "removed" in server.prune_backups(str(target), days=14, confirm=True)


def test_prompt_wrappers_return_guidance(payload: Path) -> None:
    deploy_text = server.deploy("/proj")
    assert "af_status" not in deploy_text  # tool names are unprefixed now
    assert "curated-assignments.json" in deploy_text
    resolve_text = server.resolve_conflicts("/proj")
    assert "conflict_diff" in resolve_text and "update_hashes" in resolve_text


def test_orphan_wrappers(payload: Path, tmp_path: Path) -> None:
    target = tmp_path / "proj"
    target.mkdir()
    server.apply(str(target), confirm=True)
    orphan = target / ".github" / "instructions" / "old.instructions.md"
    orphan.parent.mkdir(parents=True, exist_ok=True)
    orphan.write_text("# old\n", encoding="utf-8")
    hf = target / ".github" / ".af-hashes"
    hf.write_text(hf.read_text(encoding="utf-8") + "instructions/old.instructions.md=DEADBEEF\n", encoding="utf-8")

    listed = server.list_orphans(str(target))
    assert listed["count"] >= 1

    guard = server.prune_orphans(str(target), confirm=False)
    assert guard["confirmation_required"] is True

    done = server.prune_orphans(str(target), confirm=True)
    assert ".github/instructions/old.instructions.md" in done["removed"]
    assert not orphan.exists()
