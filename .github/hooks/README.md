# Hooks for this repository's own development

This is not payload. The payload's hooks live under
`flavors/github-copilot/.github/hooks/` and are what a consumer project
receives. This file arms one of those guards for work done **on the framework
itself**, which #61 records as a gap: the framework ships safety hooks and
develops without them.

## What is armed

`block-dangerous` on `PreToolUse`, and nothing else. It is the guard whose
absence has the largest consequence — it hard-denies `git push --force`, any
push naming a protected branch, `git reset --hard`, `git rebase`,
`git branch -D` and `git add .` / `-A`.

## The point: no copy, no deploy

The `command` entries point **into** `flavors/`, at the scripts as they are
shipped. Nothing is copied to the repository root, so:

- there is no second version of a script that can drift from the first;
- `deploy.ps1` never runs against this repository, so the `CONFLICT` and
  `PROTECT` predictions that a self-deploy would produce (#105, #106) do not
  arise;
- no agents, instructions or skills are installed, so the untested question of
  how two payloads would take precedence never has to be answered.

That narrowness is deliberate. It is what makes the arrangement cheap enough
to be worth trying.

## Measured

The scripts work when invoked this way. Driven from the repository root with a
synthetic `PreToolUse` payload:

```
harmless command    (git status)              -> allow
force push          (git push --force ...)    -> deny
hard reset          (git reset --hard HEAD~1) -> deny
git add -A                                    -> deny
```

`block-dangerous.ps1` resolves its own location and its helpers relative to
where it sits, not to the current directory, so running it from a root that
has no payload beneath it changes nothing about its behaviour.

## Not yet measured

Whether VS Code loads this file at all from a repository that is not itself a
deployed payload, and whether it resolves the relative `command` paths against
this folder in a multi-root workspace. Both are answerable only by opening a
session and reading the hook log. Until that is done, treat this file as an
experiment, not as a guard you can rely on.

`chat.useCustomAgentHooks` must be `true` in `.vscode/settings.json` for any of
it to run. That setting is tracked, for exactly this reason.

## Deliberately not here

The payload's other session-wide guard, `scan-secrets`, is not armed. Its
`PostToolUse` payload shape was not exercised in the probe above, and arming a
hook that has not been shown to work would repeat the mistake this experiment
exists to avoid. Add it once it has been driven the same way.
