### Added

- **Reasoning effort per model tier (#557).** In the Copilot harness a subagent
  without `reasoning-effort:` runs at the effort of the chat that called it
  (measured in #447), so a formatting worker could run at `high` and a planner
  at `low`. Deploy now writes `reasoning-effort:` after every resolved tier
  `model:`: the project's `AF_EFFORT_TIER_*` in `af-env.conf`, else the
  framework default `AF_EFFORT_DEFAULT_*` (PREMIUM `high`, BALANCED `medium`,
  EFFICIENT `low`). `inherit` as the project value writes no line. An agent
  that declares its own `reasoning-effort:` keeps it. Values: `low`, `medium`,
  `high`, `xhigh`, `max`; anything else fails the deploy. All three deploy
  paths (`deploy.ps1`, `deploy.sh`, MCP deploy) emit identical bytes.
