"""3-way merge for files both the framework and the project changed (#105).

``CONFLICT`` used to be a hash verdict: any file whose hash moved on both sides
was withheld, even when the edits did not overlap. Measured in a real upgrade, 4
of 7 conflicts merged cleanly, among them the files carrying the fixes the
upgrade was for.

The baseline content now lives in a store in the target,
``.github/.af-baseline/<HASH>``, holding the canonical bytes whose hash
``.af-hashes`` records. A non-customizable file that merges without overlap is
``MERGE`` and is applied. Anything the merge cannot vouch for stays
``CONFLICT``, which is never worse than before.
"""

from __future__ import annotations

import hashlib
import shutil
from pathlib import Path

from af_deploy_mcp import deploy_core

MANIFEST = """\
# manifest
agents/
af-env.conf   [customizable]
MANIFEST.md
DOC.md   [customizable]
"""

LINES = [f"line {i}" for i in range(1, 13)]
REGION = "curated-skills"


def _text(lines: list[str]) -> str:
    return "\n".join(lines) + "\n"


def _with(index: int, value: str) -> list[str]:
    lines = list(LINES)
    lines[index] = value
    return lines


def _write(p: Path, text: str, newline: str = "") -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8", newline=newline)


def _make_source(root: Path) -> Path:
    _write(root / "VERSION", "1.0.0\n")
    gh = root / ".github"
    _write(gh / ".af-manifest", MANIFEST)
    _write(gh / "agents" / "planner.agent.md", "# planner\n")
    _write(gh / "af-env.conf", "SRC_DIR=src\n")
    _write(gh / "MANIFEST.md", _text(LINES))
    _write(gh / "DOC.md", _text(LINES))
    return root


def _deployed(tmp_path: Path) -> tuple[Path, Path]:
    src = _make_source(tmp_path / "src")
    target = tmp_path / "proj"
    deploy_core.apply(src, target)
    return src, target


def _classes(src: Path, target: Path) -> dict[str, str]:
    return {f["path"]: f["classification"] for f in deploy_core.dry_run(src, target)["files"]}


def _diverge(src: Path, target: Path, name: str, af_index: int, project_index: int) -> None:
    """The framework edits one line, the project another."""
    _write(src / ".github" / name, _text(_with(af_index, "line AF")))
    _write(target / ".github" / name, _text(_with(project_index, "line PROJECT")))


def _store(target: Path) -> Path:
    return target / ".github" / ".af-baseline"


# ── The store ───────────────────────────────────────────────────────────────


def test_apply_stores_the_content_behind_every_recorded_hash(tmp_path: Path) -> None:
    _, target = _deployed(tmp_path)
    recorded = deploy_core.read_baseline_hashes(target / ".github")
    assert recorded
    for key, digest in recorded.items():
        obj = _store(target) / digest
        assert obj.is_file(), f"no stored baseline for {key}"
        assert hashlib.sha256(obj.read_bytes()).hexdigest().upper() == digest


def test_the_store_ignores_itself_in_git(tmp_path: Path) -> None:
    _, target = _deployed(tmp_path)
    assert (_store(target) / ".gitignore").read_text(encoding="utf-8").strip() == "*"


