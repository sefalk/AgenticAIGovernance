### Added

- **The deploy notes a project without an `af-command` registration (#445).** Since #60, argument-bearing script runs have one route, `af-command/run_script`; without the server an agent can only report BLOCKED. All three deploy paths now look for the `"af-command"` server key in `.vscode/mcp.json` and in any `*.code-workspace` in the target or its parent folder (where MP keeps it), and print the registration snippet when none is found. A text match, because workspace files are JSONC. Advisory: the result stays `ok`, and a user-level registration cannot be seen from the repository.
