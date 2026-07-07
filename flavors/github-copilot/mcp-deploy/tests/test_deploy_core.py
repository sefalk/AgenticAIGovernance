"""Tests for deploy_core — the read-only AAIG deploy logic behind the MCP PoC."""

# copilot:generated | test-writer | 2026-07-07

from __future__ import annotations

from pathlib import Path

from aaig_deploy_mcp import deploy_core

MANIFEST = """\
# manifest
agents/
instructions/
af-env.conf   [customizable]
MANIFEST.md
.af-version   [optional]
instructions/architecture.instructions.md   [customizable]
"""

PLANNER = "---\nname: planner\nmodel: __AF_TIER_BALANCED__\ndescription: 'x'\n---\n\n# Planner\n"


def _write(p: Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8", newline="")


def _make_source(root: Path, version: str = "1.0.0") -> Path:
    _write(root / "VERSION", version + "\n")
    gh = root / ".github"
    _write(gh / ".af-manifest", MANIFEST)
    _write(gh / "agents" / "planner.agent.md", PLANNER)
    _write(gh / "instructions" / "architecture.instructions.md", "# arch\n")
    _write(gh / "af-env.conf", "SRC_DIR=src\n")
    _write(gh / "MANIFEST.md", "# manifest doc\n")
    return root


# ── Tier resolution ────────────────────────────────────────────────────────


def test_tier_resolution_uses_defaults_as_yaml_array(tmp_path: Path) -> None:
    resolved = deploy_core.resolve_tier_tokens(PLANNER, tmp_path / "af-env.conf")
    assert "model:\n  - Claude Sonnet 5 (copilot)\n  - Claude Sonnet 4.6 (copilot)" in resolved
    assert "__AF_TIER_BALANCED__" not in resolved


def test_tier_resolution_single_entry_is_inline(tmp_path: Path) -> None:
    af = tmp_path / "af-env.conf"
    af.write_text("AF_MODEL_TIER_BALANCED=Only One (copilot)\n", encoding="utf-8")
    resolved = deploy_core.resolve_tier_tokens(PLANNER, af)
    assert "model: Only One (copilot)\n" in resolved


def test_tier_resolution_preserves_crlf(tmp_path: Path) -> None:
    crlf = PLANNER.replace("\n", "\r\n")
    resolved = deploy_core.resolve_tier_tokens(crlf, tmp_path / "af-env.conf")
    assert "\r\n  - Claude Sonnet 5 (copilot)\r\n" in resolved


# ── Status ─────────────────────────────────────────────────────────────────


def test_status_not_deployed(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src", "1.2.3")
    target = tmp_path / "proj"
    target.mkdir()
    assert deploy_core.status(src, target)["state"] == "not-deployed"


def test_status_up_to_date_and_stale(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src", "1.2.3")
    target = tmp_path / "proj"
    _write(target / ".github" / ".af-version", "version: 1.2.3\n")
    assert deploy_core.status(src, target)["state"] == "up-to-date"
    _write(target / ".github" / ".af-version", "version: 1.0.0\n")
    assert deploy_core.status(src, target)["state"] == "stale"


# ── Dry-run classification ─────────────────────────────────────────────────


def _deploy_identically(src: Path, target: Path) -> None:
    """Copy source .github into target and write a matching baseline (resolved)."""
    src_gh = src / ".github"
    tgt_gh = target / ".github"
    manifest = deploy_core.parse_manifest(src_gh / ".af-manifest")
    af_env = tgt_gh / "af-env.conf"
    lines = ["# AF deployment baseline hashes"]
    for rel in deploy_core.collect_source_files(src_gh, manifest):
        text = (src_gh / rel).read_text(encoding="utf-8")
        resolved = deploy_core.resolve_tier_tokens(text, af_env) if "__AF_TIER_" in text else text
        _write(tgt_gh / rel, resolved)
        lines.append(f"{rel}={deploy_core.source_hash_resolved(src_gh / rel, af_env)}")
    _write(tgt_gh / ".af-hashes", "\n".join(lines) + "\n")


def test_dry_run_clean_deploy_is_all_unchanged(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    _deploy_identically(src, target)
    result = deploy_core.dry_run(src, target)
    assert result["counts"].get("UNCHANGED") == result["total_files"]
    assert "UPDATE" not in result["counts"]
    assert "CONFLICT" not in result["counts"]


def test_dry_run_af_change_is_update(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    _deploy_identically(src, target)
    # AF changes a non-customizable file; project untouched → UPDATE.
    _write(src / ".github" / "MANIFEST.md", "# manifest doc CHANGED\n")
    files = {f["path"]: f["classification"] for f in deploy_core.dry_run(src, target)["files"]}
    assert files[".github/MANIFEST.md"] == "UPDATE"


def test_dry_run_customizable_project_change_is_preserved(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    _deploy_identically(src, target)
    # Project edits a [customizable] file; AF unchanged → PRESERVE (never clobbered).
    _write(target / ".github" / "af-env.conf", "SRC_DIR=myproject\n")
    files = {f["path"]: f["classification"] for f in deploy_core.dry_run(src, target)["files"]}
    assert files[".github/af-env.conf"] == "PRESERVE"


def test_dry_run_customizable_both_changed_is_conflict(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    _deploy_identically(src, target)
    _write(src / ".github" / "af-env.conf", "SRC_DIR=src\nNEW_KEY=1\n")
    _write(target / ".github" / "af-env.conf", "SRC_DIR=myproject\n")
    files = {f["path"]: f["classification"] for f in deploy_core.dry_run(src, target)["files"]}
    assert files[".github/af-env.conf"] == "CONFLICT"


def test_dry_run_tier_file_roundtrips_as_unchanged(tmp_path: Path) -> None:
    """A tier agent deployed cleanly must classify UNCHANGED (hash parity)."""
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    _deploy_identically(src, target)
    files = {f["path"]: f["classification"] for f in deploy_core.dry_run(src, target)["files"]}
    assert files[".github/agents/planner.agent.md"] == "UNCHANGED"


# ── Write path (Phase 1) ───────────────────────────────────────────────────


def test_apply_writes_update_and_backs_up(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    _deploy_identically(src, target)
    _write(src / ".github" / "MANIFEST.md", "# manifest doc CHANGED\n")

    report = deploy_core.apply(src, target)

    assert ".github/MANIFEST.md" in report["applied"]
    assert (target / ".github" / "MANIFEST.md").read_text(encoding="utf-8") == "# manifest doc CHANGED\n"
    assert report["backup_dir"] is not None
    assert (Path(report["backup_dir"]) / ".github" / "MANIFEST.md").read_text(encoding="utf-8") == "# manifest doc\n"
    # After apply, a fresh dry-run sees no pending updates.
    assert "UPDATE" not in deploy_core.dry_run(src, target)["counts"]


def test_apply_never_writes_customizable_conflict(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    _deploy_identically(src, target)
    _write(src / ".github" / "af-env.conf", "SRC_DIR=src\nNEW=1\n")
    _write(target / ".github" / "af-env.conf", "SRC_DIR=myproject\n")

    report = deploy_core.apply(src, target)

    assert ".github/af-env.conf" not in report["applied"]
    assert any(s["path"] == ".github/af-env.conf" for s in report["skipped"])
    # The project's customization is untouched.
    assert (target / ".github" / "af-env.conf").read_text(encoding="utf-8") == "SRC_DIR=myproject\n"


def test_write_resolved_refuses_traversal(tmp_path: Path) -> None:
    target = tmp_path / "proj"
    (target / ".github").mkdir(parents=True)
    import pytest

    with pytest.raises(ValueError):
        deploy_core.write_resolved(target, "../../evil.txt", "x")


def test_write_resolved_writes_under_github(tmp_path: Path) -> None:
    target = tmp_path / "proj"
    (target / ".github").mkdir(parents=True)
    deploy_core.write_resolved(target, "instructions/merged.md", "# merged\n")
    assert (target / ".github" / "instructions" / "merged.md").read_text(encoding="utf-8") == "# merged\n"


def test_conflict_diff_reports_changes(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    _deploy_identically(src, target)
    _write(src / ".github" / "MANIFEST.md", "# manifest doc CHANGED\n")
    diff = deploy_core.conflict_diff(src, target, "MANIFEST.md")
    assert "-# manifest doc" in diff
    assert "+# manifest doc CHANGED" in diff


def test_update_hashes_rebaselines(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    # Deploy files but with NO baseline, then rebaseline.
    _deploy_identically(src, target)
    (target / ".github" / ".af-hashes").unlink()
    result = deploy_core.update_hashes(src, target)
    assert result["entries"] == len(deploy_core.collect_source_files(src / ".github", deploy_core.parse_manifest(src / ".github" / ".af-manifest")))
    assert "UPDATE" not in deploy_core.dry_run(src, target)["counts"]


def test_prune_backups_removes_old_dirs(tmp_path: Path) -> None:
    import os
    import time

    target = tmp_path / "proj"
    old = target / ".af-backup-20200101000000"
    old.mkdir(parents=True)
    old_time = time.time() - 30 * 86400
    os.utime(old, (old_time, old_time))
    fresh = target / ".af-backup-fresh"
    fresh.mkdir()

    removed = deploy_core.prune_backups(target, days=14)["removed"]
    assert ".af-backup-20200101000000" in removed
    assert not old.exists()
    assert fresh.exists()  # recent backup kept

