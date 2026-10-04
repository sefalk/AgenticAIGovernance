"""Tests for deploy_core — the read-only AF deploy logic behind the MCP PoC."""

from __future__ import annotations

from pathlib import Path

from af_deploy_mcp import deploy_core

MANIFEST = """\
# manifest
agents/
instructions/
af-env.conf   [customizable]
MANIFEST.md
.af-version   [optional]
instructions/architecture.instructions.md   [customizable]
tasks.json   [customizable, vscode]
settings.json   [vscode]
missing.jsonc   [optional, vscode]
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
    _write(root / ".vscode" / "tasks.json", '{"version":"2.0.0"}\n')
    _write(root / ".vscode" / "settings.json", '{"editor.tabSize":4}\n')
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


# ── Payload staleness (#236) ───────────────────────────────────────────────


def _bundled(tmp_path: Path, payload_version: str, repo_version: str | None) -> tuple[Path, Path]:
    """Build a wheel-shaped layout: flavor/mcp-deploy/af_deploy_mcp/payload."""
    flavor = tmp_path / "flavor"
    pkg = flavor / "mcp-deploy" / "af_deploy_mcp"
    src = _make_source(pkg / "payload", payload_version)
    if repo_version is not None:
        _write(flavor / "VERSION", repo_version + "\n")
    return pkg, src


def _deployed(tmp_path: Path, version: str) -> Path:
    target = tmp_path / "proj"
    _write(target / ".github" / ".af-version", f"version: {version}\n")
    return target


def test_bundled_payload_behind_repository_is_named(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.delenv("AF_SOURCE_ROOT", raising=False)
    monkeypatch.delenv("AF_PAYLOAD_URL", raising=False)
    pkg, src = _bundled(tmp_path, payload_version="1.2.3", repo_version="1.3.0")
    result = deploy_core.status(src, _deployed(tmp_path, "1.2.3"), package_dir=pkg)
    # The target matches the payload, so the old check is happy — that is the trap.
    assert result["state"] == "up-to-date"
    assert result["payload_state"] == "behind-repository"
    assert result["repository_version"] == "1.3.0"
    assert "1.2.3" in result["payload_note"] and "1.3.0" in result["payload_note"]


def test_bundled_payload_matching_repository_is_current(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.delenv("AF_SOURCE_ROOT", raising=False)
    monkeypatch.delenv("AF_PAYLOAD_URL", raising=False)
    pkg, src = _bundled(tmp_path, payload_version="1.3.0", repo_version="1.3.0")
    result = deploy_core.status(src, _deployed(tmp_path, "1.3.0"), package_dir=pkg)
    assert result["payload_state"] == "current"
    assert "payload_note" not in result


def test_bundled_payload_without_a_checkout_says_it_cannot_tell(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.delenv("AF_SOURCE_ROOT", raising=False)
    monkeypatch.delenv("AF_PAYLOAD_URL", raising=False)
    pkg, src = _bundled(tmp_path, payload_version="1.2.3", repo_version=None)
    result = deploy_core.status(src, _deployed(tmp_path, "1.2.3"), package_dir=pkg)
    # Silence would read as "fine"; an installed wheel genuinely cannot know.
    assert result["payload_state"] == "unverifiable"
    assert "repository_version" not in result
    assert "reinstall" in result["payload_note"]


def test_in_repo_payload_needs_no_staleness_claim(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.delenv("AF_SOURCE_ROOT", raising=False)
    monkeypatch.delenv("AF_PAYLOAD_URL", raising=False)
    src = _make_source(tmp_path / "flavor", "1.3.0")
    pkg = tmp_path / "flavor" / "mcp-deploy" / "af_deploy_mcp"
    pkg.mkdir(parents=True)
    result = deploy_core.status(src, _deployed(tmp_path, "1.3.0"), package_dir=pkg)
    assert result["payload_origin"] == "in-repo"
    assert result["payload_state"] == "not-applicable"


def test_env_override_is_not_reported_as_a_bundled_payload(tmp_path: Path, monkeypatch) -> None:
    pkg, src = _bundled(tmp_path, payload_version="1.2.3", repo_version="1.3.0")
    monkeypatch.setenv("AF_SOURCE_ROOT", str(src))
    result = deploy_core.status(src, _deployed(tmp_path, "1.2.3"), package_dir=pkg)
    assert result["payload_origin"] == "env-override"
    assert result["payload_state"] == "not-applicable"


# ── Dry-run classification ─────────────────────────────────────────────────


def _deploy_identically(src: Path, target: Path) -> None:
    """Copy source payload into target and write a matching baseline (resolved)."""
    tgt_gh = target / ".github"
    af_env = tgt_gh / "af-env.conf"
    manifest = deploy_core.parse_manifest(src / ".github" / ".af-manifest")
    lines = ["# AF deployment baseline hashes"]
    for u in deploy_core.collect_units(src, target, manifest):
        data = deploy_core.resolved_source_bytes(u.source, af_env)
        u.target.parent.mkdir(parents=True, exist_ok=True)
        u.target.write_bytes(data)
        lines.append(f"{u.hash_key}={deploy_core.source_hash_resolved(u.source, af_env)}")
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
    manifest = deploy_core.parse_manifest(src / ".github" / ".af-manifest")
    assert result["entries"] == len(deploy_core.collect_units(src, target, manifest))
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


# ── VS Code files ([vscode]) ────────────────────────────────────────


def test_dry_run_includes_vscode_files(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    _deploy_identically(src, target)
    paths = {f["path"] for f in deploy_core.dry_run(src, target)["files"]}
    assert ".vscode/tasks.json" in paths
    assert ".vscode/settings.json" in paths
    assert ".vscode/missing.jsonc" not in paths  # optional + absent → skipped


def test_dry_run_vscode_customizable_preserved(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    _deploy_identically(src, target)
    # Project edits a [customizable, vscode] file; AF unchanged → PRESERVE.
    _write(target / ".vscode" / "tasks.json", '{"version":"2.0.0","custom":true}\n')
    files = {f["path"]: f["classification"] for f in deploy_core.dry_run(src, target)["files"]}
    assert files[".vscode/tasks.json"] == "PRESERVE"


def test_apply_writes_vscode_update(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    _deploy_identically(src, target)
    # AF changes a non-customizable vscode file → apply writes it under .vscode/.
    _write(src / ".vscode" / "settings.json", '{"editor.tabSize":2}\n')
    report = deploy_core.apply(src, target)
    assert ".vscode/settings.json" in report["applied"]
    assert (target / ".vscode" / "settings.json").read_text(encoding="utf-8") == '{"editor.tabSize":2}\n'


def test_write_resolved_vscode_prefix(tmp_path: Path) -> None:
    target = tmp_path / "proj"
    (target / ".vscode").mkdir(parents=True)
    out = deploy_core.write_resolved(target, ".vscode/settings.json", "{}\n")
    assert out["path"] == ".vscode/settings.json"
    assert (target / ".vscode" / "settings.json").read_text(encoding="utf-8") == "{}\n"


def test_conflict_diff_vscode(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    _deploy_identically(src, target)
    _write(src / ".vscode" / "settings.json", '{"editor.tabSize":2}\n')
    diff = deploy_core.conflict_diff(src, target, ".vscode/settings.json")
    assert "editor.tabSize" in diff
    assert "+" in diff and "-" in diff


# ── Payload resolution (packaging) ─────────────────────────────────────────


def test_resolve_source_root_env_override(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("AF_SOURCE_ROOT", str(tmp_path))
    assert deploy_core.resolve_source_root() == tmp_path.resolve()


def test_resolve_source_root_prefers_bundled_payload(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.delenv("AF_SOURCE_ROOT", raising=False)
    pkg = tmp_path / "af_deploy_mcp"
    payload = pkg / "payload"
    payload.mkdir(parents=True)
    (payload / "VERSION").write_text("1.0.0\n", encoding="utf-8")
    assert deploy_core.resolve_source_root(package_dir=pkg) == payload.resolve()


def test_resolve_source_root_dev_fallback(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.delenv("AF_SOURCE_ROOT", raising=False)
    # No bundled payload → the flavor dir two levels above the package.
    pkg = tmp_path / "flavor" / "mcp-deploy" / "af_deploy_mcp"
    pkg.mkdir(parents=True)
    assert deploy_core.resolve_source_root(package_dir=pkg) == (tmp_path / "flavor").resolve()


def test_collect_source_files_excludes_pycache(tmp_path: Path) -> None:
    root = _make_source(tmp_path / "src")
    gh = root / ".github"
    # Stray bytecode caches (regenerate when the guard test runs) must be ignored.
    _write(gh / "agents" / "__pycache__" / "planner.cpython-311.pyc", "junk")
    _write(gh / "agents" / "leftover.pyc", "junk")
    manifest = deploy_core.parse_manifest(gh / ".af-manifest")
    files = deploy_core.collect_source_files(gh, manifest)
    assert not any("__pycache__" in f or f.endswith((".pyc", ".pyo")) for f in files)
    assert "agents/planner.agent.md" in files


def test_validate_payload_flags_missing_pieces(tmp_path: Path) -> None:
    assert deploy_core.validate_payload(tmp_path) is not None  # no VERSION
    (tmp_path / "VERSION").write_text("1.0.0\n", encoding="utf-8")
    assert deploy_core.validate_payload(tmp_path) is not None  # no .af-manifest
    (tmp_path / ".github").mkdir()
    (tmp_path / ".github" / ".af-manifest").write_text("# manifest\n", encoding="utf-8")
    assert deploy_core.validate_payload(tmp_path) is None


# ── Orphan detection & pruning ─────────────────────────────────────────────


def _add_baseline_entry(target: Path, key: str) -> None:
    hf = target / ".github" / ".af-hashes"
    hf.write_text(hf.read_text(encoding="utf-8") + f"{key}=DEADBEEF\n", encoding="utf-8")


def test_list_and_prune_orphans(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    _deploy_identically(src, target)
    # Simulate a framework file removed from source but still baselined + on disk.
    orphan = target / ".github" / "agents" / "old.agent.md"
    _write(orphan, "# old agent\n")
    _add_baseline_entry(target, "agents/old.agent.md")

    found = deploy_core.list_orphans(src, target)
    assert any(o["path"] == ".github/agents/old.agent.md" for o in found)

    report = deploy_core.prune_orphans(src, target)
    assert ".github/agents/old.agent.md" in report["removed"]
    assert not orphan.exists()
    assert (Path(report["backup_dir"]) / ".github" / "agents" / "old.agent.md").is_file()
    assert "agents/old.agent.md" not in deploy_core.read_baseline_hashes(target / ".github")
    # Idempotent: nothing left to prune.
    assert deploy_core.list_orphans(src, target) == []


def test_list_orphans_ignores_project_files(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    _deploy_identically(src, target)
    # A project-created file (not in the baseline) is never an orphan.
    _write(target / ".github" / "agents" / "my-custom.agent.md", "# mine\n")
    assert deploy_core.list_orphans(src, target) == []


def test_prune_orphans_no_op_when_none(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    _deploy_identically(src, target)
    report = deploy_core.prune_orphans(src, target)
    assert report["removed"] == [] and report["backup_dir"] is None


def test_list_orphans_handles_vscode(tmp_path: Path) -> None:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    _deploy_identically(src, target)
    orphan = target / ".vscode" / "old-launch.json"
    _write(orphan, "{}\n")
    _add_baseline_entry(target, "vscode/old-launch.json")
    found = deploy_core.list_orphans(src, target)
    assert any(o["path"] == ".vscode/old-launch.json" for o in found)
