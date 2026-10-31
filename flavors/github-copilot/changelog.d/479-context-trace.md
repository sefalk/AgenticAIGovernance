### Added

- **Context trace per agent (#479).** `collect-session-cost.py` gains
  `context_series()`. Per log (main and each subagent) it collects the input
  tokens of each agent request (uncached + cached: what the model read, not
  what it cost), with floor, median and max. A fall of more than half between
  two requests is marked as an inferred compaction (`CONTEXT_DROP` 0.5). A log
  that lost its head has no floor.
  - `--report` adds `context_floor`: min, median and max of the first request
    over the complete sessions, kind `inferred` with rule `first-request`. On
    MP's store (2 complete sessions) it reads 45,556 to 47,306 tokens: what an
    empty turn reads, measured where #221 had an estimate.
  - The flight report (#476) gets a fifth panel, "Context per request", with one
    line per lane and the drops marked. On this AF session the main log peaked
    at 691,139 input tokens with one inferred drop; the test-writer log ran from
    39,395 to 84,727.
