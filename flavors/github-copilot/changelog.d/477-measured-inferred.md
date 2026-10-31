### Added

- **Every field of an AF report says whether it is measured or inferred
  (#477).** The convention is written once in `logs/README.md` ("Measured,
  inferred, lower bound"), and the metrics skill points to it. There are four
  kinds: `measured`, `inferred` (with a named rule id), `lower_bound`, and
  `meta`. A field built on an inferred verdict is inferred.
  - `collect-session-cost.py` declares `FIELD_KINDS` for the `cost:` block and
    `REPORT_FIELD_KINDS` for `--report`. Both outputs carry a `kinds:` line that
    names their inferred fields with rule ids and their lower bounds. The block
    is now schema 9.
  - `gate-health.py --json` replaces `basis` with a `kinds` map over every
    top-level field. Each finding names its rule: `not-run-half`, `quiet-gate`
    or `declared-unseen`.
  - `test-session-cost.ps1` and `test-gate-health.ps1` fail on an emitted field
    without a kind, and on a rule id the README does not define.
