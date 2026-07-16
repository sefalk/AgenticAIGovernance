"""EOL/BOM parity tests — the deployed bytes must be canonical UTF-8 (no BOM), LF.

These lock the invariant that the MCP write/hash path produces the same canonical
bytes regardless of the source's line endings or BOM, so it stays byte-identical
to what deploy.ps1/.sh emit for the same logical content.
"""

from __future__ import annotations

import re
from pathlib import Path

from af_deploy_mcp import deploy_core

TIER_FILE = "---\nname: planner\nmodel: __AF_TIER_BALANCED__\ndescription: 'x'\n---\n\n# Planner\n"


def _write_bytes(p: Path, data: bytes) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(data)


def test_resolved_source_bytes_normalizes_crlf_to_lf(tmp_path: Path) -> None:
    src = tmp_path / "f.md"
    _write_bytes(src, b"line one\r\nline two\r\n")
    out = deploy_core.resolved_source_bytes(src, tmp_path / "af-env.conf")
    assert out == b"line one\nline two\n"
    assert b"\r" not in out


def test_resolved_source_bytes_normalizes_lone_cr(tmp_path: Path) -> None:
    src = tmp_path / "f.md"
    _write_bytes(src, b"a\rb\r")
    out = deploy_core.resolved_source_bytes(src, tmp_path / "af-env.conf")
    assert out == b"a\nb\n"


def test_resolved_source_bytes_strips_utf8_bom(tmp_path: Path) -> None:
    src = tmp_path / "f.md"
    _write_bytes(src, b"\xef\xbb\xbf# heading\n")
    out = deploy_core.resolved_source_bytes(src, tmp_path / "af-env.conf")
    assert out == b"# heading\n"
    assert not out.startswith(b"\xef\xbb\xbf")


def test_resolved_source_bytes_lf_is_noop(tmp_path: Path) -> None:
    src = tmp_path / "f.md"
    original = b"already\nlf\ncontent\n"
    _write_bytes(src, original)
    assert deploy_core.resolved_source_bytes(src, tmp_path / "af-env.conf") == original


def test_resolved_source_bytes_tier_from_crlf_is_lf(tmp_path: Path) -> None:
    src = tmp_path / "planner.agent.md"
    _write_bytes(src, TIER_FILE.replace("\n", "\r\n").encode("utf-8"))
    out = deploy_core.resolved_source_bytes(src, tmp_path / "af-env.conf")
    assert b"\r" not in out
    assert b"__AF_TIER_BALANCED__" not in out
    assert b"model:\n  - Claude Sonnet 5 (copilot)" in out


def test_source_hash_resolved_is_eol_independent(tmp_path: Path) -> None:
    lf = tmp_path / "lf.md"
    crlf = tmp_path / "crlf.md"
    _write_bytes(lf, b"same\ncontent\nhere\n")
    _write_bytes(crlf, b"same\r\ncontent\r\nhere\r\n")
    af = tmp_path / "af-env.conf"
    assert deploy_core.source_hash_resolved(lf, af) == deploy_core.source_hash_resolved(crlf, af)


def test_resolved_source_bytes_binary_passthrough(tmp_path: Path) -> None:
    src = tmp_path / "logo.png"
    blob = b"\x89PNG\r\n\x1a\n\xff\xfe\x00\x01binary\xc0\xc1"
    _write_bytes(src, blob)
    # Non-UTF-8 content must be returned untouched (never normalized/corrupted).
    assert deploy_core.resolved_source_bytes(src, tmp_path / "af-env.conf") == blob


def test_apply_writes_lf_and_no_bom(tmp_path: Path) -> None:
    src = tmp_path / "src"
    gh = src / ".github"
    (gh / "agents").mkdir(parents=True)
    (src / "VERSION").write_bytes(b"1.0.0\n")
    (gh / ".af-manifest").write_bytes(b"# manifest\r\nagents/\r\n")
    # A CRLF, BOM-prefixed agent file in the source.
    (gh / "agents" / "planner.agent.md").write_bytes(b"\xef\xbb\xbf# Planner\r\nbody\r\n")

    target = tmp_path / "proj"
    deploy_core.apply(src, target)

    written = (target / ".github" / "agents" / "planner.agent.md").read_bytes()
    assert written == b"# Planner\nbody\n"
    assert b"\r" not in written
    assert not written.startswith(b"\xef\xbb\xbf")


def test_write_resolved_canonicalizes_crlf_and_bom(tmp_path: Path) -> None:
    target = tmp_path / "proj"
    (target / ".github").mkdir(parents=True)
    deploy_core.write_resolved(target, "agents/x.agent.md", "\ufeffline\r\ntwo\r\n")
    written = (target / ".github" / "agents" / "x.agent.md").read_bytes()
    assert written == b"line\ntwo\n"


def test_baseline_hashes_are_uppercase(tmp_path: Path) -> None:
    # deploy.ps1 (ToString('X2')) and deploy.sh (tr a-f A-F) emit uppercase hex;
    # the MCP baseline must match so .af-hashes is byte-portable across tools.
    src = tmp_path / "src"
    gh = src / ".github"
    (gh / "agents").mkdir(parents=True)
    (src / "VERSION").write_bytes(b"1.0.0\n")
    (gh / ".af-manifest").write_bytes(b"# manifest\nagents/\n")
    (gh / "agents" / "planner.agent.md").write_bytes(b"# Planner\n")
    target = tmp_path / "proj"
    deploy_core.update_hashes(src, target)
    hashes_text = (target / ".github" / ".af-hashes").read_text(encoding="utf-8")
    values = [ln.split("=", 1)[1] for ln in hashes_text.splitlines() if "=" in ln and not ln.startswith("#")]
    assert values, "expected at least one hash entry"
    for val in values:
        assert re.fullmatch(r"[0-9A-F]+", val), val
