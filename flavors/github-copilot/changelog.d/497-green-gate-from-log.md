### Changed

- **The green and refactor gates read the full-suite result; they never run
  the suite themselves (#497).** Since #473 the stop hooks found pytest and ran
  `tests: all` inside the `Stop` hook whenever the test log had no current pass.
  In MP that ran from 22:12 to 00:06 (114 min). The host did not enforce the
  30 s timeout, and the verdict was then discarded as a `non_blocking_error`:
  the agent waited two hours and the gate still failed open.
  - `implementer-stop` and `refactorer-stop` (both dialects) accept a current,
    complete, passing `all` entry in `.github/test-log.json` as before.
  - Otherwise they **block**. A failed last run gets "fix it, run `tests: all`
    once more". A missing, partial or stale entry gets "run `tests: all` once
    as your last step, then stop again".
  - The producers now run `tests: all` once as their last step. The number of
    full runs per phase is unchanged; the run moved from the hook to the agent,
    where it is visible and has no hook timeout.
  - **A logged pass is current when nothing changed after the run started.**
    Before, any uncommitted file under `SRC_DIR` or `tests/` made the log
    stale. A producer stops before the coordinator commits, so under the new
    rule that would have blocked every green phase forever. Now a commit after
    the run started makes the log stale, and so does a dirty or untracked file
    written after it (`Test-AfRunCurrent` / `af_run_current` in `_common`).
  - Updated to match: the `test-execution` skill budgets (implementer and
    refactorer 1× all), `implementer.agent.md`, `refactorer.agent.md` and
    `testing.instructions.md`.
