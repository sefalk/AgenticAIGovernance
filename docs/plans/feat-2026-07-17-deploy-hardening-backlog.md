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
| 2 | Managed regions (general, sparing) + apply to curated agent skills | large | `agent/managed-regions` | DONE (2a–2d) — pending merge |
| 3 | Skill-deactivation churn (deactivated framework skill = perpetual CREATE) | medium | — | TODO |
| 4 | curate-skills: warn on assignment to an agent without `## Skills` | small | `agent/managed-regions` | DONE (folded into 2c-ii, Step 8 validation) |
| 5 | curate-skills: separate framework-base skills from curation (researcher redundancy) | small | — | FOLDED into #2 (2c AC7) |
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

## Measure 2 — Managed regions (general, sparing)  *(REFINED)*

### Decisions (confirmed with human 2026-07-17)
- **Concept approved.** A deployed file may contain **managed regions** whose
  inner content is project-owned; the deploy ignores that content when deciding
  UPDATE/CONFLICT and preserves it on write.
- **General mechanism, used sparingly.** Allowed in any deployable file, but it
  is a *last resort*. **Prefer `af-env.conf` for project-specification whenever
  possible** — managed regions are only for per-project content that cannot be
  expressed as config (e.g. curated skill lines injected into agent prose).
- **First (only current) consumer:** the curated-skills block in agent
  `## Skills` sections. This also resolves #5 (base vs. curation now delimited).

### Marker syntax
```
<!-- AF:MANAGED:{region-name}:START -->
   ...project-owned content...
<!-- AF:MANAGED:{region-name}:END -->
```
Detection is comment-wrapper-agnostic (match a line containing
`AF:MANAGED:{name}:START` / `:END`), so the same mechanism works for `#`, `//`,
`<!-- -->` hosts later. Framework source ships the region **empty** (markers
only) as the slot.

### Deploy semantics (the core)
- **Hash for classification** = the file with every managed region **normalized
  to empty** (inner content stripped, markers kept). Applied to BOTH source and
  target → content inside a region never causes UPDATE/CONFLICT.
- **Write on UPDATE** = take the framework source, then **transplant the
  target's current region content** into each same-named region (preserve
  project content); framework changes outside regions still land.
- **CREATE** = framework version (region empty/template).
- Must be **byte-parity across deploy_core, deploy.ps1, deploy.sh** and coexist
  with tier-token resolution + EOL/BOM canonicalization.

### Sub-steps
- **2a — Core mechanism (deploy_core, TDD) — ✅ DONE (7 tests, dormant until 2b/2c):**
  region parse + `normalize_regions`
  (empty for hashing) + `merge_regions` (transplant target content on write);
  wire into `source_hash_resolved`/`resolved_source_bytes` classification and the
  apply write path. Unit tests: region content change → UNCHANGED; base change →
  UPDATE; update preserves target region; malformed/again-empty regions safe.
- **2b — Parity (deploy.ps1 + deploy.sh):** same region-aware hash + write;
  extend the cross-tool parity test with a region fixture.
  - **2b-ps1 — ✅ DONE (VERSION 1.21.6):** `Strip-ManagedRegions`/`Merge-ManagedRegions`
    via `[regex]::Replace` + `Get-SourceHashResolved`/`Get-TargetClassifyHash` stripped +
    `Publish-SingleFile` merges target region on write. AST-based byte-parity test
    (`test_ps_managed_regions_parity.py`, 11 tests) vs `deploy_core` — green locally.
  - **2b-sh — ✅ DONE (locally verified with Git-for-Windows gawk 5.0):** awk
    state-machine `_AWK_STRIP`/`_AWK_MERGE` (join model + `od`-based trailing-newline
    handling) + `source_hash_resolved`/`target_classify_hash` stripped + `write_deployed`
    merges target region. `test_sh_managed_regions_parity.py` extracts the real awk
    programs and asserts byte-parity vs `deploy_core` — 9/9 green under gawk; `bash -n`
    clean. Skipped where awk is absent; runs in Linux CI. Engine contract: operates on
    **canonical LF bytes only** (`canonical_write` strips CR/BOM first), so no CRLF case.
  - **Option B (follow-up, not blocking):** full end-to-end `deploy.sh` run under a
    local bash/WSL was not completed here — the existing `test_sh_deploy_then_mcp_dryrun_is_clean`
    aborts under Git-bash-on-Windows because `get_current_git_branch` +
    `set -euo pipefail` returns 128 when the **target is not a git repo** (pre-existing,
    unrelated to regions; passes in Linux CI). Tracked as a GitHub issue (see below).
