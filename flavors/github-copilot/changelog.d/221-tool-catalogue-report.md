### Added

- **Tool-catalogue report: what each MCP server costs per request against how
  often it is called (#221).**
  - `scripts/tool-catalogue-report.py <debug-logs dir> [...]` reads the
    `tools_N.json` dumps and `tool_call` spans of many sessions and prints one
    row per server with sessions delivered, mean tokens per request, calls,
    last-seen date and a verdict.
  - It judges only the last `--window-days` (default 30) and says so, with
    corpus size and date range. A server is dated by the dumps that carried it,
    so one switched off earlier shows as `not delivered in window`.
  - Too few sessions in the window (`--min-sessions`, default 10) or no session
    data is `BLOCKED`, exit 2.
  - Read-only: it disables nothing. `candidate` means delivered and never
    called; the decision is a human's.
  - **By agent mode.** Requests are split by the agent they ran in (the mode
    name the editor writes into the system prompt; nothing else is read from
    it), with share and mean catalogue tokens. An agent's `tools:` list is its
    reviewed enablement, so per-server verdicts cover only the unrestricted
    catalogue; a server seen only in an agent's list is `agent tools only`.
    Decided on #221: no parallel allowlist beside the agent definitions.
