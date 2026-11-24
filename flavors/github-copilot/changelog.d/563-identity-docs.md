### Added

- **`docs/IDENTITIES.md` separates the agent identity from repository access
  (#563).** The Copilot harness sign-in runs the agents. A fine-grained PAT in
  `AF_GH_TOKEN` (minimum scopes listed) serves issues, PRs and REST, and Git
  Credential Manager serves git-only access, including a second account on the
  same host. Any script that starts a nested Copilot CLI must clear the
  inherited `COPILOT_*`/`GH_*`/`GITHUB_*` variables and set its identity
  explicitly; no AF script does so today, and the rule binds the CLI
  attestation of #553. A provider API key (BYOK) was evaluated and not
  adopted; the open measurements are listed. The README links the page under
  runtime prerequisites.
