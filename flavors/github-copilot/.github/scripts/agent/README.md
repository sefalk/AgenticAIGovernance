# Agent scripts

Scripts that agents write for their own work and run through the command
server's `run_script` tool (`af-command-mcp`, #60), with arguments and without a
`tasks.json` entry. This is the default main folder of `AF_SCRIPT_DIRS`.

- `.py` runs with the project venv, `.ps1` with PowerShell, `.sh` with bash.
- `AF_SCRIPT_APPROVAL` decides whether a new or changed script asks first.
- Keep a script here only while it is useful; it is reviewed like any other file.

## Declaring arguments

A script that takes arguments declares them in a header block within its first
40 lines. `list_scripts` publishes it, and `run_script` refuses argv that does
not fit it before anything is approved or run. Without a header, argv is passed
through unchecked.

```python
# af-command: Lint the given files with ruff.
# af-arg: FILE...                 Files to lint
# af-arg: [--fix]                 Apply fixes
# af-arg: [--select CODES]        Comma-separated rule codes
# af-arg: [--format {text|json}]  Output format
```

- Spec and help text are separated by **two or more spaces**.
- `[...]` marks an optional argument. `NAME...` is a repeated positional, and it
  must be the last one. `--opt VALUE` takes a value (`--opt=value` works too),
  and `{a|b}` restricts it to a closed set of values.
- Placeholders are upper case. A malformed line refuses every call to the script
  until it is fixed.
