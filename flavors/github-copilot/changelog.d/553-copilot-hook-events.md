### Changed

- **Hook lifecycle attestation reads Copilot session evidence (#553, stage A).**
  The local integration check now selects an exact recorded workspace/session,
  pairs hook invocation ids and reports observed failures and durations without
  exposing hook inputs. Missing, ambiguous, malformed or incomplete evidence is
  explicitly inconclusive. The Local output-channel reader stays on the Local
  release line. Script identity, verdict and timeout-specific checks are named
  as unobservable rather than silently reported as passed. Automatic CLI CI
  attestation and its three licence cases remain open; the existing local-check
  attestation marker is retained.
