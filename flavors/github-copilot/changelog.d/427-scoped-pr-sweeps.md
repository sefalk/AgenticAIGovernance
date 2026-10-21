### Changed

- **CI runs only the suites a pull request into `dev` needs (#427).** Every
  pull request ran every payload suite, about 21 minutes each, although
  `run-all-tests.ps1 -Changed` could already pick the suites a diff needs.
  - The sweep step passes `-Changed -Since origin/dev` on a pull request into
    `dev`, after printing the selection to the log and the job summary. The
    push to `dev` after the merge and the `dev -> main` promotion keep the full
    sweep, so a gap in `suite-scope.json` never reaches `main`.
  - A path outside the payload (the repository's own CI, hooks, scripts and
    docs) is no longer "unmapped": those have their own unconditional CI steps,
    and counting them widened nearly every pull request to the full sweep. The
    new `repo` map in `suite-scope.json` names the exceptions a payload suite
    reads (`.githooks/pre-commit` for `test-context-budget.ps1`).
  - Fixed on the way: path matching trimmed the characters `./` instead of the
    prefix, so in a project every `.github/...` path became `github/...` and
    matched no mapping. Scoped runs there always fell back to the full sweep.
