#!/usr/bin/env python3
"""Hard-gate checks for Python type hints, docstrings, and ignore hygiene.

This script is intentionally dependency-free and runs in hook contexts.
"""

from __future__ import annotations

import argparse
import ast
import re
import subprocess
import sys
from pathlib import Path


IGNORE_RE = re.compile(r"#\s*type:\s*ignore(?P<suffix>.*)$")
IGNORE_CODE_RE = re.compile(r"#\s*type:\s*ignore\[[^\]]+\]")
PYRIGHT_IGNORE_RE = re.compile(r"#\s*pyright:\s*ignore(?P<suffix>.*)$", re.IGNORECASE)
NOQA_RE = re.compile(r"#\s*noqa(?P<suffix>.*)$", re.IGNORECASE)
NOQA_CODE_RE = re.compile(r"#\s*noqa:\s*\w+", re.IGNORECASE)
SUPPRESSION_RE = re.compile(r"#\s*(?:type:\s*ignore|pyright:\s*ignore|noqa)\b.*$", re.IGNORECASE)
HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")

# Sentinel for "the whole file is new", used where the base has no such blob.
WHOLE_FILE: tuple[int, int] = (1, 1 << 30)


def _git(args: list[str]) -> tuple[int, str]:
    """Run a git command in the current working directory.

    Parameters
    ----------
    args : list[str]
        Arguments after the ``git`` executable.

    Returns
    -------
    tuple[int, str]
        Exit code and captured stdout (empty if git is unavailable).
    """
    try:
        proc = subprocess.run(
            ["git", *args],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    except OSError:
        return 1, ""
    return proc.returncode, proc.stdout


def resolve_base(ref: str) -> tuple[str | None, str | None]:
    """Resolve a base ref to a commit, without deciding what the base should be.

    Base-branch *policy* lives in the stop hooks, which already resolve
    ``merge-base(HEAD, BASE_BRANCH)``. This only looks the given ref up, so the
    framework keeps a single resolver.

    Parameters
    ----------
    ref : str
        Commit-ish supplied by the caller.

    Returns
    -------
    tuple[str | None, str | None]
        The resolved commit, or None plus a notice explaining the fallback.
    """
    code, _ = _git(["rev-parse", "--is-inside-work-tree"])
    if code != 0:
        return None, f"not a git repository; --diff-base {ref} cannot be applied"

    for candidate in (ref, f"origin/{ref}"):
        code, out = _git(["rev-parse", "--verify", "--quiet", f"{candidate}^{{commit}}"])
        if code == 0 and out.strip():
            return out.strip(), None

    return None, f"base ref '{ref}' does not resolve (shallow clone or missing branch)"


def changed_ranges(path: Path, base: str) -> list[tuple[int, int]]:
    """Derive the line ranges a branch changed in one file.

    Compares the base commit against the working tree, so changes that are
    still uncommitted count. A file absent from the base is entirely new.

    Parameters
    ----------
    path : Path
        File to inspect, relative to the repository root.
    base : str
        Resolved base commit.

    Returns
    -------
    list[tuple[int, int]]
        Inclusive ``(start, end)`` line ranges in the working-tree file.
    """
    posix = path.as_posix()

    # An untracked file is absent from every diff, so the diff cannot speak for
    # it. A file that is merely absent from the base needs no special case:
    # `git diff` already reports it as wholly added.
    code, _ = _git(["ls-files", "--error-unmatch", "--", posix])
    if code != 0:
        return [WHOLE_FILE]

    code, out = _git(["diff", "--unified=0", base, "--", posix])
    if code != 0:
        return [WHOLE_FILE]

    ranges: list[tuple[int, int]] = []
    for line in out.splitlines():
        m = HUNK_RE.match(line)
        if not m:
            continue
        start = int(m.group(1))
        count = int(m.group(2)) if m.group(2) is not None else 1
        if count == 0:
            # Pure deletion: lines vanished after `start`. Attribute it to the
            # surrounding code, or removing a function body would go unnoticed.
            ranges.append((start, start + 1))
        else:
            ranges.append((start, start + count - 1))
    return ranges


def _intersects(start: int, end: int, ranges: list[tuple[int, int]] | None) -> bool:
    if ranges is None:
        return True
    return any(not (end < lo or start > hi) for lo, hi in ranges)


def base_text(path: Path, base: str) -> str | None:
    """Read a file as it stands in the base commit.

    Parameters
    ----------
    path : Path
        File path relative to the repository root.
    base : str
        Resolved base commit.

    Returns
    -------
    str | None
        The base contents, or None if the base has no such blob.
    """
    code, out = _git(["show", f"{base}:{path.as_posix()}"])
    if code != 0:
        return None
    return out


def _normalise_docstrings(tree: ast.AST) -> ast.AST:
    """Collapse whitespace inside every docstring of a parsed module.

    Formatters re-indent docstrings when a definition's nesting changes, and
    that lands in the AST as a different string constant. Collapsing runs of
    whitespace keeps re-indentation out of the comparison while leaving the
    words -- the part a human would have had to write -- intact.

    Parameters
    ----------
    tree : ast.AST
        Parsed module, modified in place.

    Returns
    -------
    ast.AST
        The same tree, for chaining.
    """
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        body = getattr(node, "body", None)
        if not body:
            continue
        first = body[0]
        if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str):
            first.value.value = " ".join(first.value.value.split())
    return tree