def test_update_hashes_stores_the_content_it_baselines(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    shutil.rmtree(_store(target), ignore_errors=True)
    deploy_core.update_hashes(src, target)
    for digest in deploy_core.read_baseline_hashes(target / ".github").values():
        assert (_store(target) / digest).is_file()


def test_an_object_no_hash_references_is_pruned(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    old = deploy_core.read_baseline_hashes(target / ".github")["MANIFEST.md"]
    assert (_store(target) / old).is_file()
    _write(src / ".github" / "MANIFEST.md", _text(_with(0, "line AF")))
    deploy_core.apply(src, target)
    assert not (_store(target) / old).exists()


# ── Classification ──────────────────────────────────────────────────────────


def test_non_overlapping_edits_classify_as_merge(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    _diverge(src, target, "MANIFEST.md", af_index=0, project_index=11)
    assert _classes(src, target)[".github/MANIFEST.md"] == "MERGE"


def test_overlapping_edits_stay_conflict(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    _diverge(src, target, "MANIFEST.md", af_index=5, project_index=5)
    assert _classes(src, target)[".github/MANIFEST.md"] == "CONFLICT"


def test_a_customizable_file_is_never_merged(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    _diverge(src, target, "DOC.md", af_index=0, project_index=11)
    assert _classes(src, target)[".github/DOC.md"] == "CONFLICT"


def test_without_a_stored_baseline_it_stays_conflict(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    _diverge(src, target, "MANIFEST.md", af_index=0, project_index=11)
    shutil.rmtree(_store(target), ignore_errors=True)
    assert _classes(src, target)[".github/MANIFEST.md"] == "CONFLICT"


def test_a_tampered_object_is_not_trusted(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    digest = deploy_core.read_baseline_hashes(target / ".github")["MANIFEST.md"]
    _diverge(src, target, "MANIFEST.md", af_index=0, project_index=11)
    _store(target).mkdir(parents=True, exist_ok=True)
    (_store(target) / digest).write_bytes(_text(_with(11, "line PROJECT")).encode("utf-8"))
    assert _classes(src, target)[".github/MANIFEST.md"] == "CONFLICT"


def test_a_crlf_target_merges_on_its_real_delta(tmp_path: Path) -> None:
    # The caveat in #105: mixed endings made a one-line change a whole-file conflict.
    src, target = _deployed(tmp_path)
    _write(src / ".github" / "MANIFEST.md", _text(_with(0, "line AF")))
    _write(target / ".github" / "MANIFEST.md", _text(_with(11, "line PROJECT")), newline="\r\n")
    assert _classes(src, target)[".github/MANIFEST.md"] == "MERGE"


def test_without_git_it_stays_conflict(tmp_path: Path, monkeypatch) -> None:
    src, target = _deployed(tmp_path)
    _diverge(src, target, "MANIFEST.md", af_index=0, project_index=11)
    monkeypatch.setenv("PATH", str(tmp_path / "no-tools-here"))
    assert _classes(src, target)[".github/MANIFEST.md"] == "CONFLICT"


# ── Apply ───────────────────────────────────────────────────────────────────


def test_apply_writes_both_sides_and_backs_up_the_project_file(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    _diverge(src, target, "MANIFEST.md", af_index=0, project_index=11)

    report = deploy_core.apply(src, target)

    written = (target / ".github" / "MANIFEST.md").read_text(encoding="utf-8")
    assert written == _text(["line AF", *LINES[1:11], "line PROJECT"])
    assert ".github/MANIFEST.md" in report["merged"]
    assert ".github/MANIFEST.md" in report["applied"]
    backup = Path(report["backup_dir"]) / ".github" / "MANIFEST.md"
    assert backup.read_text(encoding="utf-8") == _text(_with(11, "line PROJECT"))


def test_after_a_merge_the_project_edit_reads_as_preserved(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    _diverge(src, target, "MANIFEST.md", af_index=0, project_index=11)
    deploy_core.apply(src, target)
    assert _classes(src, target)[".github/MANIFEST.md"] == "PRESERVE"


def test_apply_leaves_an_overlapping_conflict_untouched(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    _diverge(src, target, "MANIFEST.md", af_index=5, project_index=5)
    report = deploy_core.apply(src, target)
    assert (target / ".github" / "MANIFEST.md").read_text(encoding="utf-8") == _text(_with(5, "line PROJECT"))
    assert {"path": ".github/MANIFEST.md", "classification": "CONFLICT"} in report["skipped"]


def test_a_merge_keeps_the_project_managed_region(tmp_path: Path) -> None:
    def agent(first: str, region_body: str, last: str) -> str:
        return (
            f"{first}\n"
            + _text(LINES[1:6])
            + f"<!-- AF:MANAGED:{REGION}:START -->\n{region_body}<!-- AF:MANAGED:{REGION}:END -->\n"
            + _text(LINES[6:11])
            + f"{last}\n"
        )

    src, target = _deployed(tmp_path)
    path = ".github/agents/planner.agent.md"
    _write(src / path, agent("line 1", "", "line 12"))
    deploy_core.apply(src, target)
    _write(target / path, agent("line 1", "- **cur-x** curated\n", "line PROJECT"))
    _write(src / path, agent("line AF", "", "line 12"))

    assert _classes(src, target)[path] == "MERGE"
    deploy_core.apply(src, target)
    assert (target / path).read_text(encoding="utf-8") == agent("line AF", "- **cur-x** curated\n", "line PROJECT")
