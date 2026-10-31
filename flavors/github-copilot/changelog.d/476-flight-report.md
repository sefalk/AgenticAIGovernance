### Added

- **`flight-report.py`: one offline HTML page per chat session (#476).** It
  joins the session's debug logs, the hook log and the cost collector on one
  time axis. The page has four panels:
  - subagent lanes: span, requests and edited files per log;
  - a gate strip: one cell per hook verdict that names this session;
  - cost by agent × model, with its coverage;
  - a log of starts, ends, denies, blocks and NOT RUN verdicts.

  Every panel declares its kind (#477). At any coverage other than `full` the
  cost panel is a `lower_bound`. The page loads nothing from the network and
  copies no prompt, argument or tool text. It is run by hand:
  `flight-report.py --session-dir <dir>` writes
  `.github/logs/flight-<session>.html`. On a real session (96 MB `main.jsonl`,
  832 verdicts) the page took 2.1 s.
- `gate-health.py` now reads the hook log through `iter_runs()`, which yields
  every run and outcome with its `session` and timestamp from the Input line.
  The counts report and the flight report share this one reader.
