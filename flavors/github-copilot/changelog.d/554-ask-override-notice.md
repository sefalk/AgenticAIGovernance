### Fixed

- **AF ask gates now notify the agent when the tool call runs (#554).** The
  PostToolUse notice names the gate and reason, explains that hook data cannot
  distinguish a human approval from host permission policy, and recommends
  aligning IDE and AF permissions. It also reminds the agent to preserve
  traceability where applicable. Delivery was verified live in a Copilot
  session for the main agent and a subagent on the `block-dangerous` path.
- **The researcher fetch hook no longer echoes credentialed URLs (#554).** It
  names the finding instead, and a backslash in the URL authority now prompts,
  because WHATWG and RFC 3986 parsers resolve such a host differently.
