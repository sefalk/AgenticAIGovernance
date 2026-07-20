"""AF deploy logic for the MCP PoC — a parity port of ``deploy.ps1`` / ``deploy.sh``.

Provides version status, the 3-way dry-run classification (including agent
model-tier resolution), and the guarded write path (apply with backups,
re-baseline, resolved-write, conflict diff, backup pruning). Covers both the
``.github/`` payload and manifest ``[vscode]`` files (deployed to ``.vscode/``).

Hash format matches the PowerShell deploy: SHA-256, uppercase hex. Tier files
are hashed over their resolved UTF-8 (no BOM) bytes, exactly like
``Get-StringHashUpper`` in ``deploy.ps1``. Path keys are normalized to forward
slashes so a baseline written by either the ``.ps1`` (Windows, backslashes) or
``.sh`` (POSIX, forward slashes) deploy compares consistently.
"""

from __future__ import annotations

import difflib
import hashlib
import os
import re
import shutil
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

# Curated fallback tiers — keep in sync with deploy.ps1 / deploy.sh $TierDefaults.
TIER_DEFAULTS: dict[str, str] = {
    "PREMIUM": "Claude Opus 4.8 (copilot), Claude Opus 4.7 (copilot), Claude Sonnet 5 (copilot)",
    "BALANCED": "Claude Sonnet 5 (copilot), Claude Sonnet 4.6 (copilot), Claude Sonnet 4.5 (copilot)",
    "EFFICIENT": "Claude Haiku 4.5 (copilot), Claude Sonnet 5 (copilot)",
}

_TIER_TOKEN_RE = re.compile(r"__AF_TIER_(PREMIUM|BALANCED|EFFICIENT)__")


def _norm(rel: str) -> str:
    """Normalize a relative path key to forward slashes."""
    return rel.replace("\\", "/")


def get_af_env_value(af_env_path: Path, key: str) -> str:
    """Return the value of ``key`` in the target af-env.conf, or ''."""
    if not af_env_path.is_file():
        return ""
    pattern = re.compile(r"^\s*" + re.escape(key) + r"=(.*)$")
    for line in af_env_path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = pattern.match(line)
        if m:
            return m.group(1).strip()
    return ""


def _tier_models(tier: str, af_env_path: Path) -> list[str]:
    val = get_af_env_value(af_env_path, f"AF_MODEL_TIER_{tier}") or TIER_DEFAULTS[tier]
    return [m.strip() for m in val.split(",") if m.strip()]


def resolve_tier_tokens(text: str, af_env_path: Path) -> str:
    """Replace ``model: __AF_TIER_X__`` lines with the resolved model list.

    Byte-compatible with ``deploy.ps1`` Resolve-TierTokens: preserves the file's
    dominant newline, emits a single ``model: X`` for one entry or a YAML array
    for several, and never consumes the line break (lookahead).
    """
    nl = "\r\n" if "\r\n" in text else "\n"
    for tier in ("PREMIUM", "BALANCED", "EFFICIENT"):
        token = f"__AF_TIER_{tier}__"
        if token not in text:
            continue
        models = _tier_models(tier, af_env_path)
        if len(models) <= 1:
            repl = f"model: {models[0]}" if models else "model:"
        else:
            repl = "model:" + "".join(f"{nl}  - {m}" for m in models)
        pattern = re.compile(r"(?m)^model:[ \t]*" + re.escape(token) + r"[ \t]*(?=\r?\n|$)")
        text = pattern.sub(lambda _m, r=repl: r, text)
    return text


def _sha256_upper_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def file_hash(path: Path) -> str:
    """SHA-256 (uppercase) of raw file bytes — matches PowerShell Get-FileHash."""
    return _sha256_upper_bytes(path.read_bytes())


def _canonicalize_text(text: str) -> str:
    """Strip a leading UTF-8 BOM and normalize all line endings to LF."""
    if text.startswith("\ufeff"):
        text = text[1:]
    return text.replace("\r\n", "\n").replace("\r", "\n")


def resolved_source_bytes(path: Path, af_env_path: Path) -> bytes:
    """The canonical bytes that would be deployed.

    Canonical = UTF-8 without BOM, LF line endings, with agent model-tier tokens
    resolved. Non-UTF-8 (binary) content is returned untouched. Canonicalizing
    here (not just for tier files) makes the deployed bytes byte-identical
    regardless of the source's EOL/BOM, so the two deploy paths (this and
    ``deploy.ps1``/``deploy.sh``) never disagree on otherwise-equal files.
    """
    raw = path.read_bytes()
    try:
        text = raw.decode("utf-8-sig")  # strips a leading UTF-8 BOM if present
    except UnicodeDecodeError:
        return raw  # binary -- never touch
    text = _canonicalize_text(text)
    if _TIER_TOKEN_RE.search(text):
        text = resolve_tier_tokens(text, af_env_path)
    return text.encode("utf-8")


