### Fixed

- **GitHub agents write issues and pull requests without a form (#573).** In
  VS Code the GitHub MCP server handed `issue_write`, `create_pull_request` and
  `update_pull_request` to an interactive form instead of running them, so
  every write waited for the human, whatever chat permission level was set.
  The `af-github` entry in `templates/mcp.json` now sends
  `X-MCP-Features: mcp_apps_disable_form_deferral`. The AF write guards still
  run before the call. Deploy never edits an existing `.mcp.json`: add the
  header to your project's `af-github` entry and restart the server; remove it
  to keep the form. `gh-issue` and `gh-pr-manager` treat
  `awaiting_user_submission` as pending, never as a completed write.
