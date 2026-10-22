### Changed

- **The framework states that it supports the VS Code Local harness only (#443, owner decision A).** VS Code now offers a Copilot harness as well, and the framework's hooks, guards and tool names were built and measured in Local only. All three deploy paths and `session-context` (both dialects) now say so. Supporting the Copilot harness is parked as #447.

### Removed

- **`search/changes` is no longer assigned to any agent (#443).** A probe on 2026-10-22 showed that a Local subagent does not receive it, so ten agents believed they had a capability they lacked. `test-rule-drift.ps1` R30 keeps it out. The `pylance-mcp-server/*` names stay: the same probe showed all of them resolving in Local, so the Agent Customizations editor's flag on them is cosmetic (documented in `TOOLS.md`).
