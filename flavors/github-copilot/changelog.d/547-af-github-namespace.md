### Fixed

- **GitHub agents get their tools as subagents in the Copilot harness (#547).**
  `gh-issue-manager` and `gh-pr-manager` granted `github/<tool>`, which never
  resolves for a subagent when the server is named `github`: both ran with no
  GitHub tools and reported BLOCKED (measured in #447). They now grant
  `af-github/<tool>`. `deploy.ps1` and `deploy.sh` create a repo-root
  `.mcp.json` registering `af-github` (HTTP, `Authorization: Bearer
  ${AF_GH_TOKEN}`; no secret in the file) when the target has none. An
  existing `.mcp.json` is never modified: without an `af-github` entry the
  deploy warns and prints the entry to merge. Set the `AF_GH_TOKEN`
  environment variable to a fine-grained token for the repository.
