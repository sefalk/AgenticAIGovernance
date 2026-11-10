### Fixed

- **Guard hooks no longer fail open under parallel MCP calls (#515).** In MP, an
  `ado-work-item-manager` subagent sent `list_comments` reads in batches of six.
  `block-dangerous` and `scan-secrets` then took 13–57 s per call, and 21 of 80
  runs ended in `non_blocking_error`, which means those calls ran unchecked.
  - **Fast path before Python.** Both guards now read the tool name first, in
    PowerShell or bash. Any call that no guard acts on exits before `_common`
    probes for Python. The pattern lives in `_fastpath.{ps1,sh}` and covers every
    guarded class: terminal, task, code-execution surfaces, work-item and body
    writes, file writes. A test checks it against `scan-secrets.py`'s write-tool
    list and that both dialects use the same pattern.
  - **Reads that still start Python.** `scan-secrets` stays on the full path for
    three kinds of call:
    - work-item `get`/`get_batch`, `issue_read` and `pull_request_read`, which the
      field and body guards must record (#197, #376);
    - any result of 4,096 chars or more, which may need the long-line notice
      (#341);
    - `runSubagent`.

### Added

- **Fail-open guards are named.**
  - The turn receipt labels an error on `block-dangerous` or `scan-secrets` as
    `FAIL-OPEN`.
  - When a subagent returns, the coordinator's PostToolUse on `runSubagent`
    adds context naming the guard runs in that subagent that ended in error.
    The coordinator therefore learns that those calls were unchecked before it
    acts on the result.
