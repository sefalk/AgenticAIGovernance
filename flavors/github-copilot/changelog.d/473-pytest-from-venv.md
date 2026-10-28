### Fixed

- **Producer stop gates run the tests again in a live session (#473).** The
  extension host starts hooks without the project's venv on `PATH`, and
  `implementer-stop`, `refactorer-stop` and `test-writer-stop` looked the runner
  up with `Get-Command pytest` / `command -v pytest` only — so every live Red and
  Green gate was skipped (15 of 15 verdicts in the hook logs, 2026-10-22..28),
  each reading as a pass. The runner is now resolved like `run-tests.ps1` does:
  the code root's (then the deploying root's) `.venv` interpreter with
  `-m pytest`, `PATH` last (`Get-AfPytest` / `af_resolve_pytest` in `_common`).
- **test-writer keeps its provenance gate without a runner.** A missing runner,
  `tests/` directory or collected test now disables the Red gate only; it used
  to exit before the provenance gate. New test files are listed with
  `--untracked-files=all`, so files in a new test directory are checked too.
- A test gate that could not run is reported as `NOT RUN`, not as `PASS`.
