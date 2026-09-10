#!/usr/bin/env python3
"""Report files an agent CREATED at the repository root that nobody asked for.

Issue #123, suggested direction 3: have the stop hook diff the working tree
against the declared in-scope file list rather than trusting the agent's
self-report. The incident that opened the issue was a test-writer that dropped
`run_wit3103_tests.py` into the repository root -- a throwaway runner, never
requested, never mentioned in its return, and found only because the
coordinator happened to run `git status` by hand.

WHERE THE DECLARED SCOPE COMES FROM. The editor writes the delegation prompt
verbatim into the subagent log as a `user_message` span, one per invocation.
That is the coordinator's own words, machine-recorded, never round-tripped
through a model -- the same channel and the same principle as
`concurrent-agent-edits` (#101) and `collect-agent-invocations` (#173): a value
a model can get wrong should be measured, not requested.

WHY THE RULE IS THIS NARROW. Measured over 815 real subagent logs, 334 of which
wrote files at all:

  * "wrote a file the prompt never names" fires on 52 of 334 runs (15.6%), and
    most of those are legitimate -- documenter plan and retro files whose names
    it derives, new test files, `.vscode/tasks.json`. A gate with that false
    positive rate gets switched off, and a hook nobody runs protects nothing
    (#108). Rejected.

  * "CREATED, directly at the repository root, and never named in the prompt"
    fires 6 times with no false positives. All 6 are the pathology, including
    `run_wit3103_tests.py` itself. The other five are `.verify_assertions.py`,
    `.verify_test_file.py`, `check_unit_values.py`, `test_syntax_check.py` and
    `verify_mask_fix.py` -- every one a scratch verification script.

Both clauses earn their place, and they are deliberately redundant:

  * The *created* clause carries the rule on its own. The five legitimate root
    writes in the sample (`.gitignore`, `azure-pipelines.yml`, `databricks.yml`,
    `pyproject.toml`, `tox.ini`) all arrived through `replace_string_in_file`
    against a file that already existed. This matters more than it looks: the
    delegation prompt is capped at ~5000 characters and 342 of 814 sampled
    prompts (42%) end in `[truncated]`, so a name that appears only in the
    severed tail reads as "never named". Truncation can therefore produce false
    positives but never false negatives, and the created clause is immune to it.

  * The *unnamed* clause keeps a legitimately requested new root file -- a task
    that genuinely says "create CHANGELOG.md" -- out of the report.

WHAT THIS IS NOT. Not a general scope check. A file created in a subdirectory
is not reported however undeclared it is, because subdirectories are where
legitimate deliverables live and the measurement says so. The repository root
is special: it is the one directory where a project's files are enumerable, and
nothing an agent invents belongs there.

Every failure to measure -- no session directory, no log, an unreadable log, a
log with no `user_message` -- reports nothing and exits 1. The caller must treat
that as "no finding", never as "clean": a guard that cannot see must not block,
or a missing interpreter becomes an outage.

Stdlib only, on purpose -- a gate that needs `pip install` stops being run.

Usage:
    undeclared-scratch.py --session-dir <dir> --agent <name>
                          [--repo-root <path>]

Output:
    Repo-root-relative file names, one per line -- files the agent created at
    the repository root that the delegation prompt never mentions.

Exit codes:
    0  a measurement was made (the list may be empty -- nothing to report)
    1  nothing measurable; the caller must not treat this as a pass
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

from _agentlog import TOOL_CALL_HINT, find_own_log, harvest_paths

# Cheap prefilter so a large log is not JSON-parsed line by line.
USER_MESSAGE_HINT = b'"user_message"'

# Creation only. `replace_string_in_file` and friends are deliberately absent:
# editing a file that already exists at the root is how the legitimate cases in
# the sample behaved, and including them is what pulls prompt truncation into
# the false positive path.
CREATE_TOOLS = frozenset(
    {
        "create_file",
        "create_directory",
        "create_new_jupyter_notebook",
        "createFile",
        "createDirectory",
        "createDir",
        "writeFile",
    }
)

# Covers a tool that does not exist yet -- a creating verb plus a file noun.
# `replace_string_in_file` carries no creating verb and `create_and_run_task`
# no file noun, so neither is caught.
CREATE_VERB = re.compile(r"create|write", re.IGNORECASE)
CREATE_NOUN = re.compile(r"file|notebook|dir", re.IGNORECASE)


def is_create_tool(name: object) -> bool:
    if not isinstance(name, str) or not name:
        return False
    if name in CREATE_TOOLS:
        return True
    return bool(CREATE_VERB.search(name) and CREATE_NOUN.search(name))


def scan(path: str) -> tuple[str | None, set[str]]:
    """One pass over a subagent log: the delegation prompt and created paths."""
    prompt: str | None = None
    created: set[str] = set()
    try:
        with open(path, "rb") as handle:
            for raw in handle:
                is_user = prompt is None and USER_MESSAGE_HINT in raw
                if not is_user and TOOL_CALL_HINT not in raw:
                    continue
                try:
                    span = json.loads(raw.decode("utf-8", "replace"))
                except (ValueError, UnicodeDecodeError):
                    continue
                if not isinstance(span, dict):
                    continue
                attrs = span.get("attrs")
                if not isinstance(attrs, dict):
                    continue
                if span.get("type") == "user_message":
                    if prompt is None and isinstance(attrs.get("content"), str):
                        prompt = attrs["content"]
                    continue
                if span.get("type") != "tool_call":
                    continue
                if not is_create_tool(span.get("name")):
                    continue
                args = attrs.get("args")
                if isinstance(args, str):
                    try:
                        args = json.loads(args)
                    except ValueError:
                        continue
                harvest_paths(args, created)
    except OSError:
        return None, set()
    return prompt, created


def root_level(paths: set[str], repo_root: str) -> set[str]:
    """Names of paths sitting directly in the repository root, nothing deeper."""
    root = os.path.normcase(os.path.abspath(repo_root))
    out: set[str] = set()
    for raw in paths:
        absolute = os.path.normcase(os.path.abspath(raw))
        if absolute == root:
            continue
        if not absolute.startswith(root + os.sep):
            continue
        relative = os.path.relpath(absolute, root)
        if os.sep in relative or "/" in relative:
            continue
        out.add(os.path.basename(raw))
    return out


def undeclared(created: set[str], prompt: str) -> list[str]:
    """Root-level creations whose name the delegation prompt never mentions.

    Matched on the bare name rather than the full path: the prompt writes
    repo-relative paths and the tool call writes absolute ones, so comparing
    paths would report every file. A bare-name match is the permissive
    direction, which is the right way to be wrong here.
    """
    return sorted(name for name in created if not re.search(re.escape(name), prompt))


def main() -> int:
    parser = argparse.ArgumentParser(description="Report undeclared repo-root creations.")
    parser.add_argument("--session-dir", required=True)
    parser.add_argument("--agent", required=True)
    parser.add_argument("--repo-root", default=".")
    args = parser.parse_args()

    log = find_own_log(args.session_dir, args.agent)
    if log is None:
        return 1

    prompt, created = scan(log)
    if prompt is None:
        # No delegation prompt means no declared scope to diff against. Saying
        # "nothing found" here would be a lie the caller cannot detect.
        return 1

    for name in undeclared(root_level(created, args.repo_root), prompt):
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
