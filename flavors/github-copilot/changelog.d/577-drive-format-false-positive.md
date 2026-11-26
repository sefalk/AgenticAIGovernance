### Fixed

- **`block-dangerous`: the drive-format rule matches the command, not the
  word (#577).** The unanchored pattern `format\s+[A-Za-z]:` hard-denied any
  `format` followed by an absolute Windows path, `ruff format C:\x.py`
  included. A hard deny is terminal for an agent, so it stopped the work. The
  rule now requires `format` or `format.com` in command position: at the start
  of a scan unit, after `&`, or after `cmd /c`. It also covers `format.com` by
  path, which the old pattern let through. The cases are in the shared table
  and run in both dialects.
