### Fixed

- **`pytest --collect-only` no longer counts as a green full-suite run (#504).**
  The `af_test_log` plugin filed a collect-only run of `tests/` under `all`.
  Such a run exits 0 and executes no tests, so the entry read "0/0 passed" and
  replaced the last real result. The green and refactor gates then accepted it.
  - The plugin now writes no entry for a collect-only run.
  - The gates, in both ps1 and sh, accept a pass only when `total > 0`.
