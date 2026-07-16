"""Tests for the optional remote payload fetch (governance mode)."""

from __future__ import annotations

import hashlib
import zipfile
from pathlib import Path

import pytest

from af_deploy_mcp import deploy_core, remote_payload


def _make_payload_zip(tmp_path: Path, version: str = "9.9.9") -> tuple[Path, str]:
    """Build a valid payload tree, zip it, return (archive_path, sha256_upper)."""
    payload = tmp_path / "payloadsrc"
    (payload / ".github").mkdir(parents=True)
    (payload / ".github" / ".af-manifest").write_text("# manifest\n", encoding="utf-8")
    (payload / "VERSION").write_text(version + "\n", encoding="utf-8")
    archive = tmp_path / "payload.zip"
    with zipfile.ZipFile(archive, "w") as zf:
        for p in sorted(payload.rglob("*")):
            if p.is_file():
                zf.write(p, p.relative_to(payload).as_posix())
    data = archive.read_bytes()
    return archive, hashlib.sha256(data).hexdigest().upper()


def _file_url(p: Path) -> str:
    return p.resolve().as_uri()


def test_fetch_payload_verifies_and_extracts(tmp_path: Path) -> None:
    archive, sha = _make_payload_zip(tmp_path)
    root = remote_payload.fetch_payload(_file_url(archive), sha, tmp_path / "cache")
    assert (root / "VERSION").read_text(encoding="utf-8").strip() == "9.9.9"
    assert (root / ".github" / ".af-manifest").is_file()


def test_fetch_payload_hash_mismatch_raises(tmp_path: Path) -> None:
    archive, _sha = _make_payload_zip(tmp_path)
    with pytest.raises(ValueError, match="hash mismatch"):
        remote_payload.fetch_payload(_file_url(archive), "0" * 64, tmp_path / "cache")


def test_fetch_payload_rejects_plain_http(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="scheme"):
        remote_payload.fetch_payload("http://example.com/p.zip", "A" * 64, tmp_path / "cache")


def test_fetch_payload_caches_and_skips_refetch(tmp_path: Path) -> None:
    archive, sha = _make_payload_zip(tmp_path)
    cache = tmp_path / "cache"
    root1 = remote_payload.fetch_payload(_file_url(archive), sha, cache)
    archive.unlink()  # a cached hit must resolve without touching the source
    root2 = remote_payload.fetch_payload(_file_url(archive), sha, cache)
    assert root1 == root2
    assert (root2 / "VERSION").is_file()


def test_fetch_payload_refuses_zip_slip(tmp_path: Path) -> None:
    archive = tmp_path / "evil.zip"
    with zipfile.ZipFile(archive, "w") as zf:
        zf.writestr("../evil.txt", "pwned")
    sha = hashlib.sha256(archive.read_bytes()).hexdigest().upper()
    with pytest.raises(ValueError, match="escaping archive root"):
        remote_payload.fetch_payload(_file_url(archive), sha, tmp_path / "cache")


def test_resolve_source_root_remote_requires_pin(monkeypatch) -> None:
    monkeypatch.delenv("AF_SOURCE_ROOT", raising=False)
    monkeypatch.setenv("AF_PAYLOAD_URL", "https://example.com/p.zip")
    monkeypatch.delenv("AF_PAYLOAD_SHA256", raising=False)
    with pytest.raises(ValueError, match="unpinned payload"):
        deploy_core.resolve_source_root()


def test_resolve_source_root_uses_remote_payload(tmp_path: Path, monkeypatch) -> None:
    archive, sha = _make_payload_zip(tmp_path)
    monkeypatch.delenv("AF_SOURCE_ROOT", raising=False)
    monkeypatch.setenv("AF_PAYLOAD_URL", _file_url(archive))
    monkeypatch.setenv("AF_PAYLOAD_SHA256", sha)
    monkeypatch.setenv("AF_PAYLOAD_CACHE", str(tmp_path / "cache"))
    root = deploy_core.resolve_source_root()
    assert (root / "VERSION").read_text(encoding="utf-8").strip() == "9.9.9"
