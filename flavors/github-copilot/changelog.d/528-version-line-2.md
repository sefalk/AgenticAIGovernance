### Changed

- **`dev` starts the 2.x line for the Copilot harness (#528).** The Local
  harness is deprecated in VS Code 1.146 and removed in February 2027. 1.28.6
  is the final Local feature release; the 1.28.x line continues on
  `release/local-1.28` with hotfixes only. Releases from `dev` are 2.x, so a
  version number now tells which harness line a deployment belongs to, and a
  `dev` release can no longer collide with a 1.28.x hotfix tag.
