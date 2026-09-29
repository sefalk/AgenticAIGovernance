# Hooks for this repository's own development

This is not payload. The payload's hooks live under
`flavors/github-copilot/.github/hooks/` and are what a consumer project
receives. This file arms one of those guards for work done **on the framework
itself**, which #61 records as a gap: the framework ships safety hooks and
develops without them.

## Why `hooks-dev/` and not `hooks/`

VS Code loads `.github/hooks` from **every** folder of a window. In a
multi-root window holding this repository and a consumer, this hook therefore
ran on every tool call of the consumer's work too: about 2.5 s extra per call,
judged against this repository's policy instead of the consumer's (#345).

It now lives outside the default location and is enabled only by
`chat.hookFilesLocations` in this repository's `.vscode/settings.json`. That
setting has no resource scope, so it applies when this repository is opened
**on its own**. In a multi-root window VS Code does not read window settings
from a folder's `.vscode/settings.json`, so the hook is not loaded there. Both
halves were decided on #345 to be checked live before merge. The outcome is
recorded below under *Scoped to its own window*.

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

## It works, and this is the evidence

VS Code does load this file, from a repository that is not itself a deployed
payload. Measured in a reloaded window whose workspace holds this repository
alongside an unrelated project that has the payload deployed the normal way:

```
  14x  PreToolUse: 2 hook(s)
  12x  PostToolUse: 1 hook(s)

  13x  1925ms avg  PreToolUse  [AgenticAIGovernance]
                   ... -File flavors/github-copilot/.github/hooks/scripts/block-dangerous.ps1
  13x  2034ms avg  PreToolUse  [MP Usage XP at Teamplay]
                   ... -File .github\hooks\scripts\block-dangerous.ps1
  12x  1948ms avg  PostToolUse [MP Usage XP at Teamplay]
                   ... -File .github\hooks\scripts\scan-secrets.ps1
```

Three things follow, and only the first was in doubt:

- **The relative `command` path resolves against the folder that declares it.**
  The hook ran with `cwd` set to this repository, not to the folder of the file
  being edited. That is what makes pointing into `flavors/` viable at all.
- **Hooks from different workspace folders compose additively.** Every
  `PreToolUse` ran exactly two hooks, one per folder, with no duplication and
  no folder suppressing the other.
- **`PostToolUse` ran one hook**, because this file declares none. The absence
  is as informative as the presence: nothing is being inherited that was not
  declared here.

`chat.useCustomAgentHooks` must be `true` in `.vscode/settings.json` for any of
it to run. That setting is tracked, for exactly this reason.

## What it costs, and what it does not prove

Roughly 1.9 s per tool call, spent before the tool runs. That is PowerShell
startup, not analysis. In a window that also has a payload deployed, the two
guards together add about 4 s to every `PreToolUse`.

Not proven until 2026-09-29: that the guard *denies* in this arrangement. The
deny paths had only been demonstrated by driving the script directly. The first
live deny is recorded under *Scoped to its own window* below.

Note also that this hook sees **every** tool call in the window, including
calls that concern the other workspace folder, and it sees them with its own
`cwd`. For a guard that classifies the command string that is harmless, and
arguably desirable. For any future hook here that inspects the working tree, it
would not be.

## Scoped to its own window (#345)

**Opened alone: the dev hook runs, and it denies live.** On 2026-09-29 a new
window opened on this folder only, and the agent was asked to run
`git rebase --abort`. That window's hook log shows exactly one PreToolUse hook,
this one, with `cwd` in this repository. It returned the deny, and the chat
reported the command as blocked:

```
[#0] [PreToolUse] Executing 1 hook(s)
[#0] [PreToolUse] Running: powershell -NoProfile -ExecutionPolicy Bypass -File flavors/github-copilot/.github/hooks/scripts/block-dangerous.ps1
[#0] [PreToolUse] Output: {"hookSpecificOutput":{"permissionDecision":"deny", ... "Policy hard-deny: rebase (history rewrite)..."}}
```

So `chat.hookFilesLocations` from this folder's settings loads `hooks-dev/`.
The command is harmless on purpose: without a rebase in progress, git would
only have reported an error had the hook not fired.

**Multi-root window with a consumer: the dev hook does not run.** On
2026-09-29 the multi-root window (this repository + MPUsageXPTP) was reloaded
with this layout checked out. Same hook log, split at the reload (sequence
`#3687 -> #0`, 15:19:41):

| | PreToolUse calls | dev hook runs |
|---|---|---|
| before reload (`.github/hooks/`) | 547 | 526 |
| after reload (`.github/hooks-dev/` + setting) | 12 | **0** |

The folder's window setting is ignored in a multi-root window, as assumed, so
the fallback (#345, option B) is not needed.

## Deliberately not here

The payload's other session-wide guard, `scan-secrets`, is not armed. Its
`PostToolUse` payload shape was not exercised in the probe above, and arming a
hook that has not been shown to work would repeat the mistake this experiment
exists to avoid. Add it once it has been driven the same way.
