### Fixed

- **The Red gate runs only the changed test files (#507).** `test-writer-stop`
  (ps1 and sh) used to run `pytest tests/`, the whole suite, inside a Stop
  hook. In MP that took hours and ended as a host timeout. It also answered the
  wrong question: one pre-existing red test anywhere in `tests/` satisfied the
  gate for new tests that all passed.
  - The gate now runs the files `git status` shows as new or modified under
    `tests/` (`test_*.py`, `*_test.py`).
  - If no test file changed, it reports
    `Red gate NOT RUN (no changed test files)`.
