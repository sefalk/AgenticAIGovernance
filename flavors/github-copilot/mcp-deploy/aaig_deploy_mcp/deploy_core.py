"""Read-only AAIG deploy logic for the MCP PoC.

Mirrors the read-only half of ``deploy.ps1`` / ``deploy.sh`` (version status and
the 3-way dry-run classification, including agent model-tier resolution) so an
MCP server can expose ``af_status`` and ``af_dry_run`` *without* touching the
target repository. No writes happen here — this module only reads and compares.

Hash format matches the PowerShell deploy: SHA-256, uppercase hex. Tier files
are hashed over their resolved UTF-8 (no BOM) bytes, exactly like
``Get-StringHashUpper`` in ``deploy.ps1``. Path keys are normalized to forward
slashes so a baseline written by either the ``.ps1`` (Windows, backslashes) or
``.sh`` (POSIX, forward slashes) deploy compares consistently.
"""

# copilot:generated | implementer | 2026-07-07

from __future__ import annotations

import difflib
import hashlib
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


def resolved_source_bytes(path: Path, af_env_path: Path) -> bytes:
    """The exact bytes that would be deployed: resolved for tier files, raw otherwise."""
    raw = path.read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw
    if not _TIER_TOKEN_RE.search(text):
        return raw
    return resolve_tier_tokens(text, af_env_path).encode("utf-8")


def source_hash_resolved(path: Path, af_env_path: Path) -> str:
    """Hash of the *deployed* content: resolved bytes for tier files, raw otherwise."""
    return _sha256_upper_bytes(resolved_source_bytes(path, af_env_path))


@dataclass
class Manifest:
    dirs: list[str] = field(default_factory=list)
    root_files: list[str] = field(default_factory=list)
    customizable: set[str] = field(default_factory=set)
    optional: set[str] = field(default_factory=set)


def parse_manifest(manifest_path: Path) -> Manifest:
    """Parse ``.af-manifest`` (path [ann1, ann2]) into a Manifest.

    Only ``.github/`` entries are handled by this PoC; ``[vscode]`` files are
    skipped (a Phase-1 item).
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
        if "vscode" in annotations:
            continue  # PoC scope: .github only
        entry = _norm(entry)
        if entry.endswith("/"):
            dirs.append(entry.rstrip("/"))
        else:
            files.append(entry)
        if "customizable" in annotations:
            m.customizable.add(entry)
        if "optional" in annotations:
            m.optional.add(entry)
    m.dirs = dirs
    # Root files = manifest files not inside any manifest directory.
    m.root_files = [f for f in files if not any(f.startswith(d + "/") for d in dirs)]
    return m


def collect_source_files(source_github: Path, manifest: Manifest) -> list[str]:
    """All deployable .github-relative files (forward-slash keys)."""
    rels: list[str] = []
    for d in manifest.dirs:
        src_dir = source_github / d
        if src_dir.is_dir():
            for p in sorted(src_dir.rglob("*")):
                if p.is_file():
                    rels.append(_norm(str(p.relative_to(source_github))))
    for f in manifest.root_files:
        if (source_github / f).is_file():
            rels.append(f)
    return rels


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


def dry_run(source_root: Path, target_dir: Path) -> dict:
    """Classify every deployable file (read-only). Mirrors the deploy dry-run."""
    source_github = source_root / ".github"
    target_github = target_dir / ".github"
    target_af_env = target_github / "af-env.conf"
    manifest = parse_manifest(source_github / ".af-manifest")
    baseline = read_baseline_hashes(target_github)
    has_baseline = len(baseline) > 0
    rels = collect_source_files(source_github, manifest)

    results: list[dict] = []
    counts: dict[str, int] = {}
    for rel in rels:
        src = source_github / rel
        tgt = target_github / rel
        is_custom = rel in manifest.customizable
        src_h = source_hash_resolved(src, target_af_env)
        tgt_h = file_hash(tgt) if tgt.is_file() else None
        cls = _classify(is_custom, src_h, tgt_h, baseline.get(rel), has_baseline)
        counts[cls] = counts.get(cls, 0) + 1
        results.append({"path": f".github/{rel}", "classification": cls, "customizable": is_custom})

    return {
        "source_version": read_version(source_root),
        "deployed_version": read_deployed_version(target_dir),
        "total_files": len(rels),
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
    content = (
        f"version: {version}\n"
        f"deployed: {datetime.now().isoformat(timespec='seconds')}\n"
        f"source: mcp:aaig-deploy\n"
    )
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

    for rel in collect_source_files(source_github, manifest):
        src = source_github / rel
        tgt = target_github / rel
        is_custom = rel in manifest.customizable
        data = resolved_source_bytes(src, target_af_env)
        src_h = _sha256_upper_bytes(data)
        tgt_h = file_hash(tgt) if tgt.is_file() else None
        cls = _classify(is_custom, src_h, tgt_h, baseline.get(rel), has_baseline)
        if cls in ("CREATE", "UPDATE"):
            if tgt.is_file():
                bpath = backup_dir / ".github" / rel
                bpath.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(tgt, bpath)
                made_backup = True
            _write_bytes(tgt, data)
            deployed[rel] = src_h
            applied.append(f".github/{rel}")
        elif cls == "UNCHANGED":
            deployed[rel] = src_h
        else:
            skipped.append({"path": f".github/{rel}", "classification": cls})

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
    source_github = source_root / ".github"
    target_github = target_dir / ".github"
    target_af_env = target_github / "af-env.conf"
    manifest = parse_manifest(source_github / ".af-manifest")
    version = read_version(source_root)
    hashes = {
        rel: source_hash_resolved(source_github / rel, target_af_env)
        for rel in collect_source_files(source_github, manifest)
    }
    _write_hashes(target_github, hashes, version)
    return {"entries": len(hashes), "version": version}


def write_resolved(target_dir: Path, rel: str, content: str) -> dict:
    """Write agent-merged content to a ``.github/`` file (workspace-scoped)."""
    path = _safe_join(target_dir / ".github", rel)
    data = content.encode("utf-8")
    _write_bytes(path, data)
    return {"path": f".github/{rel}", "bytes": len(data)}


def conflict_diff(source_root: Path, target_dir: Path, rel: str) -> str:
    """Unified diff between the deployed file (project) and the resolved source."""
    source_github = source_root / ".github"
    target_github = target_dir / ".github"
    target_af_env = target_github / "af-env.conf"
    src_text = resolved_source_bytes(source_github / rel, target_af_env).decode("utf-8", "replace")
    tgt_path = target_github / rel
    tgt_text = tgt_path.read_text(encoding="utf-8", errors="replace") if tgt_path.is_file() else ""
    return "".join(
        difflib.unified_diff(
            tgt_text.splitlines(keepends=True),
            src_text.splitlines(keepends=True),
            fromfile=f"project/.github/{rel}",
            tofile=f"framework/.github/{rel}",
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
