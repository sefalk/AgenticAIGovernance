### Fixed

- **The work-item field guard records reads in the Copilot harness and no
  longer hard-blocks by default (#551).** Copilot sends a tool's result as
  `tool_result.text_result_for_llm` (or `toolResult.textResultForLlm`), not
  `tool_response`, so the field guard and the GitHub body guard never cached a
  read and refused every long-text update as "not read" (measured in #447).
  Both now read whichever field the harness sends. An update without a read,
  without `test /rev`, or with a stale `test /rev` now asks the human instead
  of refusing, so an intended or emergency change stays possible; the agent
  records why in `System.History` or a comment. `WI_FIELD_SHRINK_POLICY=deny`
  or `declared-strict` keeps the refusal. Where no human can answer (cloud
  agent, CLI autopilot) Copilot treats `ask` as deny.
