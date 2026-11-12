### Added

- **The two release lines can no longer mix unnoticed (#537).** `dev` (2.x, Copilot harness) and `release/local-1.28` (1.28.x, Local harness) are worked by separate sessions. CI now refuses a pull request into either line that brings a commit of the other. A change both lines need is implemented on each line separately; a cherry-pick passes. Only an explicit, urgent owner decision may cross, declared in the body as `cross-line: <reason>`.
