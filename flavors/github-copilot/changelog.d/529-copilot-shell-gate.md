### Fixed

- **`block-dangerous` gates the Copilot harness shell tools (#529).** Under the
  Copilot harness the deployed `agent-hooks.json` fires, but the shell tool
  arrives as `Bash` (or `powershell` from a version-1 hook file) instead of
  `runInTerminal`. The gate did not recognise either name and returned `{}`,
  which is consent; the fast path skipped the full guard for the same reason.
  Both names are now gated in both dialects. The existing deny output
  (`hookSpecificOutput.permissionDecision`) was measured to be honoured by the
  Copilot harness (#447), so only the input recognition changed. Subagent
  `task` / `Agent` calls and reads stay untouched.
- **CI runs on pull requests into `release/local-1.28`**, the Local-harness
  hotfix branch since `dev` moved to the Copilot migration (#528).

### Added

- **README: "Release lines".** 1.28.x on `release/local-1.28` is the Local
  line (hotfixes only, 1.28.6 the final feature release); 2.x on `dev` is the
  Copilot-harness line (#528).
