# Branch rulesets

Exports of the rulesets that govern `dev` and `main`. Both branches report
`"protected": true` since these were imported; before that, both were `false`.

| File | Target | What it enforces |
|---|---|---|
| `dev-branch-ruleset.json` | `refs/heads/dev` | Pull request required, status check required and strict, merge commits only, no force-push, no deletion |
| `main-branch-ruleset.json` | `~DEFAULT_BRANCH` | The same, on the release branch, without the strict policy |

## What `dev` guarantees, and what it does not

Every commit on `dev` has been through `Regression suites (Windows PowerShell
5.1)` **against the base it actually landed on**. That second half is what
`strict_required_status_checks_policy: true` buys, and it is not decoration:
since #150 an armed pull request merges itself, and since a merge performed
with `GITHUB_TOKEN` triggers no further workflow runs, the `push: [dev]` run
that used to re-test the result no longer happens for automated merges. Without
the strict policy, a pull request could merge on a check measured against a
base that had moved, and nothing would ever test the combination.

The cost lands on concurrency: when the base moves, an armed pull request stops
until its branch is updated. It stalls visibly instead of merging something
untested.

`main` does not carry the strict policy. It moves only on release pull requests
that a human merges, so there is nothing for a check to be stale against.

## These files are a record, not the source of truth

GitHub does not read them. A maintainer imports them by hand under
*Settings → Rules → Rulesets → Import a ruleset*. If the live ruleset is edited
in the UI and the file is not updated, the two drift apart and **nothing
detects it** — at which point the file is worse than nothing, because it looks
authoritative while being stale. Change the settings page and this directory in
the same breath, or not at all.

Closing that gap needs a check comparing these exports against the live
rulesets through the API. That is deliberately not built (see #147).

## Two couplings worth knowing

**The status check context is a job name.** `Regression suites (Windows
PowerShell 5.1)` is matched by string against the `name:` of the job in
`.github/workflows/regression.yml`. Rename the job and every pull request waits
forever on a check that no longer reports — the gate stalls rather than fails,
which is the harder failure to notice.

**`allowed_merge_methods` is pinned to `merge`.** Squash produces a commit that
does not contain the feature branch tip, so the post-merge
`git branch -d agent/*` fails as "not fully merged". The same constraint is
recorded in `ado-pr-manager`.

## What the rulesets cannot do

`Allow auto-merge` is a repository-wide setting, and a single maintainer cannot
require an approving review on `main` without deadlocking it — you cannot
approve your own pull request. So "`main` is human-only" rests on agent policy,
not on anything enforced here.
