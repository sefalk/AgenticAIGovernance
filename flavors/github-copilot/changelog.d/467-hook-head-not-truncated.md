### Fixed

- **The session cost store no longer reports every intact session as
  `coverage: truncated` (#467).** The editor writes one `hook`/`SessionStart`
  span per SessionStart hook ahead of `session_start` in `main.jsonl`, so the
  #450 rule "the first line must be `session_start`" withheld the total of every
  session in a deployment with SessionStart hooks — #457 showed only a lower
  bound. Leading SessionStart hook spans are now passed over, in the direct and
  the `--store` path; a fragment or any other event first is still `truncated`.
  The store's verdict waits across snapshots until the deciding line is read,
  and `STORE_VERSION` 2 re-reads stores written under the old rule.
