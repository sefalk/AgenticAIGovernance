### Added

- **Session start now checks that `AF_GH_TOKEN` is valid, not just present
  (#563).** The `session-mcp-readiness` hook runs `_gh_token_check.py`, which
  makes one `GET /user` request with a 4-second timeout. It reports the login
  and the expiry date from the `github-authentication-token-expiration`
  header. A warning goes at the front of the session context when the token is
  rejected (HTTP 401), expires within 14 days, or is unset while `.mcp.json`
  references it. Network errors are reported as `not verified` and never fail
  the hook. The token value is never printed. `AF_GH_API_URL` overrides the API
  base for GHES. The hook now also emits a top-level `additionalContext`, which
  is the form the Copilot harness passes to the model (#447).
  `test-gh-token-check.ps1` covers this against a local stub server.
