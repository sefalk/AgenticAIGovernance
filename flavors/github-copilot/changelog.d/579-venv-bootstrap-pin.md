### Changed

- **Runners create a missing venv themselves; hooks share the resolver (#579).**
  With `PY_ENV_BOOTSTRAP=always`, now the default, `run-lint`, `run-tests` and
  `run-metrics` run `.github/scripts/bootstrap-python-env` when no venv
  resolves, then continue. Creating a venv is no longer a human step, so a
  fresh worktree does not stop an autonomous workflow. `ask` and `off` report
  BLOCKED and name the bootstrap script, the new task `env: bootstrap python`
  and `setup-worktree`.

  Hooks never bootstrap, because pip cannot finish inside a hook timeout. The
  coordinator hook no longer runs pip itself. Under `always` it denies a raw
  Python command and points at the runner or the bootstrap script; runner
  commands pass.

  The bootstrap installs `DEP_FILE` / `DEP_DEV_FILE` through the reviewed
  script, not through an ad-hoc command, so it does not pass the
  `AUTONOMY_CAT_PKG_INSTALL` check in block-dangerous. Set `ask` or `off`
  where unattended installs are not acceptable.

- **Hooks find the project venv the same way the runners do.**
  `Get-AfPytest` / `af_resolve_pytest` and the implementer and refactorer stop
  gates now use the shared resolver (`_venv.ps1` / `_venv.sh`). A payload
  below the git toplevel and a shared worktree get the same venv in a hook as
  in a runner. In `isolated` mode a hook no longer borrows the main
  checkout's venv; that matches the runners.

- **`run-lint` warns when the venv's ruff differs from the pin.** When
  `DEP_DEV_FILE` (in the workspace or at the toplevel) pins `ruff==X`, a
  different installed version prints a `WARN`. `ruff format` output changes
  between versions, so drift otherwise shows up only as a CI failure. The AF
  repository's own pin moved into a root `requirements-dev.txt`, which
  `regression.yml` installs.
