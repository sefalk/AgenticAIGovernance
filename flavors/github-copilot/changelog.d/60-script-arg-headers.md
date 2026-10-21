### Added

- **Scripts declare their arguments in a header block (#60).** `run_script`
  passed `args` through as argv, so an agent learned a script's interface by
  reading it or by failing. A script now states it in `# af-command:` and
  `# af-arg:` lines in the usage-line notation (`FILE...`, `[--fix]`,
  `[--select CODES]`, `{text|json}`).
  - `list_scripts` returns `description`, `usage` and `args` for each script
    with a header, and `header_error` for a header it cannot read.
  - `run_script` refuses argv that does not fit, before approval, so nobody is
    asked to approve a call that cannot be right. The reason ends in the usage
    line.
  - A malformed header refuses every call; a script without a header keeps the
    old pass-through contract.
  - Owner decision 2026-10-21: a header block in the script rather than a
    separate manifest, so there is one source and nothing to drift.
