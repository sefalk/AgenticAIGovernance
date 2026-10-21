# Changelog fragments

> copilot:generated | coordinator | 2026-10-21

One file per pull request, folded into `../CHANGELOG.md` at the release cut
(#426). Do not edit `CHANGELOG.md` in a pull request: every such edit inserts
at the same place, so any two open pull requests conflict on it. The
pre-commit hook and CI refuse a `CHANGELOG.md` change that does not also
change `VERSION`, which only a release cut does.

## Name

`<issue>-<slug>.md`, slug in lowercase `a-z0-9-`, e.g. `426-conflict-free-prs.md`.
Fragments are ordered by issue number inside each section.

## Content

Only `###` sections with one of the six Keep a Changelog kinds, each at most
once, each non-empty. No `##` heading, and no text before the first `###`.

```markdown
### Fixed

- **What changed, for whom (#426).** Why it matters, in the style of the
  existing entries.
```

## Check and release

```powershell
python .github/scripts/changelog-fragments.py check                 # every fragment
python .github/scripts/changelog-fragments.py check --against origin/dev
python .github/scripts/changelog-fragments.py assemble --version X.Y.Z --dry-run
```

`assemble` moves `[Unreleased]` and every fragment into `## [X.Y.Z] -- <date>`,
sets `VERSION` and deletes the fragments. The release cut is described in the
deployment skill.
