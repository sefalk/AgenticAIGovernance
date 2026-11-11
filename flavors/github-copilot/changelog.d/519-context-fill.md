### Added

- **The context budget measures context fill instead of only counting calls
  (#519).**
  - **Where it comes from.** When a subagent returns, the coordinator's
    PostToolUse on `runSubagent` adds the line
    `Context budget (#519): GREEN|YELLOW|RED · fill NN % ... (measured)`.
    The fill is the coordinator's latest prompt tokens (`inputTokens` of its
    own `panel/*` requests, from the session log) divided by the model's
    `max_prompt_tokens` (from `models.json`).
  - **Compactions.** A drop of more than half since the previous request is
    reported as a harness compaction.
  - **Thresholds.** New keys `AF_CONTEXT_YELLOW_FILL_PCT=50` and
    `AF_CONTEXT_RED_FILL_PCT=75`, calibrated on 14 local sessions (recorded on
    the issue). `AF_CONTEXT_RED_MODE` from #518 applies unchanged.
  - **Fallback.** Without a session log or a known model there is no line, and
    the coordinator counts calls as before (#518). The narration names which
    signal it used.
  - **Privacy.** No local path reaches the context.
