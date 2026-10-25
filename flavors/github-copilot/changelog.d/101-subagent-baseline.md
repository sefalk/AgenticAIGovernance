### Fixed

- **Producer stop gates no longer claim an earlier producer's uncommitted work
  (#101).** A new global `SubagentStart` hook (`subagent-baseline`) records, per
  `agent_id`, every path that is dirty when a test-writer, implementer or
  refactorer starts, with the blob hash of its content — for the deploying repo,
  the active worktree and every folder of the multi-root workspace. The stop
  gates' peer-edit reader (`concurrent-agent-edits.py`) now also drops files
  that are still byte-identical to that record, so a provenance or quality gate
  no longer demands work on a file the subagent never touched. It also names the
  subagent's own debug log exactly by `agent_id` instead of by newest mtime.
  The lint scope is unchanged. No record, a moved `HEAD` or any failure
  subtracts nothing — the previous behaviour.
