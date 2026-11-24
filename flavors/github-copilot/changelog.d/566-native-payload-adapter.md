### Added

- **Native payload adapter for `version: 1` hook files (#566).** A
  `version: 1` registration hands hooks a camelCase payload (`toolName`,
  `toolArgs`, `sessionId`). Every AF policy reads snake_case, so each one found
  no tool name and returned `{}`. That looks the same as an approval: measured
  with a force push sent to `block-dangerous`. The new
  `hooks/scripts/_native_adapter.py <event> -- <hook command>` sits in front of
  one unchanged hook and does the following:
  - Renames the payload to the shape that the PascalCase registration
    delivers.
  - Passes snake_case input through byte for byte.
  - Keeps a patch string as a string.
  - Refuses on `preToolUse`, and warns on all other events, when a payload
    cannot be translated or the hook cannot start.
  - Lifts a nested `hookSpecificOutput` verdict to the top level.
  - Passes the hook's exit code and stderr through unchanged.

  `agent-hooks.json` is unchanged; no hook file uses the adapter yet.
  `test-native-adapter.ps1` runs the real `block-dangerous` and `scan-secrets`
  against recorded camelCase payloads and their snake_case controls.