_MANAGED_REGION_RE = re.compile(
    r"(?P<start>^[^\n]*AF:MANAGED:(?P<name>[\w.\-]+):START[^\n]*\n)"
    r"(?P<body>.*?)"
    r"(?P<end>^[^\n]*AF:MANAGED:(?P=name):END[^\n]*$)",
    re.MULTILINE | re.DOTALL,
)


def strip_managed_regions(text: str) -> str:
    """Empty every ``AF:MANAGED`` region body (keep the marker lines).

    Used for classification hashing so project-owned region content never counts
    as a framework change.
    """
    return _MANAGED_REGION_RE.sub(lambda m: m.group("start") + m.group("end"), text)


def _managed_region_bodies(text: str) -> dict[str, str]:
    return {m.group("name"): m.group("body") for m in _MANAGED_REGION_RE.finditer(text)}


def merge_managed_regions(base_text: str, overlay_text: str) -> str:
    """Return ``base_text`` with each region body replaced by ``overlay_text``'s
    same-named region body (transplant project content onto the framework base)."""
    overlay = _managed_region_bodies(overlay_text)

    def _repl(m: re.Match) -> str:
        body = overlay.get(m.group("name"), m.group("body"))
        return m.group("start") + body + m.group("end")

    return _MANAGED_REGION_RE.sub(_repl, base_text)


def _strip_bytes(data: bytes) -> bytes:
    """UTF-8 text with managed regions emptied; binary/region-less bytes unchanged."""
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return data
    stripped = strip_managed_regions(text)
    return stripped.encode("utf-8") if stripped != text else data


def _merge_target_regions(data: bytes, target: Path) -> bytes:
    """Transplant the existing target's managed-region content onto the framework
    base so project-owned regions survive an UPDATE. No-op without regions."""
    if not target.is_file():
        return data
    try:
        merged = merge_managed_regions(data.decode("utf-8"), target.read_text(encoding="utf-8"))
    except UnicodeDecodeError:
        return data
    return merged.encode("utf-8")


def source_hash_resolved(path: Path, af_env_path: Path) -> str:
    """Classification hash of the deployed content: canonical + tier-resolved, with
    managed-region bodies stripped (region content is project-owned, not framework)."""
    return _sha256_upper_bytes(_strip_bytes(resolved_source_bytes(path, af_env_path)))


def _target_classify_hash(path: Path) -> str:
    """Classification hash of a deployed target file (managed regions stripped)."""
    return _sha256_upper_bytes(_strip_bytes(path.read_bytes()))


@dataclass
class Manifest:
    dirs: list[str] = field(default_factory=list)
    root_files: list[str] = field(default_factory=list)
    customizable: set[str] = field(default_factory=set)
    optional: set[str] = field(default_factory=set)
    vscode_files: list[str] = field(default_factory=list)


def parse_manifest(manifest_path: Path) -> Manifest:
    """Parse ``.af-manifest`` (path [ann1, ann2]) into a Manifest.

    Handles ``.github/`` dirs/files and ``[vscode]`` files (deployed to
    ``.vscode/``). Customizable vscode files are keyed ``vscode/<name>`` to match
    the ``.af-hashes`` key scheme used by ``deploy.ps1``.
    """
    m = Manifest()
    dirs: list[str] = []
    files: list[str] = []
    for raw in manifest_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        annotations: list[str] = []
        entry = line
        am = re.match(r"^(.+?)\s+\[(.+)\]\s*$", line)
        if am:
            entry = am.group(1).strip()
            annotations = [a.strip().lower() for a in am.group(2).split(",")]
        is_vscode = "vscode" in annotations
        entry = _norm(entry)
        if entry.endswith("/"):
            dirs.append(entry.rstrip("/"))
        elif is_vscode:
            m.vscode_files.append(entry)
        else:
            files.append(entry)
        if "optional" in annotations:
            m.optional.add(entry)
        if "customizable" in annotations:
            m.customizable.add(f"vscode/{entry}" if is_vscode else entry)
    m.dirs = dirs
    # Root files = manifest files not inside any manifest directory.
    m.root_files = [f for f in files if not any(f.startswith(d + "/") for d in dirs)]
    return m


