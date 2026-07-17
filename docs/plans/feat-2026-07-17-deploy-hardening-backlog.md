# Deploy Hardening Backlog

- **Created:** 2026-07-17
- **Origin:** Findings from the MP 1.19.25 → 1.21.3 MCP redeploy (large-version
  jump with curated agents surfaced ordering + curation-merge gaps).
- **Rule:** Refine each measure's spec in this doc **before** implementing it.
  Check items off as they land. Each measure is its own branch/commit.

## Status

| # | Measure | Size | Branch | Status |
|---|---|---|---|---|
| 1 | Deploy-prompt reapply ordering (reapply AFTER resolve_conflicts) | small | `agent/deploy-prompt-ordering-fix` | DONE (pending merge) |
| 2 | Managed-block delimiter for curated agent skills | large | — | TODO (design first) |
| 3 | Skill-deactivation churn (deactivated framework skill = perpetual CREATE) | medium | — | TODO |
| 4 | curate-skills: warn on assignment to an agent without `## Skills` | small | — | TODO |
| 5 | curate-skills: separate framework-base skills from curation (researcher redundancy) | small | — | TODO |
| 6 | *(MP-local, not framework)* add 5 new `af-env.conf` keys (guard + ADO) | small | — | TODO (MP repo) |

---

## Measure 1 — Deploy-prompt reapply ordering  *(REFINED)*

### Problem
`deploy_prompt` in `mcp-deploy/af_deploy_mcp/prompts.py` runs the redeploy steps
as: `apply → reapply (5c/5d) → resolve_conflicts (6)`. For a **curated agent that
lands in CONFLICT** (happens on large version jumps), `apply` skips it, `reapply`
re-injects curation onto the **stale base**, then `resolve_conflicts` — if resolved
by taking the framework — **discards the just-reapplied curation**. Silent
curation loss; needs a second reapply. Validated manually in the MP redeploy.

### Fix (correct order — matches the validated manual run)
1. `apply` (CREATE/UPDATE; skips conflicts/customizable).
2. **[FIRST-TIME only]** onboard → initial curate (unchanged; first-time has no
   conflicts).
3. **Resolve conflicts** — merge each CONFLICT via `write_resolved`. For a
   **curated-agent conflict** (agent file carrying project skill lines), take the
   **framework base** (reapply restores curation next). Do not re-baseline yet.
4. **[REDEPLOY] Reapply curated skills** (`--reapply`) — restores curation on the
   **final** post-resolution base (covers both UPDATE'd agents and just-resolved
   conflict agents). Fallback to full `/af-curate-skills` if no
   `curated-assignments.json`.
5. **Re-baseline once** — `update_hashes` as the **final** step, so the sealed
   state (base + curation + resolved) becomes the baseline → future dry-runs show
   PRESERVE, not CONFLICT.
6. Report.

### Acceptance criteria
- [x] AC1: In `deploy_prompt` redeploy text, the resolve-conflicts step precedes
      the reapply step (order reversed vs. today).
- [x] AC2: A final `update_hashes`/re-baseline step appears AFTER reapply.
- [x] AC3: Text explicitly says curated-agent conflicts take framework base, then
      reapply re-adds curation.
- [x] AC4: First-time path (onboard → curate) unchanged and still before conflicts.
- [x] AC5: `test_prompts.py` asserts the new ordering; existing prompt tests pass.
      (`test_deploy_prompt_reapplies_after_conflict_resolution`; 69 passed, 1 skipped.)

---

## Measure 2 — Managed-block delimiter for curated agent skills  *(to refine)*

**Root cause of the whole "curated-agent CONFLICT" class.** Curation appends bare
`- **skill** (...)` lines into a non-customizable agent's `## Skills` section with
no delimiter, so every framework change to that agent → CONFLICT, and reapply
"regenerates" by appending (dup/drift risk). Idea: wrap curated skill lines in a
managed block (e.g. `<!-- AF:CURATED-SKILLS:START -->…<!-- END -->`) so the deploy
3-way merge and reapply treat base vs. curation independently. **Design decision
needed before code** (how deploy diff ignores the block; reapply idempotency;
migration of existing curated agents). Highest value.

## Measure 3 — Skill-deactivation churn  *(to refine)*
Deactivated framework skills (git-worktrees when `WORKTREE_ENABLED=false`) are
removed from `skills/` but remain in the framework payload → deploy re-offers them
as CREATE on every run. Need a way to record "intentionally deactivated" so the
deploy suppresses the CREATE (e.g. a deactivated-skills list the deploy honors).

## Measure 4 — curate-skills: warn on skill-less agent assignment  *(to refine)*
`curated-assignments.json` mapped `coordinator → databricks-execution-efficiency`,
but the coordinator has no `## Skills` section → reapply silently drops it. The
curate/reapply flow should warn (or refuse) when an assignment targets an agent
that has no `## Skills` section.

## Measure 5 — curate-skills: base vs. curation skills  *(to refine)*
The framework `researcher` already lists data-* skills as **base** skills, yet
`curated-assignments.json` redundantly assigns them → confusion / apparent
conflicts. curate-skills should distinguish framework-base skill lines from
curation-added ones (e.g. only manage lines inside the managed block from #2).

## Measure 6 — MP `af-env.conf` new keys  *(MP-local)*
MP's `af-env.conf` lacks 5 framework keys it should adopt (values project-set):
`LARGE_FILE_MAX_BYTES`, `LARGE_FILE_ALLOWLIST`, `ADO_REPOSITORY_NAME`,
`ADO_DEFAULT_TEAM`, `ADO_PR_MERGE_STRATEGY`. Additive merge in the MP repo (not
an AAIG framework change).
