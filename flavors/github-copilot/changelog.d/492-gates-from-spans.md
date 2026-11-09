### Changed

- **The flight report's gate strip reads the session's own debug-log `hook`
  spans (#492).** It read VS Code's per-window `Hooks.log` and filtered it to
  the session. The debug logs carry every hook's command and output, scoped to
  the session, with subagent verdicts in the subagent's log. `--log` is gone.
  The span reader is `_agentlog.hook_spans()` and the verdict is
  `gate-health.span_verdict()`; `turn-receipt` (#478) uses the same pair.
  `gate-health.py` keeps reading `Hooks.log` for its cross-session counts.
