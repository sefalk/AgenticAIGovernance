### Fixed

- **Runners find the venv in worktrees and below the repo root (#579).**
  `run-lint`, `run-tests` and `run-metrics` looked only at
  `<workspace>/.venv`. A worktree in the default `WORKTREE_VENV_MODE=shared`
  has none, and neither has a payload that sits below the git toplevel. Every
  runner therefore stopped with "venv python not found" exactly where agents
  work, and the only way left to format was a bare `ruff`, outside
  `LINTING_STRICTNESS`. A shared resolver (`_venv.ps1` / `_venv.sh`) now tries
  the workspace `.venv`, then the toplevel's, then (in `shared` mode only) the
  main checkout's. It prints a `NOTE` when it borrows one and puts the venv's
  bin first on `PATH`, so ruff comes from the same venv. When it finds nothing,
  it reports BLOCKED and names `setup-worktree` / `bootstrap-python-env`:
  creating a venv installs packages, so a human runs that step, never a
  runner. `run-tests` also blocks a shared venv that holds an editable install
  of the main checkout (`check-venv-editable.py`), because pytest would test
  the main checkout's code instead of the worktree's.
