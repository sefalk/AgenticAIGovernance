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

import hashlib
import re
from dataclasses import dataclass, field
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


def source_hash_resolved(path: Path, af_env_path: Path) -> str:
    """Hash of the *deployed* content: resolved bytes for tier files, raw otherwise."""
    raw = path.read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return _sha256_upper_bytes(raw)
    if not _TIER_TOKEN_RE.search(text):
        return _sha256_upper_bytes(raw)
    resolved = resolve_tier_tokens(text, af_env_path)
    return _sha256_upper_bytes(resolved.encode("utf-8"))


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