def _ast_signature(source: str) -> str | None:
    """Reduce source to a text-independent signature of what it means.

    ``ast.dump`` omits line and column attributes by default, so reflowing,
    re-quoting and re-bracketing all leave the signature untouched.

    Parameters
    ----------
    source : str
        Python source text.

    Returns
    -------
    str | None
        The signature, or None if the source does not parse.
    """
    try:
        tree = ast.parse(source)
    except (SyntaxError, ValueError):
        return None
    return ast.dump(_normalise_docstrings(tree))


def is_authored(path: Path, base: str) -> bool:
    """Decide whether a branch actually wrote anything in a file.

    Diff scope answers a different question -- which lines moved -- and a
    formatter moves all of them. Gates that are about authorship (provenance,
    docstrings, type hints) need this one instead, or a mechanical repo-wide
    reformat forces an agent to author content it has no reason to write.

    Undecidable means authored: no base blob, an unparseable file on either
    side, or git unable to answer. Failing the other way would hand every
    authorship gate an off switch.

    Parameters
    ----------
    path : Path
        File path relative to the repository root.
    base : str
        Resolved base commit.

    Returns
    -------
    bool
        True if the file carries authored change, or if that cannot be decided.
    """
    before = base_text(path, base)
    if before is None:
        return True

    try:
        after = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return True

    base_sig = _ast_signature(before)
    head_sig = _ast_signature(after)
    if base_sig is None or head_sig is None:
        return True
    return base_sig != head_sig


def _suppression_signature(line: str) -> str | None:
    """Reduce a suppression comment to a form a reformat cannot change."""
    m = SUPPRESSION_RE.search(line)
    if not m:
        return None
    return " ".join(m.group(0).split())


def _inherited_suppressions(base_lines: list[str] | None) -> dict[str, int]:
    """Count the suppressions a file already carried in the base commit."""
    counts: dict[str, int] = {}
    for line in base_lines or []:
        sig = _suppression_signature(line)
        if sig is not None:
            counts[sig] = counts.get(sig, 0) + 1
    return counts


def _func_span(func: ast.AST) -> tuple[int, int]:
    start = func.lineno
    for dec in getattr(func, "decorator_list", []):
        start = min(start, dec.lineno)
    end = getattr(func, "end_lineno", None) or func.lineno
    return start, end


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


def _check_ignore_hygiene(
    lines: list[str],
    file_label: str,
    base_lines: list[str] | None = None,
) -> tuple[list[str], list[str]]:
    """Check suppression hygiene, splitting branch-owned from inherited hits.

    Ownership is decided by the suppression itself, not by which lines moved.
    A reformat rewrites the line an inherited suppression sits on, so line-range
    scoping would call it branch-owned and demand a justification for a comment
    the agent never wrote. Conversely a suppression the branch adds is absent
    from the base whatever the formatter did around it -- which is why the
    AST-based authorship filter must not be applied to this check: comments do
    not appear in an AST at all.

    Parameters
    ----------
    lines : list[str]
        File contents, one entry per line.
    file_label : str
        Prefix used in messages.
    base_lines : list[str] | None
        The file's contents in the base commit, or None when there is no base
        to compare against, in which case every suppression counts as owned.

    Returns
    -------
    tuple[list[str], list[str]]
        Blocking issues on branch-owned suppressions, advisories on inherited ones.
    """
    issues: list[str] = []
    advisories: list[str] = []
    inherited = _inherited_suppressions(base_lines)
    for idx, line in enumerate(lines, start=1):
        sig = _suppression_signature(line)
        if sig is not None and inherited.get(sig, 0) > 0:
            inherited[sig] -= 1
            sink = advisories
        else:
            sink = issues
        m = IGNORE_RE.search(line)
        if m:
            if not IGNORE_CODE_RE.search(line):
                sink.append(f"{file_label}:{idx}: type ignore must include explicit rule code, e.g. type: ignore[reportGeneralTypeIssues]")
            tail = m.group("suffix")
            parts = tail.split("#", 1)
            if len(parts) < 2 or len(parts[1].strip()) < 8:
                sink.append(f"{file_label}:{idx}: type ignore requires justification comment (min 8 chars)")

        pm = PYRIGHT_IGNORE_RE.search(line)
        if pm:
            tail = pm.group("suffix")
            parts = tail.split("#", 1)
            if len(parts) < 2 or len(parts[1].strip()) < 8:
                sink.append(f"{file_label}:{idx}: pyright ignore requires justification comment (min 8 chars)")

        nq = NOQA_RE.search(line)
        if nq and not IGNORE_RE.search(line) and not PYRIGHT_IGNORE_RE.search(line):
            if not NOQA_CODE_RE.search(line):
                sink.append(f"{file_label}:{idx}: noqa must include explicit rule code, e.g. # noqa: E501")
            tail = nq.group("suffix")
            parts = tail.split("#", 1)
            if len(parts) < 2 or len(parts[1].strip()) < 8:
                sink.append(f"{file_label}:{idx}: noqa requires justification comment (min 8 chars after # noqa: CODE  # reason)")
    return issues, advisories


