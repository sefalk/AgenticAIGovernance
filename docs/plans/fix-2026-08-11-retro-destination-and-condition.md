<!-- copilot:generated | planner | 2026-08-11 -->

# Fix: one retro destination, and a retro only when there is something to learn

- **Issues:** [#98](https://github.com/sefalk/AgenticAIGovernance/issues/98),
  [#27](https://github.com/sefalk/AgenticAIGovernance/issues/27) (child of #22)
- **Branch:** `agent/98-27-retro-destination-and-condition`
- **Base:** `dev` @ `e6fe5fe`
- **Complexity tier:** Standard
- **Status:** COMPLETED

## Problem

Two issues about the same artifact, deliberately taken together: #98 asks
*where* the retro goes and whether it is committed, #27 asks *whether it is
written at all*. Fixing one without the other would touch the same four hook
scripts and the same two agent files twice.

### #98 — the premise has partly expired

The issue measured a deployed payload at `1.21.43` and found
`documenter.agent.md` naming two destinations. **That contradiction no longer
exists in source.** Every reference now names `.github/retros/auto/`:

| File | Lines |
|---|---|
| `agents/documenter.agent.md` | 63, 159, 163, 207, 208, 222, 249, 268 |
| `agents/compliance-checker.agent.md` | 84, 128, 211 |
| `agents/coordinator.agent.md` | 314 |
| `prompts/af-retro-summary.prompt.md` | 11, 26, 29 |

`.github/retros/auto/.gitignore` (`*` + `!.gitignore`) also ships. The
consumer measured it absent because `1.21.43` predates the commit that added
it, not because the deploy drops it.

So the source already implements **Variant A** (retros are local
instrumentation), with the rationale recorded in the CHANGELOG: split by
author — agent-generated retros are ignored, hand-written retrospectives one
level up stay the project's choice.

**What actually survives in source is narrower and more interesting:** the four
Stop hooks still accept *either* path.

```powershell
# documenter-stop.ps1:91-92        # stop-tests.ps1:55-56
$retroPath1 = ".github/retros/auto/$workflowId.md"
$retroPath2 = "retros/auto/$workflowId.md"
```

Same in `documenter-stop.sh:81` and `stop-tests.sh:53`. That fallback is the
only mechanism keeping the split reachable, and it is precisely why nobody
noticed: the gate passes either way, so a documenter writing to the wrong
place is indistinguishable from one writing to the right place. A tolerant
gate does not resolve an ambiguity, it *preserves* it — and then the evidence
of the divergence (48 files at the root, 35 of them tracked) accumulates
silently in the consumer.

Three stale references remain outside the agent prompts: `README.md:145`,
`agent-framework-map.v2.html:803`, `retros/README.md:36`.

### #27 — the retro is written for every workflow

The retro is a HARD gate, so it is produced whether or not anything happened:
34 files measured, ~2,485 B ≈ 621 tokens each. A clean run records that
nothing went wrong, and Step 0 of the next workflow reads it back as input.

The issue proposes writing one only when `retries > 0`, `escalations > 0`, a
critic returned REJECTED/ESCALATE, or a HARD gate was BLOCKED.

## Approach

### A. One destination, and a legacy path that is named rather than accepted

Collapse the dual check in all four hooks to `.github/retros/auto/` only. A
retro found at the legacy root path is **not** accepted, but it is *reported*:
the message says the file was found at `retros/auto/` and must move. Silent
rejection would be as unhelpful as silent acceptance — the consumer with 48
files needs to be told what to do with them, not merely failed.

### B. The condition is derived from the log, not declared by the documenter

The obvious reading of #27 is "let the documenter skip the retro when the run
was clean". That would make the exemption a self-report — the same channel
#91 closed for timestamps, where a documenter declared "zero fabricated data"
in the output containing an invented one.

So the hook decides. It reads the workflow log it has *already verified
exists* and looks for the trigger conditions. Shared helper
`Get-AfRetroRequirement` / `af_retro_required`, alongside
`Get-AfPlanLifecycle`.

### C. Skipping must be positively established

The helper requires a retro **unless** it can positively read `retries: 0`
*and* `escalations: 0` *and* find no REJECTED / ESCALATE / BLOCKED. A log that
is missing, unreadable, or still carrying the unfilled `retries: <number>`
template does **not** license the skip.

Absence of evidence is not evidence of a clean run. Inverting that default is
the whole difference between an exemption and a hole — and it is the same
mistake as an assertion that passes on nothing (#96), one release earlier.

### D. Follow the condition everywhere the gate is asserted

`documenter.agent.md` (write rule + exit gate), `compliance-checker.agent.md`
(post-flight gates at L128 and L211), `stop-tests.*`. A clean run stays
identifiable as clean from the log, which already carries
`summary.retries` and `summary.escalations`.

### E. Deploy-time check that the `.gitignore` landed

#98's last bullet. The retro directory without its `.gitignore` is the
committed-by-accident case the issue measured.

## Subtasks

1. Shared helper + hooks: `_common.ps1` / `_common.sh`, four Stop hooks —
   canonical path only, legacy path named, retro required only when the log
   does not positively show a clean run.
2. Agent prompts: `documenter.agent.md`, `compliance-checker.agent.md`.
3. Stale references + deploy-time `.gitignore` check.

## Risks

| Risk | Mitigation |
|---|---|
| A clean-run skip becomes a hole if the log is unreadable | C: the skip requires positive evidence; anything else requires the retro |
| Consumers with retros at the legacy path start failing the gate | A: the message names the file and the destination, so the failure is actionable |
| The trigger scan matches the word BLOCKED inside prose in the log | Anchor on the gate/verdict fields, and assert a case where the word appears in a task summary |

## Mutations to attempt

1. Restore the legacy path in the PowerShell hook → the canonical-only case goes red.
2. Invert C (skip when the log cannot be read) → the unreadable-log case goes red.
3. Treat the unfilled `retries: <number>` template as clean → that case goes red.
4. Drop the REJECTED trigger → the rejected-verdict case goes red.
5. Drop the legacy-path *message* while keeping the rejection → the migration-note case goes red.

## Results

`test-hooks.ps1` 233 → **238 pass / 7 fail** at Red → **250 / 0** at Green.
`test-hooks.sh` **132 / 0**. Twelve new PowerShell assertions, twelve new bash
assertions, five static claims that the same edit reached the `.sh` side.

The seven reds were exactly the claimed properties: the legacy root path still
satisfied the gate in three places, a clean run was still forced to write a
retro, the words in the trigger prose still forced one, and `stop-tests` both
warned about a retro nobody owed and accepted the legacy path.

Five mutants, five killed, each at the assertion it was aimed at:

| Mutant | Result | Killed |
|---|---|---|
| M1 restore the legacy path in the PowerShell hook | 247/3 | canonical-only + both migration messages |
| M2 skip when the log cannot be read | 242/8 | every case that owes a retro |
| M3 treat `retries: <number>` as clean | 249/1 | the unfilled template |
| M4 drop the adverse-verdict condition | 249/1 | the REJECTED verdict |
| M5 drop the legacy-path message, keep the rejection | 248/2 | both migration messages |

M4 and M5 did not kill anything on the first attempt. Both survivals were
defects in the assertions, not in the product — see Notes.

## Notes

**The contradiction the issue reported was already gone.** #98 cites a
documenter that names `retros/auto/` in one place and `.github/retros/auto/` in
another; measured against source, every reference in every agent file already
said `.github/`. What survived was the gate underneath, which accepted *either*
path — and that is the more interesting defect, because a gate that accepts
both answers does not resolve the ambiguity it exists to resolve, it preserves
it. A documenter writing to the wrong place was indistinguishable from one
writing to the right place, and the file it left behind sat outside the
`.gitignore` that keeps generated retros out of the repository. The consumer
repo where this was measured has a payload from `1.21.43`, which predates the
commit that added that `.gitignore` at all.

**Variant A was chosen without the decider.** The prior agreement was Variant B
(move the canonical location to the repository root). Asked to confirm the
switch, the human was unavailable. B would have reversed a shipped,
CHANGELOG-documented decision while the person who made it could not be asked;
A keeps the shipped location, is the conservative direction, and stays
reversible. Recorded here so the choice is reviewable rather than merely
executed.

**Two assertions passed on the wrong thing, and mutation testing is the only
reason that is known.** M5 removed the message that names the legacy file while
keeping the rejection, and the suite stayed green: the assertion looked for
`retros/auto/72-x.md`, which is a *substring of the canonical path*, so the
generic message that names no file at all satisfied it. M4 removed the
adverse-verdict condition and the REJECTED case still went red — but for the
wrong reason: the fixture appended its `steps:` block to a here-string with no
trailing newline, so it landed on the `escalations: 0` line and the case was
failing on an unreadable counter, never reaching the verdict at all. Both are
the same failure as the one this issue is about: an artifact that looks like
evidence and is not.

**A CRLF anchor bug cost one Green cycle.** The counter regexes ended with
`[^\S\r\n]*$`, which cannot match the `\r` of a CRLF line: in .NET multiline
mode `$` sits *between* `\r` and `\n`. Every log written on Windows read as
"the log does not record `escalations: 0`" — the REQUIRED default doing its job
and hiding the bug behind a plausible reason. Fixed by ending both with `\s*$`.

**The Red assertion for the exemption had to be tightened before it was
committed.** `Assert-Contains $clean.Output 'retro'` passed at Red, because the
existing block message already contains "retro snippet". A red test that would
have passed for an unrelated reason proves nothing about what turns it green.
