"""Hatch build hook: stamp the bundled payload with the commit it was built from (#429).

The wheel's payload is a copy, not a git checkout, so ``deploy_core.source_commit``
cannot ask git where it came from. This hook asks at build time, when the
framework checkout is still next to it, and writes the answer into the payload
as ``SOURCE_COMMIT``. An empty answer (no git, untracked VERSION) writes nothing.
"""

# copilot:generated | implementer | 2026-10-22

from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path

from hatchling.builders.hooks.plugin.interface import BuildHookInterface

_STAMP_DEST = "af_deploy_mcp/payload/SOURCE_COMMIT"
_PAYLOAD_DEST = "af_deploy_mcp/payload"
_PAYLOAD_TREES = (".github", ".vscode")


def _deploy_core():
    # Loaded by path: the package is not importable while it is being built.
    core = Path(__file__).resolve().parent / "af_deploy_mcp" / "deploy_core.py"
    spec = importlib.util.spec_from_file_location("_af_deploy_core_build", core)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module  # @dataclass resolves its module through sys.modules
    spec.loader.exec_module(module)
    return module


def _source_commit(payload_root: Path) -> str:
    core = _deploy_core()
    return core.source_commit(payload_root) if core else ""


def _payload_force_include(payload_root: Path) -> dict[str, str]:
    """Source file -> wheel path for the bundled payload trees, minus what git ignores (#454)."""
    core = _deploy_core()
    ignored = core.git_ignored_files(payload_root) if core else set()
    mapping: dict[str, str] = {}
    for tree in _PAYLOAD_TREES:
        for p in sorted((payload_root / tree).rglob("*")):
            if not p.is_file() or (core and core._is_ignored_artifact(p)):
                continue
            rel = p.relative_to(payload_root).as_posix()
            if rel not in ignored:
                mapping[str(p)] = f"{_PAYLOAD_DEST}/{rel}"
    return mapping


class SourceCommitHook(BuildHookInterface):
    PLUGIN_NAME = "custom"

    def initialize(self, version: str, build_data: dict) -> None:
        payload_root = Path(self.root).resolve().parent
        force_include = build_data.setdefault("force_include", {})
        force_include.update(_payload_force_include(payload_root))
        commit = _source_commit(payload_root)
        if not commit:
            return
        stamp = Path(tempfile.mkdtemp(prefix="af-source-commit-")) / "SOURCE_COMMIT"
        stamp.write_text(commit + "\n", encoding="utf-8")
        force_include[str(stamp)] = _STAMP_DEST
