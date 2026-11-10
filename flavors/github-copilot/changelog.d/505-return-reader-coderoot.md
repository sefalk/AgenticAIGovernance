### Fixed

- **`implementer-stop.ps1` reads its own return again (#505).** It called
  `Get-AfSubagentReturn` without `-CodeRoot`. The wrapper then joined an empty
  path, found no Python, and reported every return as `unavailable`. So every
  implementer PASS in MP said `RETURN UNREADABLE`, even though the complete
  return was in the debug log.
  - The hook now passes `-CodeRoot`.
  - The wrapper falls back to the code and main roots it already resolved.
  - A `test-hooks.ps1` case runs the hook end to end against a real session
    directory. Before, the tests checked only the reader on its own and that
    the hook's text named the wrapper.
