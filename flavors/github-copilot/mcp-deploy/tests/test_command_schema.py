"""Argument schemas declared in a script's header block (#60, owner decision 2026-10-21).

``run_script`` passed ``args`` straight through as argv, so an agent learned a
script's interface only by reading it or by failing. A header block now states
it next to the code it describes -- one source, no sibling manifest to drift:

    # af-command: Lint the given files with ruff.
    # af-arg: FILE...              Files to lint
    # af-arg: [--fix]              Apply fixes
    # af-arg: [--select CODES]     Comma-separated rule codes
    # af-arg: [--format {text|json}]  Output format

``list_scripts`` publishes it and ``run_script`` refuses argv that violates it
before anything is approved or executed. A script without a header keeps the
old contract: argv is passed through unchecked.
"""

# copilot:generated | coordinator | 2026-10-21

from __future__ import annotations

import pytest

from af_deploy_mcp import command_schema as cs

LINT = (
    "#!/usr/bin/env python\n"
    "# af-command: Lint the given files with ruff.\n"
    "# af-arg: FILE...                Files to lint\n"
    "# af-arg: [--fix]                Apply fixes\n"
    "# af-arg: [--select CODES]       Comma-separated rule codes\n"
    "# af-arg: [--format {text|json}]  Output format\n"
    "import sys\n"
)


def _schema(text: str = LINT) -> cs.Schema:
    schema = cs.parse_header(text)
    assert schema is not None
    return schema


# ── parsing ─────────────────────────────────────────────────────────────────


def test_a_script_without_a_header_has_no_schema() -> None:
    assert cs.parse_header("import sys\nprint(sys.argv)\n") is None


def test_the_header_is_parsed_into_description_and_arguments() -> None:
    schema = _schema()
    assert schema.description == "Lint the given files with ruff."
    assert [a.spec for a in schema.args] == ["FILE...", "[--fix]", "[--select CODES]", "[--format {text|json}]"]
    file, fix, select, fmt = schema.args
    assert (file.name, file.required, file.repeat, file.positional) == ("FILE", True, True, True)
    assert (fix.name, fix.required, fix.value, fix.positional) == ("--fix", False, None, False)
    assert (select.value, select.choices) == ("CODES", None)
    assert fmt.choices == ("text", "json")
    assert file.help == "Files to lint"


def test_the_usage_line_is_derived_from_the_specs() -> None:
    assert _schema().usage == "FILE... [--fix] [--select CODES] [--format {text|json}]"


def test_powershell_and_bash_comments_work_the_same() -> None:
    ps1 = "param()\n# af-command: Count lines.\n# af-arg: PATH  The file\n"
    assert [a.name for a in _schema(ps1).args] == ["PATH"]


def test_a_header_after_the_first_forty_lines_is_not_a_header() -> None:
    assert cs.parse_header("x = 1\n" * 40 + "# af-arg: FILE  late\n") is None


@pytest.mark.parametrize(
    ("line", "why"),
    [
        ("# af-arg: FILE", "help"),  # spec and help need two spaces between them
        ("# af-arg: [FILE  Missing bracket", "bracket"),
        ("# af-arg: file  lower-case placeholder", "upper-case"),
        ("# af-arg: [--x {a}]  one choice", "choices"),
    ],
)
def test_a_malformed_line_is_an_error_not_a_silent_skip(line: str, why: str) -> None:
    with pytest.raises(cs.HeaderError, match=why):
        cs.parse_header(f"# af-command: X.\n{line}\n")


def test_a_repeated_positional_must_be_last() -> None:
    with pytest.raises(cs.HeaderError, match="last"):
        cs.parse_header("# af-arg: FILE...  files\n# af-arg: OUT  output\n")


def test_two_descriptions_are_an_error() -> None:
    with pytest.raises(cs.HeaderError, match="af-command"):
        cs.parse_header("# af-command: A.\n# af-command: B.\n")


# ── validation ──────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "argv",
    [
        ["a.py"],
        ["a.py", "b.py", "--fix"],
        ["--fix", "a.py"],
        ["a.py", "--select", "E,F"],
        ["a.py", "--select=E,F"],
        ["a.py", "--format", "json"],
        ["--", "--weird-name.py"],
    ],
)
def test_valid_argv_passes(argv: list[str]) -> None:
    assert cs.validate(_schema(), argv) is None


@pytest.mark.parametrize(
    ("argv", "why"),
    [
        ([], "FILE"),  # required positional missing
        (["a.py", "--force"], "--force"),  # unknown option
        (["a.py", "--select"], "--select"),  # option without its value
        (["a.py", "--select", "--fix"], "--select"),  # an option is not a value
        (["a.py", "--format", "xml"], "xml"),  # outside the choices
        (["a.py", "--fix=yes"], "--fix"),  # a flag takes no value
    ],
)
def test_invalid_argv_is_refused_with_the_reason(argv: list[str], why: str) -> None:
    reason = cs.validate(_schema(), argv)
    assert reason is not None
    assert why in reason
    assert "usage:" in reason


def test_too_many_positionals_are_refused() -> None:
    schema = _schema("# af-arg: PATH  one file\n")
    assert "unexpected" in (cs.validate(schema, ["a", "b"]) or "")


def test_a_required_option_must_be_given() -> None:
    schema = _schema("# af-arg: --out PATH  where to write\n")
    assert "--out" in (cs.validate(schema, []) or "")
    assert cs.validate(schema, ["--out", "x"]) is None


def test_a_script_with_only_a_description_takes_no_arguments() -> None:
    schema = _schema("# af-command: No arguments.\n")
    assert cs.validate(schema, []) is None
    assert "unexpected" in (cs.validate(schema, ["x"]) or "")


def test_schema_serialises_for_list_scripts() -> None:
    data = _schema().to_dict()
    assert data["usage"] == "FILE... [--fix] [--select CODES] [--format {text|json}]"
    assert data["args"][3] == {
        "spec": "[--format {text|json}]",
        "name": "--format",
        "required": False,
        "repeat": False,
        "value": "{text|json}",
        "choices": ["text", "json"],
        "help": "Output format",
    }
