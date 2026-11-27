### Fixed

- **`block-dangerous`: PowerShell literals no longer trip the pipe-to-shell
  rule (#581).** The rule scans the line with quoted data removed, but it lexed
  every command as bash: a backtick counted as command substitution and
  here-strings were unknown. A regex alternation such as `"a(?:ps1|sh)`r"` or
  a Markdown table cell inside `@'...'@` was hard-denied. A hard deny is
  terminal for an agent, so it stopped the work. For the `powershell` and
  `pwsh` tools the splitter now reads PowerShell: a backtick is an escape, and
  here-strings and single-quoted strings are data. A `$(...)` subexpression
  inside a double-quoted string or here-string is still scanned. Real pipes to
  `sh` or `iex` are still denied. The cases are in the shared table and run in
  both dialects.
- **The hook reads Copilot's `Bash` tool as PowerShell on Windows.**
  `agent-hooks.json` reports the shell tool as `Bash` on every host, and on
  Windows it runs PowerShell (measured in #447). On a Windows host the hook
  therefore lexes `Bash` commands as PowerShell. Residual risk: a real bash
  shell on Windows that reports itself as `Bash` and hides a pipe to a shell
  inside a backtick substitution in double quotes is no longer denied there.
  The other tool names (`bash`, `run_in_terminal`) keep the bash lexer.
