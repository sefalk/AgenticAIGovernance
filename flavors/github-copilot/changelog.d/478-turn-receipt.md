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
  - Verdicts come from the hook log through `gate-health.iter_runs`, filtered
    to this session and to the time since its previous `Stop`.
  - Measured on a real 3.9 MB hook log: 1.5 s, inside the 15 s timeout.
