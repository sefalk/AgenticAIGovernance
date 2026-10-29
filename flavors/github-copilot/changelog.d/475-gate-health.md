### Added

- **`gate-health.py`: what every hook actually decided, per gate (#475).** It
  reads VS Code's `GitHub Copilot Chat Hooks.log` (all windows, or `--log`, from
  `--since`) and counts each hook script's outcomes. Outcomes are allow / ask /
  deny / block, pass, warn, advisory, silent, NOT RUN (including the `skipped`
  and `not measurable` wordings), loop-guard skip, error and timeout. It then
  lists inferred findings:
  - `not-run`: a gate that did not run in at least half its runs;
  - `never-decided`: a gate able to block that never did;
  - `never-ran`: declared in `agent-hooks.json` or agent frontmatter but never
    seen; dialect twins count as one, and SessionStart is exempt.

  Against the 2026-10-22..28 logs it flags `implementer-stop` (9 of 11 runs) and
  `test-writer-stop` (8 of 8): the inert gates of #473, which a week of verdicts
  had shown as PASS. Read-only; `--json` for other tools (the flight report,
  #476).
