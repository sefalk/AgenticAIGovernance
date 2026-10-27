### Fixed

- **Producer stop gates now judge every repository the subagent edited
  (#456, phase 2).** In a multi-root workspace the deploying repository's
  `implementer-stop`, `refactorer-stop` and `test-writer-stop` fired for edits
  in every folder but scoped themselves from the deploying checkout, so an edit
  in a second repository was never tested, linted or checked for provenance.
  The new `repo-gates.py` core reads the subagent's own debug log (exactly, by
  `agent_id`), and when another repository was edited it runs the calling hook
  and that repository's own deployed copy of it — under its own `af-env.conf`,
  venv and test log — and merges the verdicts: every block is reported in one
  message, prefixed with the repository. A repository without a deployed hook is
  named as not gated. Edits confined to the deploying repository gate inline
  exactly as before.
