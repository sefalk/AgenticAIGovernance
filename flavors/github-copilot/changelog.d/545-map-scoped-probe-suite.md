### Fixed

- **`test-copilot-scoped-probe.ps1` is registered in the suite map and budgets (#545).** AF PR 542 added the suite without an entry in `suite-scope.json` or `suite-budgets.json`, so the suite-map and budget meta-suites failed on `dev` and every pull request that selected them.