def _is_ignored_artifact(p: Path) -> bool:
    """Python bytecode caches regenerate on any hook/script test run and must
    never enter the deploy payload."""
    return "__pycache__" in p.parts or p.suffix in (".pyc", ".pyo")


def collect_source_files(source_github: Path, manifest: Manifest) -> list[str]:
    """All deployable .github-relative files (forward-slash keys)."""
    rels: list[str] = []
    for d in manifest.dirs:
        src_dir = source_github / d
        if src_dir.is_dir():
            for p in sorted(src_dir.rglob("*")):
                if p.is_file() and not _is_ignored_artifact(p):
                    rels.append(_norm(str(p.relative_to(source_github))))
    for f in manifest.root_files:
        if (source_github / f).is_file():
            rels.append(f)
    return rels


@dataclass
class Unit:
    """One deployable file: its source, target, ``.af-hashes`` key and display path."""

    source: Path
    target: Path
    hash_key: str
    display: str
    is_custom: bool


def collect_units(source_root: Path, target_dir: Path, manifest: Manifest) -> list[Unit]:
    """All deployable units across ``.github/`` and manifest ``[vscode]`` files.

    Missing ``[vscode]`` source files (e.g. ``[optional]``) are silently skipped,
    mirroring ``deploy.ps1``.
    """
    source_github = source_root / ".github"
    target_github = target_dir / ".github"
    units: list[Unit] = [
        Unit(
            source=source_github / rel,
            target=target_github / rel,
            hash_key=rel,
            display=f".github/{rel}",
            is_custom=rel in manifest.customizable,
        )
        for rel in collect_source_files(source_github, manifest)
    ]
    source_vscode = source_root / ".vscode"
    target_vscode = target_dir / ".vscode"
    for f in manifest.vscode_files:
        src = source_vscode / f
        if not src.is_file():
            continue
        units.append(
            Unit(
                source=src,
                target=target_vscode / f,
                hash_key=f"vscode/{f}",
                display=f".vscode/{f}",
                is_custom=f"vscode/{f}" in manifest.customizable,
            )
        )
    return units


def read_baseline_hashes(target_github: Path) -> dict[str, str]:
    """Read ``.af-hashes`` into {normalized-key: HASH}."""
    hashes: dict[str, str] = {}
    hf = target_github / ".af-hashes"
    if hf.is_file():
        for line in hf.read_text(encoding="utf-8").splitlines():
            m = re.match(r"^([^#=]+)=(.+)$", line)
            if m:
                hashes[_norm(m.group(1).strip())] = m.group(2).strip()
    return hashes


def resolve_source_root(package_dir: Path | None = None) -> Path:
    """Resolve the framework payload root.

    Resolution order: the ``AF_SOURCE_ROOT`` env override (dev / tests), then a
    hash-pinned remote payload (``AF_PAYLOAD_URL`` + ``AF_PAYLOAD_SHA256``,
    governance mode), then a ``payload/`` directory bundled next to the package
    (installed wheel), then the in-repo flavor directory (source checkout).

    Parameters
    ----------
    package_dir:
        Directory of the installed package; defaults to this module's directory.
        Injectable for testing.

    Returns
    -------
    Path
        The resolved payload root (contains ``VERSION`` and ``.github/``).

    Raises
    ------
    ValueError
        If ``AF_PAYLOAD_URL`` is set without a mandatory ``AF_PAYLOAD_SHA256`` pin.
    """
    env = os.environ.get("AF_SOURCE_ROOT")
    if env:
        return Path(env).resolve()
    url = os.environ.get("AF_PAYLOAD_URL")
    if url:
        sha = os.environ.get("AF_PAYLOAD_SHA256")
        if not sha:
            raise ValueError(
                "AF_PAYLOAD_URL is set but AF_PAYLOAD_SHA256 is missing — refusing to fetch an unpinned payload."
            )
        from . import remote_payload

        cache = Path(os.environ.get("AF_PAYLOAD_CACHE") or (Path.home() / ".cache" / "af-deploy-mcp"))
        return remote_payload.fetch_payload(url, sha, cache)
    pkg = (package_dir or Path(__file__).resolve().parent).resolve()
    bundled = pkg / "payload"
    if (bundled / "VERSION").is_file():
        return bundled
    # Dev mode: the flavor directory two levels above the package (…/mcp-deploy/pkg).
    return pkg.parents[1]


