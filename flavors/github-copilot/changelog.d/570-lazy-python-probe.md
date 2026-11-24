### Changed

- **PowerShell guard hooks probe for Python only when a verdict needs it
  (#570).** Loading `_common.ps1` used to probe every interpreter candidate up
  front. On Windows that cost about 0.5 s per hook call, because `python3` is
  an App Execution Alias that fails only after a full process start. The
  PreToolUse hooks (`block-dangerous`, `coordinator`, `planner`, `refactorer`,
  `researcher`, `test-writer`) and `stop-tests` now set `$AfLazyPython = $true`
  and read the interpreter through the new `Get-AfPython`, which probes once on
  first call. A read-only command, a hard deny or a confinement verdict no
  longer starts Python; work-item writes, the foreign-work guard and ask
  receipts still get the same proven interpreter. Other hooks, including
  project hooks, keep the eager `$AfPython` unchanged.
- **`check-hook-resolution.py` rule AF006.** A `.ps1` that opts into the
  deferred probe and still reads `$AfPython` directly is reported, because
  there the variable stays empty and the checks behind it would stop running.
