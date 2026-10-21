"""Argument schemas declared in a script's header block (#60).

A script states its interface in comment lines near the top, in the usage-line
notation people already read::

    # af-command: Lint the given files with ruff.
    # af-arg: FILE...                 Files to lint
    # af-arg: [--fix]                 Apply fixes
    # af-arg: [--select CODES]        Comma-separated rule codes
    # af-arg: [--format {text|json}]  Output format

Spec and help are separated by two or more spaces. ``[...]`` marks an optional
argument, ``NAME...`` a repeated positional (last only), ``--opt VALUE`` an
option with a value, ``{a|b}`` a closed set of values. A malformed line is an
error, never a silent skip: a header that half-applies is worse than none.
"""

# copilot:generated | coordinator | 2026-10-21

from __future__ import annotations

import re
from dataclasses import dataclass, field

HEADER_LINES = 40

_LINE = re.compile(r"^\s*#\s*af-(?P<kind>command|arg):\s*(?P<body>.*?)\s*$")
_SPEC_HELP = re.compile(r"^(?P<spec>\S.*?)(?:\s{2,}|\t+)(?P<help>\S.*)$")
_PLACEHOLDER = re.compile(r"^[A-Z][A-Z0-9_]*$")
_CHOICES = re.compile(r"^\{(?P<items>[^{}]+)\}$")
_NUMBER = re.compile(r"^-\d+(\.\d+)?$")


class HeaderError(ValueError):
    """The header block is present but cannot be read."""


@dataclass(frozen=True)
class Arg:
    spec: str
    name: str
    required: bool
    repeat: bool
    value: str | None
    choices: tuple[str, ...] | None
    help: str

    @property
    def positional(self) -> bool:
        return not self.name.startswith("-")

    def to_dict(self) -> dict:
        return {
            "spec": self.spec,
            "name": self.name,
            "required": self.required,
            "repeat": self.repeat,
            "value": self.value,
            "choices": list(self.choices) if self.choices else None,
            "help": self.help,
        }


@dataclass(frozen=True)
class Schema:
    description: str | None
    args: tuple[Arg, ...] = field(default_factory=tuple)

    @property
    def usage(self) -> str:
        return " ".join(a.spec for a in self.args)

    def to_dict(self) -> dict:
        return {"description": self.description, "usage": self.usage, "args": [a.to_dict() for a in self.args]}


def _choices(token: str, number: int) -> tuple[str, ...] | None:
    m = _CHOICES.match(token)
    if not m:
        return None
    items = tuple(i.strip() for i in m.group("items").split("|") if i.strip())
    if len(items) < 2:
        raise HeaderError(f"line {number}: {token} needs at least two choices, separated by '|'")
    return items


def _parse_arg(body: str, number: int) -> Arg:
    m = _SPEC_HELP.match(body)
    if not m:
        raise HeaderError(f"line {number}: 'af-arg: {body}' needs a help text, two spaces after the spec")
    spec, help_text = m.group("spec").strip(), m.group("help").strip()
    inner, required = spec, True
    if spec.startswith("["):
        if not spec.endswith("]"):
            raise HeaderError(f"line {number}: unclosed bracket in {spec!r}")
        inner, required = spec[1:-1].strip(), False
    tokens = inner.split()
    if not tokens or len(tokens) > 2:
        raise HeaderError(f"line {number}: {spec!r} is not NAME, NAME..., --opt or --opt VALUE")
    name = tokens[0]
    if name.startswith("-"):
        value = tokens[1] if len(tokens) == 2 else None
        choices = _choices(value, number) if value else None
        if value and choices is None and not _PLACEHOLDER.match(value):
            raise HeaderError(f"line {number}: the value of {name} must be an upper-case placeholder or {{a|b}}")
        return Arg(spec, name, required, False, value, choices, help_text)
    if len(tokens) != 1:
        raise HeaderError(f"line {number}: a positional is one NAME, got {spec!r}")
    repeat = name.endswith("...")
    base = name[:-3] if repeat else name
    if not _PLACEHOLDER.match(base):
        raise HeaderError(f"line {number}: positional {base!r} must be an upper-case placeholder")
    return Arg(spec, base, required, repeat, None, None, help_text)


def parse_header(text: str) -> Schema | None:
    """The schema declared in the first lines of ``text``, or ``None`` without a header."""
    description: str | None = None
    args: list[Arg] = []
    seen = False
    for number, line in enumerate(text.splitlines()[:HEADER_LINES], start=1):
        m = _LINE.match(line)
        if not m:
            continue
        seen = True
        if m.group("kind") == "command":
            if description is not None:
                raise HeaderError(f"line {number}: a second af-command line")
            description = m.group("body")
            continue
        arg = _parse_arg(m.group("body"), number)
        if arg.positional and any(a.positional and a.repeat for a in args):
            raise HeaderError(f"line {number}: {arg.name} follows a repeated positional, which must be last")
        args.append(arg)
    return Schema(description, tuple(args)) if seen else None


def _is_option(token: str) -> bool:
    return token.startswith("-") and token != "-" and not _NUMBER.match(token)


def validate(schema: Schema, argv: list[str]) -> str | None:
    """``None`` when ``argv`` fits ``schema``, otherwise the reason, ending in the usage line."""

    def refuse(message: str) -> str:
        return f"{message}; usage: {schema.usage or '(no arguments)'}"

    options = {a.name: a for a in schema.args if not a.positional}
    given: set[str] = set()
    positionals: list[str] = []
    only_positionals = False
    i = 0
    while i < len(argv):
        token = argv[i]
        i += 1
        if not only_positionals and token == "--":
            only_positionals = True
            continue
        if only_positionals or not _is_option(token):
            positionals.append(token)
            continue
        name, eq, value = token.partition("=")
        opt = options.get(name)
        if opt is None:
            return refuse(f"unknown option {name}")
        if opt.value is None:
            if eq:
                return refuse(f"{name} takes no value")
        else:
            if not eq:
                if i >= len(argv) or _is_option(argv[i]):
                    return refuse(f"{name} needs a value ({opt.value})")
                value = argv[i]
                i += 1
            if opt.choices and value not in opt.choices:
                return refuse(f"{name} must be one of {'|'.join(opt.choices)}, got {value!r}")
        given.add(name)

    taken = 0
    for arg in (a for a in schema.args if a.positional):
        if arg.repeat:
            if arg.required and taken >= len(positionals):
                return refuse(f"{arg.name} needs at least one value")
            taken = len(positionals)
        elif taken < len(positionals):
            taken += 1
        elif arg.required:
            return refuse(f"missing {arg.name}")
    if taken < len(positionals):
        return refuse(f"unexpected argument {positionals[taken]!r}")
    for opt in options.values():
        if opt.required and opt.name not in given:
            return refuse(f"missing required option {opt.name}")
    return None
