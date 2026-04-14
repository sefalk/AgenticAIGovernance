#!/usr/bin/env python3
"""Hard-gate checks for Python type hints, docstrings, and ignore hygiene.

This script is intentionally dependency-free and runs in hook contexts.
"""

from __future__ import annotations

import argparse
import ast
import re
import sys
from pathlib import Path


IGNORE_RE = re.compile(r"#\s*type:\s*ignore(?P<suffix>.*)$")
IGNORE_CODE_RE = re.compile(r"#\s*type:\s*ignore\[[^\]]+\]")
PYRIGHT_IGNORE_RE = re.compile(r"#\s*pyright:\s*ignore(?P<suffix>.*)$", re.IGNORECASE)
NOQA_RE = re.compile(r"#\s*noqa(?P<suffix>.*)$", re.IGNORECASE)
NOQA_CODE_RE = re.compile(r"#\s*noqa:\s*\w+", re.IGNORECASE)


def _collect_public_functions(tree: ast.AST) -> list[tuple[ast.AST, str]]:
    funcs: list[tuple[ast.AST, str]] = []
    for node in getattr(tree, "body", []):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            if not node.name.startswith("_"):
                funcs.append((node, node.name))
        elif isinstance(node, ast.ClassDef):
            for item in node.body:
                if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)) and not item.name.startswith("_"):
                    funcs.append((item, f"{node.name}.{item.name}"))
    return funcs


def _has_full_annotations(func: ast.AST) -> bool:
    args = list(func.args.args) + list(func.args.kwonlyargs)
    if func.args.vararg is not None:
        args.append(func.args.vararg)
    if func.args.kwarg is not None:
        args.append(func.args.kwarg)

    for arg in args:
        if arg.arg in {"self", "cls"}:
            continue
        if arg.annotation is None:
            return False

    if func.returns is None:
        return False
    return True


def _requires_param_section(func: ast.AST) -> bool:
    args = list(func.args.args) + list(func.args.kwonlyargs)
    named = [a for a in args if a.arg not in {"self", "cls"}]
    if func.args.vararg is not None:
        named.append(func.args.vararg)
    if func.args.kwarg is not None:
        named.append(func.args.kwarg)
    return len(named) > 0


def _requires_return_section(func: ast.AST) -> bool:
    ret = func.returns
    if ret is None:
        return False
    if isinstance(ret, ast.Constant) and ret.value is None:
        return False
    if isinstance(ret, ast.Name) and ret.id == "None":
        return False
    return True


def _check_docstring_quality(func: ast.AST, symbol: str) -> list[str]:
    issues: list[str] = []
    doc = ast.get_docstring(func)
    if not doc:
        return [f"{symbol}: missing docstring"]

    stripped = doc.strip()
    if len(stripped) < 20:
        issues.append(f"{symbol}: docstring too short (min 20 chars)")

    if _requires_param_section(func):
        if ("Parameters" not in doc) and ("Args:" not in doc):
            issues.append(f"{symbol}: docstring missing parameter section (Parameters/Args)")

    if _requires_return_section(func):
        if ("Returns" not in doc) and ("Return:" not in doc):
            issues.append(f"{symbol}: docstring missing return section (Returns)")

    return issues


def _check_ignore_hygiene(lines: list[str], file_label: str) -> list[str]:
    issues: list[str] = []
    for idx, line in enumerate(lines, start=1):
        m = IGNORE_RE.search(line)
        if m:
            if not IGNORE_CODE_RE.search(line):
                issues.append(f"{file_label}:{idx}: type ignore must include explicit rule code, e.g. type: ignore[reportGeneralTypeIssues]")
            tail = m.group("suffix")
            parts = tail.split("#", 1)
            if len(parts) < 2 or len(parts[1].strip()) < 8:
                issues.append(f"{file_label}:{idx}: type ignore requires justification comment (min 8 chars)")

        pm = PYRIGHT_IGNORE_RE.search(line)
        if pm:
            tail = pm.group("suffix")
            parts = tail.split("#", 1)
            if len(parts) < 2 or len(parts[1].strip()) < 8:
                issues.append(f"{file_label}:{idx}: pyright ignore requires justification comment (min 8 chars)")

        nq = NOQA_RE.search(line)
        if nq and not IGNORE_RE.search(line) and not PYRIGHT_IGNORE_RE.search(line):
            if not NOQA_CODE_RE.search(line):
                issues.append(f"{file_label}:{idx}: noqa must include explicit rule code, e.g. # noqa: E501")
            tail = nq.group("suffix")
            parts = tail.split("#", 1)
            if len(parts) < 2 or len(parts[1].strip()) < 8:
                issues.append(f"{file_label}:{idx}: noqa requires justification comment (min 8 chars after # noqa: CODE  # reason)")
    return issues


def check_file(path: Path) -> list[str]:
    """Validate one Python file and return policy violations.

    Parameters
    ----------
    path : Path
        Python file path to validate.

    Returns
    -------
    list[str]
        Collected policy violation messages.
    """
    issues: list[str] = []
    try:
        raw = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        raw = path.read_text(encoding="latin-1")

    lines = raw.splitlines()
    issues.extend(_check_ignore_hygiene(lines, str(path)))

    try:
        tree = ast.parse(raw)
    except SyntaxError as exc:
        return [f"{path}:{exc.lineno}: syntax error prevents quality analysis: {exc.msg}"]

    for func, symbol in _collect_public_functions(tree):
        if not _has_full_annotations(func):
            issues.append(f"{path}:{func.lineno}: {symbol}: missing full type annotations (args + return)")
        for issue in _check_docstring_quality(func, f"{path}:{func.lineno}: {symbol}"):
            issues.append(issue)
    return issues


def main() -> int:
    """CLI entry point for hard-gate Python quality validation.

    Returns
    -------
    int
        Process exit code (0 pass, 2 fail).
    """
    parser = argparse.ArgumentParser(description="Hard-gate Python quality checks")
    parser.add_argument("--files", nargs="+", required=True, help="Python files to validate")
    args = parser.parse_args()

    all_issues: list[str] = []
    for file_arg in args.files:
        p = Path(file_arg)
        if not p.exists() or p.suffix != ".py":
            continue
        all_issues.extend(check_file(p))

    if all_issues:
        print("PYTHON_QUALITY_GATE_FAIL")
        for issue in all_issues:
            print(f"- {issue}")
        return 2

    print("PYTHON_QUALITY_GATE_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
