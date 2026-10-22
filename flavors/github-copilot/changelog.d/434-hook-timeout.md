### Fixed

- **Guards no longer time out into "allow" (#434).** A hook that outlives its
  `timeout` decides nothing: VS Code lets the tool call through. Measured on four
  logs, `block-dangerous` ran past its 5 s limit in 85 of 1976 calls (p99 6.7 s,
  max 8.6 s), and `implementer-stop` -- which declared no timeout and so got the
  30 s default -- in 8 of 11 runs (45-80 s). Every hook declaration now carries an
  explicit timeout: `block-dangerous` 15 s, `scan-secrets` 20 s, session hooks 15 s,
  agent pre/post hooks 15 s, documenter/compliance/post-merge 30 s, and the
  implementer, refactorer and test-writer stop gates 300 s.
  `test-hook-declarations.ps1` pins each value at or above its measured floor.

### Added

- **`test-hooks-integration.ps1` fails on hook timeouts (#434).** Each
  `[HookExecutor] Hook command timed out` line counts as a failure naming the
  script and its limit. The completion line of a timed-out hook can still read
  `Success`, so the old failure check never saw one.
