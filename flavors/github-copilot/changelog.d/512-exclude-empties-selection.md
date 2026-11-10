### Fixed

- **A scoped run whose only selected suites are excluded is "nothing to run",
  not a failure (#512).** CI sweeps with
  `-Exclude test-hooks-integration.ps1, test-deploy-engine.ps1`, because those
  two suites have their own steps. A PR that touched only `mcp-deploy/`
  selected `test-deploy-engine.ps1` alone. Exclusion left zero suites, and
  `run-all-tests.ps1` exited 1 with `No suites matched filter '*'`, so such a
  PR could not pass CI. It now prints `Nothing to run` and exits 0.
