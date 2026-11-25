### Changed

- **`block-dangerous.ps1` separates its policy from its entry point (#572).**
  The verdict logic is now the function `Invoke-AfBlockDangerousPolicy`, which
  takes the parsed payload, the config lines and three lookups (current branch,
  ref existence, foreign-work guard) as parameters and returns the verdict
  instead of writing it and exiting. The script body binds those lookups to
  `git` and `_foreign_guard.py` exactly as before; dot-sourcing it with
  `-AfLibrary` loads only the policy. Hook behaviour is unchanged, except that
  the current branch is now read only when a bare `git push` needs it, instead
  of once per call.
- **`test-hooks.ps1` calls the block-dangerous policy in-process.** Cases that
  only ask the policy a question no longer start `powershell -File` each; the
  stdin/exit-code contract keeps its own subprocess cases (one per verdict, and
  the empty/malformed-input cases). `AF_TEST_BD_SUBPROCESS=1` restores the old
  path; `AF_TEST_BD_CROSSCHECK=1` runs both and fails on any byte difference.
  New cases cover a bare `git push` on a protected and on an agent branch,
  which the fixture's unborn branch had kept out of reach.
