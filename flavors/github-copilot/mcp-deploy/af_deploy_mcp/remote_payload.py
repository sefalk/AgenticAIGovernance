"""Optional remote framework payload fetch for the AF deploy MCP server.

Governance mode: instead of the payload bundled in the wheel, an operator can
point the server at a published, hash-pinned payload archive via env vars
(consumed by ``deploy_core.resolve_source_root``):

    AF_PAYLOAD_URL      ``https://`` (or ``file://``) URL of a ``.zip`` / ``.tar.gz`` archive
    AF_PAYLOAD_SHA256   expected SHA-256 (uppercase hex) of the archive bytes
    AF_PAYLOAD_CACHE    optional local cache directory

Security model:

* the hash pin is **mandatory** — an unpinned ``AF_PAYLOAD_URL`` is refused;
* only ``https`` and ``file`` URL schemes are allowed (no plain ``http``);
* the archive is verified **before** extraction;
* extraction is path-traversal-safe (zip-slip / tar escape refused, links refused);
* results are cached **by hash**, so integrity is inherent and re-fetch is skipped.

No project data ever leaves the machine — this is a one-way, outbound fetch of the
framework payload only. Dependency-free (stdlib: urllib, hashlib, zipfile, tarfile).
"""

from __future__ import annotations

import hashlib
import io
import tarfile
import urllib.request
import zipfile
from pathlib import Path
from urllib.parse import urlparse

_ALLOWED_SCHEMES = frozenset({"https", "file"})


def _download(url: str, timeout: float = 30.0) -> bytes:
    """Fetch raw bytes from an allow-listed URL scheme (``https`` or ``file``)."""
    scheme = urlparse(url).scheme.lower()
    if scheme not in _ALLOWED_SCHEMES:
        raise ValueError(f"Refused payload URL scheme {scheme!r}: only {sorted(_ALLOWED_SCHEMES)} allowed.")
    with urllib.request.urlopen(url, timeout=timeout) as resp:  # scheme allow-listed above
        return resp.read()


def _is_within(base: Path, target: Path) -> bool:
    base = base.resolve()
    target = target.resolve()
    return base == target or base in target.parents


def _extract_zip(data: bytes, dest: Path) -> None:
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        for name in zf.namelist():
            if not _is_within(dest, dest / name):
                raise ValueError(f"Refused zip member escaping archive root: {name}")
        zf.extractall(dest)


def _extract_tar(data: bytes, dest: Path) -> None:
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as tf:
        for member in tf.getmembers():
            if member.issym() or member.islnk():
                raise ValueError(f"Refused link member in payload archive: {member.name}")
            if not _is_within(dest, dest / member.name):
                raise ValueError(f"Refused tar member escaping archive root: {member.name}")
        tf.extractall(dest)


def _extract(data: bytes, url: str, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    lower = url.lower()
    if lower.endswith(".zip"):
        _extract_zip(data, dest)
    elif lower.endswith((".tar.gz", ".tgz", ".tar")):
        _extract_tar(data, dest)
    else:
        raise ValueError(f"Unsupported payload archive type for URL: {url}")


def _payload_root(extracted: Path) -> Path:
    """The directory containing ``VERSION``: the extract root, or a single nested dir."""
    if (extracted / "VERSION").is_file():
        return extracted
    if extracted.is_dir():
        subdirs = [p for p in extracted.iterdir() if p.is_dir()]
        if len(subdirs) == 1 and (subdirs[0] / "VERSION").is_file():
            return subdirs[0]
    return extracted


def fetch_payload(url: str, sha256: str, cache_dir: Path) -> Path:
    """Download, verify (SHA-256) and extract a payload archive; return its root.

    Cached by hash under ``cache_dir`` — a valid cached copy skips the network.

    Parameters
    ----------
    url:
        ``https``/``file`` URL of a ``.zip`` or ``.tar.gz`` payload archive.
    sha256:
        Expected SHA-256 (hex) of the archive bytes; comparison is case-insensitive.
    cache_dir:
        Root cache directory; the payload is extracted under ``{cache_dir}/{sha}/``.

    Returns
    -------
    Path
        The payload root (contains ``VERSION`` and ``.github/``).

    Raises
    ------
    ValueError
        On a missing pin, disallowed scheme, hash mismatch, or unsafe archive.
    """
    sha = sha256.strip().upper()
    if not sha:
        raise ValueError("A payload hash pin (SHA-256) is required — refusing an unpinned fetch.")
    extracted = cache_dir / sha / "extracted"
    cached = _payload_root(extracted)
    if (cached / "VERSION").is_file():
        return cached
    data = _download(url)
    actual = hashlib.sha256(data).hexdigest().upper()
    if actual != sha:
        raise ValueError(f"Payload hash mismatch: expected {sha}, got {actual}.")
    _extract(data, url, extracted)
    return _payload_root(extracted)
