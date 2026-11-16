### Fixed

- **ADO agents get their tools as subagents in the Copilot harness (#550).**
  `ado-work-item-manager`, `ado-wiki-manager`, `ado-pr-manager` and
  `ado-pipeline-manager` granted `microsoft/azure-devops-mcp/<tool>`, which
  names no configured MCP server: all four ran with no ADO tools and no error
  (measured in #447). They now grant `ado-remote-mcp/<tool>`, the server name
  Microsoft documents for the remote Azure DevOps MCP server. Register the
  server under that key in `.vscode/mcp.json`; a toolset or tool filter must
  include the granted tools (see the **ado-shared** skill, Server Name).
  `check-mcp-tool-ids.py`, and with it the session readiness advisory, now
  flags the old prefix.