def validate_payload(root: Path) -> str | None:
    """Return an error message if ``root`` is not a valid payload, else ``None``."""
    if not (root / "VERSION").is_file():
        return f"Payload invalid: VERSION not found under {root}"
    if not (root / ".github" / ".af-manifest").is_file():
        return f"Payload invalid: .github/.af-manifest not found under {root}"
    return None


def read_version(source_root: Path) -> str:
    vf = source_root / "VERSION"
    return vf.read_text(encoding="utf-8").strip() if vf.is_file() else ""


def read_deployed_version(target_dir: Path) -> str:
    vf = target_dir / ".github" / ".af-version"
    if not vf.is_file():
        return ""
    for line in vf.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*version:\s*(.+)$", line)
        if m:
            return m.group(1).strip()
    return ""


def status(source_root: Path, target_dir: Path) -> dict:
    """Version comparison between the bundled source and the target."""
    src_v = read_version(source_root)
    dep_v = read_deployed_version(target_dir)
    if not dep_v:
        state = "not-deployed"
    elif dep_v == src_v:
        state = "up-to-date"
    else:
        state = "stale"
    return {"source_version": src_v, "deployed_version": dep_v, "state": state}


# 3-way classification identical to deploy.ps1 Publish-SingleFile.
def _classify(is_custom: bool, src_h: str, tgt_h: str | None, baseline: str | None, has_baseline: bool) -> str:
    if tgt_h is None:
        return "CREATE"
    if src_h == tgt_h:
        return "UNCHANGED"
    if baseline:
        af_changed = src_h != baseline
        proj_changed = tgt_h != baseline
        if is_custom:
            if af_changed and proj_changed:
                return "CONFLICT"
            return "PROTECT" if af_changed else "PRESERVE"
        if af_changed and not proj_changed:
            return "UPDATE"
        if not af_changed and proj_changed:
            return "PRESERVE"
        return "CONFLICT"
    if has_baseline:
        return "PROTECT" if is_custom else "UPDATE"
    return "PROTECT" if is_custom else "CONFLICT"


def _is_deactivated_skill_unit(hash_key: str, target_github: Path) -> bool:
    """True if ``hash_key`` is an active-by-default skill file the project has
    deactivated by moving it to ``skills/_available/{name}/``.

    Measure #3: ``/af-curate-skills`` deactivates a skill by *moving* its folder
    into ``_available/`` rather than deleting it. When the framework still ships
    ``skills/{name}/`` but the target has ``skills/_available/{name}/``, the deploy
    treats the framework files as DEACTIVATED (suppressed) instead of re-CREATE-ing
    them on every run.
    """
    parts = _norm(hash_key).split("/")
    if len(parts) < 3 or parts[0] != "skills" or parts[1] == "_available":
        return False
    return (target_github / "skills" / "_available" / parts[1]).is_dir()


def dry_run(source_root: Path, target_dir: Path) -> dict:
    """Classify every deployable file (read-only). Mirrors the deploy dry-run."""
    target_github = target_dir / ".github"
    target_af_env = target_github / "af-env.conf"
    manifest = parse_manifest(source_root / ".github" / ".af-manifest")
    baseline = read_baseline_hashes(target_github)
    has_baseline = len(baseline) > 0
    units = collect_units(source_root, target_dir, manifest)

    results: list[dict] = []
    counts: dict[str, int] = {}
    for u in units:
        src_h = source_hash_resolved(u.source, target_af_env)
        tgt_h = _target_classify_hash(u.target) if u.target.is_file() else None
        cls = _classify(u.is_custom, src_h, tgt_h, baseline.get(u.hash_key), has_baseline)
        if cls == "CREATE" and _is_deactivated_skill_unit(u.hash_key, target_github):
            cls = "DEACTIVATED"
        counts[cls] = counts.get(cls, 0) + 1
        results.append({"path": u.display, "classification": cls, "customizable": u.is_custom})

    return {
        "source_version": read_version(source_root),
        "deployed_version": read_deployed_version(target_dir),
        "total_files": len(units),
        "counts": counts,
        "files": results,
    }


# ── Write path (Phase 1) ────────────────────────────────────────────────────
# All writes stay under the target's ``.github/``; existing files are backed up
# before overwrite; CONFLICT / PROTECT / PRESERVE / [customizable] files are
# never written by ``apply``.