def check_file(
    path: Path,
    checks: str = "all",
    ranges: list[tuple[int, int]] | None = None,
    base_lines: list[str] | None = None,
    authored: bool = True,
) -> tuple[list[str], list[str]]:
    """Validate one Python file and return policy violations.

    Parameters
    ----------
    path : Path
        Python file path to validate.
    checks : str
        ``all`` for every check, ``ignore-hygiene`` to skip the type-hint and
        docstring rules, which do not apply to test functions.
    ranges : list[tuple[int, int]] | None
        Changed line ranges. None means the whole file is in scope, which is
        the behaviour when no base ref was supplied.
    base_lines : list[str] | None
        The file's contents in the base commit, used to tell inherited
        suppressions from ones the branch introduced.
    authored : bool
        False when the file's meaning is identical to the base, i.e. the change
        is mechanical. Type hints and docstrings are then out of scope; the
        suppression check still runs, since comments leave no AST trace.

    Returns
    -------
    tuple[list[str], list[str]]
        Blocking violations, and advisories for pre-existing suppressions.
    """
    issues: list[str] = []
    try:
        raw = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        raw = path.read_text(encoding="latin-1")

    lines = raw.splitlines()
    hygiene_issues, advisories = _check_ignore_hygiene(lines, str(path), base_lines)
    issues.extend(hygiene_issues)

    if checks == "ignore-hygiene" or not authored:
        return issues, advisories

    try:
        tree = ast.parse(raw)
    except SyntaxError as exc:
        return [f"{path}:{exc.lineno}: syntax error prevents quality analysis: {exc.msg}"], advisories

    for func, symbol in _collect_public_functions(tree):
        start, end = _func_span(func)
        if not _intersects(start, end, ranges):
            continue
        if not _has_full_annotations(func):
            issues.append(f"{path}:{func.lineno}: {symbol}: missing full type annotations (args + return)")
        for issue in _check_docstring_quality(func, f"{path}:{func.lineno}: {symbol}"):
            issues.append(issue)
    return issues, advisories


def main() -> int:
    """CLI entry point for hard-gate Python quality validation.

    Returns
    -------
    int
        Process exit code (0 pass, 2 fail).
    """
    parser = argparse.ArgumentParser(description="Hard-gate Python quality checks")
    parser.add_argument("--files", nargs="+", required=True, help="Python files to validate")
    parser.add_argument(
        "--checks",
        choices=("all", "ignore-hygiene"),
        default="all",
        help="Which checks to run. Callers pass ignore-hygiene for test files, where type hints and docstrings do not apply.",
    )
    parser.add_argument(
        "--diff-base",
        default=None,
        help=(
            "Commit-ish to diff against. Restricts type-hint and docstring "
            "reporting to functions the branch actually changed. Without it "
            "the whole file is reported, which is the historical behaviour."
        ),
    )
    parser.add_argument(
        "--list-authored",
        action="store_true",
        help=(
            "Report which of the given files carry authored change rather than "
            "a mechanical one, one path per line, and run no checks. Hooks use "
            "this to scope authorship gates such as provenance markers. Without "
            "--diff-base there is nothing to compare against and every file is "
            "reported."
        ),
    )
    args = parser.parse_args()

    notices: list[str] = []
    base: str | None = None
    if args.diff_base:
        base, notice = resolve_base(args.diff_base)
        if notice:
            notices.append(f"{notice}; reporting the whole file instead")

    if args.list_authored:
        for file_arg in args.files:
            p = Path(file_arg)
            if not p.exists() or p.suffix != ".py":
                continue
            if base is None or is_authored(p, base):
                print(file_arg)
        return 0

    all_issues: list[str] = []
    all_advisories: list[str] = []
    for file_arg in args.files:
        p = Path(file_arg)
        if not p.exists() or p.suffix != ".py":
            continue
        ranges = changed_ranges(p, base) if base else None
        before = base_text(p, base) if base else None
        authored = is_authored(p, base) if base else True
        issues, advisories = check_file(
            p,
            args.checks,
            ranges,
            before.splitlines() if before is not None else None,
            authored,
        )
        all_issues.extend(issues)
        all_advisories.extend(advisories)

    for notice in notices:
        print(f"NOTICE: {notice}")
    for advisory in all_advisories:
        print(f"ADVISORY: {advisory}")

    if all_issues:
        print("PYTHON_QUALITY_GATE_FAIL")
        for issue in all_issues:
            print(f"- {issue}")
        return 2

    print("PYTHON_QUALITY_GATE_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
