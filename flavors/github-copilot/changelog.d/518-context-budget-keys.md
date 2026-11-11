### Changed

- **The coordinator's context budget is configurable, its counting rules are
  written down, and RED stops only at a phase boundary (#518).** In a consumer
  session the coordinator hit RED after ten calls and stopped mid-workflow,
  with no context confusion observed. Two of those ten calls were a work-item
  lookup and a compliance-checker bookend.
  - **New `af-env.conf` keys.** A missing key falls back to its default.
    - `AF_CONTEXT_YELLOW_CALLS=7`
    - `AF_CONTEXT_RED_CALLS=15` (was 10)
    - `AF_CONTEXT_RED_MODE=hard|advisory`
  - **RED behaviour per mode.**
    - `hard`: finish the current phase to its next commit checkpoint, then
      checkpoint to `WIP.md` and stop.
    - `advisory`: narrate RED and continue.
    - A context-confusion error is RED regardless of the count.
  - **Counting rules** (in `tdd-orchestration` § Context Budget Awareness):
    - counted per coordinator session;
    - workflow-step agents count, retries included;
    - provider workers (`ado-*`, `gh-*`) and the compliance-checker bookends
      do not count.
  - **YELLOW** compresses the coordinator's own summaries only. It does not
    trigger or replace harness compaction.
  - `coordinator.agent.md` keeps one line that points to the runbook and names
    the keys.