def _write_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def _write_hashes(target_github: Path, hashes: dict[str, str], version: str) -> None:
    lines = [
        "# AF deployment baseline hashes",
        f"# Updated: {datetime.now().isoformat(timespec='seconds')}",
        f"# Version: {version}",
    ]
    lines += [f"{k}={hashes[k]}" for k in sorted(hashes)]
    _write_bytes(target_github / ".af-hashes", ("\n".join(lines) + "\n").encode("utf-8"))


def _write_version(target_dir: Path, version: str) -> None:
    content = f"version: {version}\ndeployed: {datetime.now().isoformat(timespec='seconds')}\nsource: mcp:af-deploy\n"
    _write_bytes(target_dir / ".github" / ".af-version", content.encode("utf-8"))


def _safe_join(base: Path, rel: str) -> Path:
    """Join ``rel`` under ``base``, refusing any path traversal outside ``base``."""
    base = base.resolve()
    target = (base / rel).resolve()
    if base != target and base not in target.parents:
        raise ValueError(f"Refused: '{rel}' resolves outside the workspace.")
    return target


def apply(source_root: Path, target_dir: Path) -> dict:
    """Apply CREATE/UPDATE files only. Backs up first; skips everything else.

    Read-only classes (CONFLICT / PROTECT / PRESERVE / [customizable] / UNCHANGED)
    are never written. Returns applied/skipped lists and the backup directory.
    """
    source_github = source_root / ".github"
    target_github = target_dir / ".github"
    target_af_env = target_github / "af-env.conf"
    manifest = parse_manifest(source_github / ".af-manifest")
    baseline = read_baseline_hashes(target_github)
    has_baseline = len(baseline) > 0
    deployed: dict[str, str] = dict(baseline)
    version = read_version(source_root)

    backup_dir = target_dir / f".af-backup-{datetime.now():%Y%m%d%H%M%S}"
    applied: list[str] = []
    skipped: list[dict] = []
    made_backup = False

    for u in collect_units(source_root, target_dir, manifest):
        data = resolved_source_bytes(u.source, target_af_env)
        src_h = _sha256_upper_bytes(_strip_bytes(data))
        tgt_h = _target_classify_hash(u.target) if u.target.is_file() else None
        cls = _classify(u.is_custom, src_h, tgt_h, baseline.get(u.hash_key), has_baseline)
        if cls == "CREATE" and _is_deactivated_skill_unit(u.hash_key, target_github):
            cls = "DEACTIVATED"
        if cls in ("CREATE", "UPDATE"):
            if u.target.is_file():
                bpath = backup_dir / u.display
                bpath.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(u.target, bpath)
                made_backup = True
            _write_bytes(u.target, _merge_target_regions(data, u.target))
            deployed[u.hash_key] = src_h
            applied.append(u.display)
        elif cls == "UNCHANGED":
            deployed[u.hash_key] = src_h
        else:
            skipped.append({"path": u.display, "classification": cls})

    _write_hashes(target_github, deployed, version)
    _write_version(target_dir, version)
    return {
        "version": version,
        "applied_count": len(applied),
        "applied": applied,
        "skipped": skipped,
        "backup_dir": str(backup_dir) if made_backup else None,
    }


def update_hashes(source_root: Path, target_dir: Path) -> dict:
    """Re-baseline ``.af-hashes`` to the current resolved source (mirror -UpdateHashes)."""
    target_github = target_dir / ".github"
    target_af_env = target_github / "af-env.conf"
    manifest = parse_manifest(source_root / ".github" / ".af-manifest")
    version = read_version(source_root)
    hashes = {
        u.hash_key: source_hash_resolved(u.source, target_af_env)
        for u in collect_units(source_root, target_dir, manifest)
    }
    _write_hashes(target_github, hashes, version)
    return {"entries": len(hashes), "version": version}


def write_resolved(target_dir: Path, rel: str, content: str) -> dict:
    """Write agent-merged content to a ``.github/`` (or ``.vscode/``) file.

    Workspace-scoped: paths escaping the target tree are refused. A bare path is
    ``.github``-relative; a ``.vscode/`` prefix targets the ``.vscode/`` tree.
    """
    p = _norm(rel)
    if p.startswith(".vscode/"):
        base, sub, prefix = target_dir / ".vscode", p[len(".vscode/") :], ".vscode"
    else:
        sub = p[len(".github/") :] if p.startswith(".github/") else p
        base, prefix = target_dir / ".github", ".github"
    path = _safe_join(base, sub)
    data = _canonicalize_text(content).encode("utf-8")
    _write_bytes(path, data)
    return {"path": f"{prefix}/{sub}", "bytes": len(data)}


