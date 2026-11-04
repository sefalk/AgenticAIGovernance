### Added

- **Turn receipt: a global `Stop` hook lifts this turn's actionable gate
  verdicts to the top level (#478).** A probe on 2026-11-02 showed that every
  hook `systemMessage` renders, but only as a collapsed "Warning from Stop
  hook". A subagent's verdict also sits inside the coordinator's collapsed
  thinking and then inside the subagent block, two levels deep. That is how
  "Green gate NOT RUN" stayed unseen for a week (#473).
  - `turn-receipt.ps1`/`.sh` with the core `turn-receipt.py` run after
    `stop-tests` and `cost-snapshot`.
  - They name this turn's NOT RUN, block, deny and error verdicts in one line
    under the answer, for example
    `turn findings (#478): implementer-stop NOT RUN; block-dangerous deny x2`.
  - A clean turn prints nothing, so the warning badge keeps its meaning.
  - Verdicts come from the `hook` spans in the session's own debug logs
    (`main.jsonl` and each subagent log), from the time since the session's
    previous `Stop`. VS Code's `Hooks.log` is not used. It is per window,
    mixes every session, and has to be located by launch folder. The first
    version picked the newest launch folder, which was empty, and printed
    nothing in the live probe (#492).
  - Measured on a live session (123 MB `main.jsonl`): 2.4 s, inside the 15 s
    timeout. Live probe in an AF window: a turn with a denied command showed
    `turn findings (#478): block-dangerous deny`; the next, clean turn showed
    nothing.

### Fixed

- `suite-scope.json` now maps `test-gate-health.ps1`, `test-flight-report.ps1`
  and `test-turn-receipt.ps1`. Before, `test-suite-scope` (S2) and
  `test-suite-portability` failed on `dev`, which PR-scoped sweeps did not
  select.