- **2c — Curated-skills consumer (REFINED, grounded in real agent format):**
  - **Region placement:** HTML-comment markers (invisible in rendered md) at the
    **end of the base bullet list** inside `## Skills`, before the trailing blank
    line / next `## ` heading. Empty by default (START/END on adjacent lines):
    ```
    ## Skills

    Consult these skills when relevant to the task:
    - **base-a** (`skills/base-a/SKILL.md`) — …
    <!-- AF:MANAGED:curated-skills:START -->
    <!-- AF:MANAGED:curated-skills:END -->

    ## Next Heading
    ```
  - **2c-i — payload markers:** add the empty region to the **13** framework
    agents that have a `## Skills` section (all except `coordinator` and
    `compliance-checker`). One-time framework UPDATE on next deploy; thereafter
    region content is CONFLICT-free (stripped for classification). Never-curated
    projects stay UNCHANGED (empty region strips to itself). HTML comments are
    inert.
  - **2c-ii — prompt logic (`af-curate-skills.prompt.md`):** rewrite Step 7
    (agent update), **Reapply Step 4**, and **Rollback Step 4** to *replace the
    region body* with the agent's curated skill lines (full idempotent replace,
    not append). Defensive migration: also strip any **bare** curated lines
    (those matching `assignments`) found OUTSIDE the region.
  - **Migration is mostly free:** the bare→region transition is handled by the
    **existing deploy workflow** (measure #1) — curated agents hit CONFLICT →
    resolve-to-framework (yields the empty region) → reapply fills it. No
    dedicated migration script; reapply’s defensive strip covers the rest.
  - **Region-vs-base dedup (AC7, promoted-curation guard):** when building the
    region, skip any assigned skill already referenced in the agent’s **base**
    Skills lines (match on `skills/{name}/`). Prevents duplication when a curated
    skill is promoted into the framework base; auto-drops it from the region on
    the next reapply (and from `curated-assignments.json`). The live researcher
    case from the MP redeploy. **Consolidates #5.**
  - **2c-iii — tests:** structural test that every shipped agent’s region is
    well-formed + empty; classification test that a region-filled agent is
    UNCHANGED vs the empty-region framework source via `deploy_core` (the prompt
    itself is agent-executed, not unit-testable — the mechanism + payload shape
    are what we gate).
- **2d — Guidance — ✅ DONE:** `copilot-authoring.instructions.md` gains a
  **Managed Regions** section (mechanism + syntax + the **“sparing, prefer
  af-env.conf”** rule); CHANGELOG `Added` entry covers the whole feature.

### Acceptance criteria
- [x] AC1: A file whose only diff is inside a managed region classifies
      UNCHANGED (both tools). *(deploy_core + ps1 + sh parity tests)*
- [x] AC2: A base (outside-region) change classifies UPDATE; applying it
      preserves the target's region content. *(region tests, all three tools)*
- [x] AC3: deploy_core, deploy.ps1, deploy.sh produce byte-identical results on
      a region fixture (cross-tool parity test). *(ps1 AST test + sh awk test, both green locally)*
- [x] AC4: curated-skills writes/reapplies only inside the region; repeated
      reapply is idempotent (no duplication). *(2c-ii: full region-body replace, never append)*
- [x] AC5: existing bare-curated agents migrate into the region once.
      *(deploy conflict→resolve→reapply + 2c-ii defensive bare-line strip)*
- [x] AC6: guidance documents sparing use + af-env.conf preference.
      *(2d: `copilot-authoring.instructions.md` → Managed Regions section)*
- [x] AC7: region-vs-base dedup — a curated skill that is now in the agent's
      base Skills section is NOT written into the region (no duplication).
      *(2c-ii Step 7 base dedup + drop from assignments)*. Consolidates #5.

### Open micro-decisions (my defaults unless you object)
- Migration lives in `/af-curate-skills --reapply` (detect bare curated lines →
  wrap) rather than a separate script. *(default)*
- One region per agent (`curated-skills`) for now; multiple regions per file
  supported by the mechanism but unused. *(default)*

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

## Discovered issues (GitHub-tracked)

### [GH #1](https://github.com/sefalk/AgenticAIGovernance/issues/1) (Option B): deploy.sh local bash/WSL e2e verification + `get_current_git_branch` non-repo hardening
Filed via GitHub MCP on 2026-07-20. Covers **Option B** (full local e2e
verification of `deploy.sh`) plus the pre-existing bug discovered during 2b:
`get_current_git_branch` aborts under `set -euo pipefail` when the target is not
a git repo (exit 128; unrelated to regions; passes in Linux CI). Not blocking —
the region engine itself is byte-parity-verified locally (gawk 5.0).
