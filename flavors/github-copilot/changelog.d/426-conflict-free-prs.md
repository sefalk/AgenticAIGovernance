### Changed

- **Parallel pull requests no longer conflict by construction (#426).** Every
  pull request changed the same two places: the pre-commit hook bumped the
  patch number in `VERSION` on every framework commit, and every entry was
  inserted at the top of `[Unreleased]`. Two open pull requests therefore
  always conflicted, and the second needed a manual merge before it could land.
  - Changelog entries are fragments: `changelog.d/<issue>-<slug>.md`, one per
    pull request. `.github/scripts/changelog-fragments.py check` validates them
    (F001–F006); `assemble --version X.Y.Z` is the release cut, folding
    `[Unreleased]` and every fragment into one version section and setting
    `VERSION`.
  - `.githooks/pre-commit` no longer bumps `VERSION`. It refuses a commit that
    stages `CHANGELOG.md` without `VERSION`, except while resolving a merge.
    CI applies the same rule to the pull request (`check --against`, F007).
  - A deploy records the source commit in `.github/.af-version` (`commit:
    <sha12>`, `-dirty` for uncommitted tracked changes) on all three paths.
    `af_status` compares commits when both sides have one, so `stale` still
    means "the source moved since this deploy" while `VERSION` stays put. A
    payload that is not a tracked part of a checkout (the wheel's bundled copy)
    records no commit and is compared by version, as before.
  - `deploy.ps1` no longer warns "VERSION is still X but N file(s) changed":
    between release cuts that is the normal state.
  - The preamble of `CHANGELOG.md` still describes the old procedure; the next
    release cut rewrites it, since only a cut may edit that file.
