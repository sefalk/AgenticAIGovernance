### Fixed

- **A merge-forward of a hotfix release no longer fails the changelog gate (#535).** `changelog-fragments.py check --against` refused any `CHANGELOG.md` change without a `VERSION` change, so bringing `release/local-1.28` into `dev` (which keeps its own 2.x `VERSION`) failed CI. It now also passes when every section of the merge base is unchanged and each new `## [X.Y.Z]` section is identical to the one tag `vX.Y.Z` holds; a top-insert into `[Unreleased]` is still refused.
