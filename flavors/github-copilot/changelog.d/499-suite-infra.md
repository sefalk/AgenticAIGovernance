### Fixed

- **Suite infrastructure after 1.28.2 (#499).**
  - `suite-budgets.json` gives `test-gate-health`, `test-flight-report` and
    `test-turn-receipt` their 30 s floor.
  - `test-hook-log-attribution.ps1`'s fixture `Stop` invocation runs the newly
    registered `turn-receipt` hook.
  - Both failed in MP's 1.28.2 sweep (37/40). The scoped PR sweeps had selected
    neither suite, so `suite-scope.json` now maps `agent-hooks.json` to the
    attribution suite and `suite-scope.json` itself to the budgets suite. A new
    hook or suite selects them next time.
