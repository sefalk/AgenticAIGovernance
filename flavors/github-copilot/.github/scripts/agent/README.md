# Agent scripts

Scripts that agents write for their own work and run through the command
server's `run_script` tool (`af-command-mcp`, #60), with arguments and without a
`tasks.json` entry. This is the default main folder of `AF_SCRIPT_DIRS`.

- `.py` runs with the project venv, `.ps1` with PowerShell, `.sh` with bash.
- `AF_SCRIPT_APPROVAL` decides whether a new or changed script asks first.
- Keep a script here only while it is useful; it is reviewed like any other file.