def _resolve_pair(source_root: Path, target_dir: Path, path: str) -> tuple[Path, Path, str]:
    """Map a deploy path to (source_file, target_file, display).

    ``.vscode/``-prefixed paths map to the ``.vscode/`` trees; everything else is
    ``.github``-relative (an optional ``.github/`` prefix is accepted).
    """
    p = _norm(path)
    if p.startswith(".vscode/"):
        rel = p[len(".vscode/") :]
        return source_root / ".vscode" / rel, target_dir / ".vscode" / rel, f".vscode/{rel}"
    rel = p[len(".github/") :] if p.startswith(".github/") else p
    return source_root / ".github" / rel, target_dir / ".github" / rel, f".github/{rel}"


def conflict_diff(source_root: Path, target_dir: Path, path: str) -> str:
    """Unified diff between the deployed file (project) and the resolved source.

    ``path`` may be ``.github``-relative (default) or carry a ``.vscode/`` prefix.
    """
    src_path, tgt_path, display = _resolve_pair(source_root, target_dir, path)
    target_af_env = target_dir / ".github" / "af-env.conf"
    src_text = resolved_source_bytes(src_path, target_af_env).decode("utf-8", "replace") if src_path.is_file() else ""
    tgt_text = tgt_path.read_text(encoding="utf-8", errors="replace") if tgt_path.is_file() else ""
    return "".join(
        difflib.unified_diff(
            tgt_text.splitlines(keepends=True),
            src_text.splitlines(keepends=True),
            fromfile=f"project/{display}",
            tofile=f"framework/{display}",
        )
    )


def prune_backups(target_dir: Path, days: int) -> dict:
    """Remove ``.af-backup-*`` directories older than ``days``."""
    removed: list[str] = []
    if days > 0:
        cutoff = time.time() - days * 86400
        for p in sorted(target_dir.glob(".af-backup-*")):
            if p.is_dir() and p.stat().st_mtime < cutoff:
                shutil.rmtree(p, ignore_errors=True)
                removed.append(p.name)
    return {"removed": removed}


# ── Orphan detection (framework files left behind by a manifest change) ──────
# An orphan is a path recorded in the target ``.af-hashes`` baseline (so it was
# delivered by a previous deploy) that is no longer a current deployable unit
# — e.g. after a rename or a manifest removal — and still exists on disk.
# Project-created files are never orphans: they are not in the baseline. The
# deploy scripts never remove these; this closes that gap safely.


def _orphan_paths(target_dir: Path, key: str) -> tuple[Path, str]:
    """Map a baseline key to its on-disk path and display path."""
    if key.startswith("vscode/"):
        rel = key[len("vscode/") :]
        return target_dir / ".vscode" / rel, f".vscode/{rel}"
    return target_dir / ".github" / key, f".github/{key}"


def list_orphans(source_root: Path, target_dir: Path) -> list[dict]:
    """List baselined framework files that are no longer deployable and still on disk."""
    target_github = target_dir / ".github"
    manifest = parse_manifest(source_root / ".github" / ".af-manifest")
    current = {u.hash_key for u in collect_units(source_root, target_dir, manifest)}
    baseline = read_baseline_hashes(target_github)
    orphans: list[dict] = []
    for key in sorted(baseline):
        if key in current:
            continue
        disk, display = _orphan_paths(target_dir, key)
        if disk.is_file():
            orphans.append({"path": display, "key": key})
    return orphans


def prune_orphans(source_root: Path, target_dir: Path) -> dict:
    """Back up and delete orphaned framework files, then drop them from ``.af-hashes``."""
    orphans = list_orphans(source_root, target_dir)
    if not orphans:
        return {"removed": [], "backup_dir": None}
    target_github = target_dir / ".github"
    backup_dir = target_dir / f".af-backup-{datetime.now():%Y%m%d%H%M%S}"
    removed: list[str] = []
    for orphan in orphans:
        disk, _ = _orphan_paths(target_dir, orphan["key"])
        bpath = backup_dir / orphan["path"]
        bpath.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(disk, bpath)
        disk.unlink()
        removed.append(orphan["path"])
    orphan_keys = {orphan["key"] for orphan in orphans}
    remaining = {k: v for k, v in read_baseline_hashes(target_github).items() if k not in orphan_keys}
    _write_hashes(target_github, remaining, read_version(source_root))
    return {"removed": removed, "backup_dir": str(backup_dir)}
