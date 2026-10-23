### Fixed

- **Session cost is read out as often as the session allows, and its completeness is proven over every read (#457).** The cost collector ran only when a workflow finished. By then a long session's debug log had often lost its head: on one machine 18 of 43 logs no longer started with `session_start`, at sizes from 1 to 231 MB. Every such session was then reported `truncated` with its total withheld, and sessions without a documenter run were never read at all.
  - A new global hook, `cost-snapshot`, runs on every `Stop` and `SubagentStop`. It refreshes a per-session store under `.github/logs/cost/sessions/` in the background and answers `{}` at once.
  - The collector's new `--store` mode reads only what each log gained since the last run. A log whose first 4 KB still hash the same was only appended to. A full pass over a 92 MB log took 2.8 s; a tail read takes milliseconds.
  - When a log's head changed, the last line read is looked up in the new file by hash. Found, nothing was lost. Not found, the store records a gap with `after_ts` and `resumed_ts`. Only hashes are kept, never log text.
  - `documenter-stop` aggregates the store's union. A session the store saw from its start is now `full` even after the log has lost its head. The workflow's facts artifact then includes the rows the log has since dropped.
  - New report mode: `collect-session-cost.py --report .github/logs/cost/sessions` gives the total across sessions. `credits_complete` (sessions with every request held) is kept apart from `credits_lower_bound` (every row held).
  - A withheld block no longer renders `by_model: {}` / `by_purpose: {}`, which read as zero cost. Both are now `null`. The rows that survived are summed under `surviving:`, a lower bound, never `totals`.
  - Coverage gains `gapped`. The block schema is version 8.
