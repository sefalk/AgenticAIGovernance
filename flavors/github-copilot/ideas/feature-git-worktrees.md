# Feature: Git Worktrees for Parallel Agent Task Execution

**Status:** 🔄 IN PROGRESS — Phase 1 (Spec) complete 2026-04-14  
**Created:** 2026-04-14  
**Owner:** User Request  
**Type:** Enhancement (git-workflow)

---

## 1. Problem Statement

Current workflow forces sequential task execution on a single branch/checkout:
- Only one agent task can run locally at a time.
- Switching between branches stashes/restores working directory repeatedly.
- Human developer cannot make local changes without interference.
- Coordination overhead and cognitive load increase.

**Goal:** Enable true parallel execution of multiple agent tasks + independent human work on the main checkout.

---

## 2. Solution: Git Worktrees

### 2.1 How It Works

A **worktree** is an additional working directory tied to a single git repository.

- **Shared repository:** `.git` directory is shared (single history).
- **Isolated checkouts:** Each worktree has its own branch and file state.
- **Lifecycle:** Create from main/dev → work on agent/{task-id} → merge → destroy.

Example structure:
```
repo/                         (main checkout, on dev)
├── .git                      (shared)
├── mpfdact/
├── tests/
└── ..

wt/                           (worktrees subdirectory)
├── wt/agent-feature-x        (agent/feature-x branch)
├── wt/agent-fix-y            (agent/fix-y branch)
└── wt/...
```

Each worktree can be worked on independently; commits flow to the same repository history.

### 2.2 Lifecycle

1. **Create:** Planner/Coordinator creates worktree for new `agent/{task-id}` branch.
   - Base: `git worktree add ../wt/{task-id} -b agent/{task-id} dev`
   - Path: `../wt/{task-id}` (sibling to main checkout).
   - Bootstrap: ensure venv, deps, hooks setup.

2. **Work:** All task-specific agents (test-writer, implementer, refactorer) run in worktree.
   - Commits stay branch-scoped.
   - Coordination hooks verify context (branch + worktree mismatch).

3. **Merge (Human):** Human merges to dev in main checkout.
   - `git merge --no-ff agent/{task-id}` from main repo.
   - No rebase by agents (prevents drift).

4. **Cleanup:** Coordinator removes worktree after successful merge.
   - `git worktree remove ../wt/{task-id}`
   - Verify no uncommitted changes before removal.
   - Prune dangling references: `git worktree prune`.

---

## 3. Architecture Changes

### 3.1 Coordinate: Startup Phase

**New step BEFORE Red (test writing):**

```
Step 0d: Worktree Bootstrap
  - Coordinator: `git worktree add ../wt/{task-id} -b agent/{task-id} dev`
  - Verify: worktree created, branch exists, .github/ hooks present.
  - Setup: run venv bootstrap (if new), ensure .python-version or .venv symlink.
  - Document: record worktree-id in plan metadata.
  - Status: READY (proceed to test-writer).
```

### 3.2 Agent Context: Proof-of-Presence

All agents (in every pre-tool use hook and critical stop gates) verify:
1. **Branch check:** `git branch --show-current` contains `agent/`.
2. **Worktree check:** `git rev-parse --git-common-dir` matches expected repo structure.
3. **Mismatch:** Halt with escalation — agent is in wrong context.

### 3.3 Coordinator: Shutdown Phase

**New step AFTER human merge:**

```
Step 8: Worktree Cleanup (Coordinator)
  - Verify merge completed (human confirms).
  - Git status in worktree: must be clean.
  - Coordinator: `git worktree remove ../wt/{task-id}`
  - Verify removal success + prune dangling references.
  - Document: record cleanup + final commit hash.
  - Archive: symlink/note for post-workflow retrospective.
```

---

## 4. Gate Matrix: Soft & Hard Gates

All gates are **HARD** (mechanically enforced) unless marked SOFT.

### 4.1 Coordinator: Worktree Creation (Pre-Tool Use Hook)

| Gate | Type | Check | Enforcement |
|---|---|---|---|
| Branch name valid | HARD | `agent/{workflow-id}` matches slug | Regex: `^agent/[a-z0-9-]+$` |
| Worktree path collision | HARD | `../wt/{task-id}` does not exist | `git worktree list` grep |
| Repo health | HARD | Main repo `.git` is valid | `git status` in main checkout |
| Dev branch exists | HARD | `dev` branch exists and is clean | `git rev-parse refs/heads/dev` |

**On violation:** `deny` decision; error message includes remediation step.

### 4.2 All Agents: Context Proof (Per-Tool Use or Pre-Commit)

| Gate | Type | Check | Enforcement |
|---|---|---|---|
| Current branch is agent/* | HARD | `git branch --show-current \| grep -q '^agent/'` | Stop hook: block any commit/terminal command if false |
| Worktree is active | HARD | `git rev-parse --git-common-dir` points to shared `.git` | Pre-tool use: block file edits if worktree context invalid |
| No cross-worktree contamination | HARD | PWD matches worktree path in git metadata | Stop hook: verify ENV or file marker |

**On violation:** Escalate to human with context dump (current branch, PWD, expected worktree).

### 4.3 Coordinator: Worktree Cleanup (Post-Merge Gate)

| Gate | Type | Check | Enforcement |
|---|---|---|---|
| Merge completed | SOFT | Human confirms merge to dev | Manual checkpoint (user narrates) |
| Worktree is clean | HARD | `git status --porcelain` empty in worktree | Coordinator checks before removal |
| Stale worktrees list | SOFT | `git worktree list` shows no orphaned entries | Informational alert if found |
| Removal succeeded | HARD | `git worktree remove` exit code 0 | Retry logic: if locked, suggest `git worktree unlock` |

**On HARD violation:** WIP checkpoint; halt and escalate to human.

---

## 5. Implementation Roadmap

### Phase 1: Spec & Documentation (2-3 files)

- [ ] Extend `git-workflow.instructions.md` with new sections:
  - Worktree lifecycle (create → work → merge → remove).
  - Path conventions (`../wt/{task-id}`).
  - Bootstrap steps (venv, hooks, context verification).
  - Error recovery (stale worktrees, unlock, cleanup).
  
- [ ] Update `coordinator.agent.md`:
  - Add Step 0d: Worktree Bootstrap (between planning and Red).
  - Add Step 8: Worktree Cleanup (after merge confirmation).
  - Subagent context injection: include worktree-id metadata.

- [ ] Create `skills/git-workflow-worktrees/SKILL.md`:
  - Troubleshooting guide (locked worktrees, merge conflicts).
  - Recovery procedures (stale worktree recovery, re-sync).
  - Performance considerations (large repos, network shares).

### Phase 2: Hard Gates (4 hooks)

- [ ] `coordinator-pretooluse.ps1/.sh`: Verify worktree creation preconditions.
  - Branch name, path collision, dev health.
  - Error: deny with remediation.

- [ ] All agent `*-pretooluse.ps1/.sh`: Verify branch + worktree context before file edits.
  - Check: `git branch --show-current` and PWD consistency.
  - Error: deny; escalate context dump.

- [ ] All agent `*-stop.ps1/.sh`: Context check before commit.
  - Verify agent/* branch is active.
  - Error: block commit, suggest context check.

- [ ] `coordinator-postmerge.ps1/.sh` (new): Cleanup gate after merge.
  - Verify worktree clean and removable.
  - Error: halt; suggest manual cleanup.

### Phase 3: Tool Integration (2 new scripts)

- [ ] `scripts/setup-worktree.sh|ps1`: Bootstrap script.
  - Clone venv? Setup hooks? Set `.python-version`?
  - Link to main repo's dev dependencies.

- [ ] `scripts/cleanup-worktree.sh|ps1`: Safe cleanup script.
  - Pre-checks (clean status, no uncommitted changes).
  - Worktree removal + prune + sanity check.

### Phase 4: Testing & Hardening

- [ ] Integration tests: create/merge/cleanup cycle.
- [ ] Stress test: 4+ parallel worktrees + merge conflicts.
- [ ] Error recovery: simulate locked worktrees, force removal.
- [ ] Documentation: troubleshooting guide + video example (optional).

---

## 6. Risk Assessment

| Risk | Severity | Mitigation |
|---|---|---|
| Stale worktrees pile up (disk/confusion) | Medium | Lifecycle gate + cleanup script + periodic audit |
| Merge conflicts from long-running branches | High | Policy: max 2-day branch lifetime; daily rebase gate (optional) |
| Agent commits in wrong worktree | High | Context proof gate in every agent stop hook |
| Worktree corruption (git internals) | Low | Git is mature; timeout on removal + manual fallback |
| Performance: many worktrees slow operations | Low | 5-10 worktrees have negligible impact on modern hardware |
| Backward compatibility | Low | Feature is opt-in; current flows still work; no breaking changes |

---

## 7. Success Criteria

- [ ] Coordinator can create/destroy worktrees without human intervention.
- [ ] Multiple agent tasks run in parallel without interference.
- [ ] Commits are properly scoped to branch + worktree.
- [ ] Hard gates prevent context contamination (wrong branch in wrong tree).
- [ ] Cleanup is automated and verifiable.
- [ ] Zero false-positive hard gate blocks (gates are tight, not paranoid).
- [ ] Documentation + troubleshooting guide covers 80% of edge cases.

---

## 8. Appendix: Example Workflow

### Timeline: 2 Parallel Tasks

**T+0: Human starts feature**
```
Human: "Implement auth module"
Coordinator → Step 0d: 
  git worktree add ../wt/feat-auth -b agent/feat-auth dev
  Bootstrap venv, setup hooks.
  → Test-writer spawned in wt/feat-auth
```

**T+1: Test-writer runs (in wt/feat-auth)**
```
Red phase: Create test_auth_service.py in wt/feat-auth
Commit: [agent:test-writer] failing tests: auth module -- login/logout/token refresh
Context gates: ✓ branch = agent/feat-auth, ✓ worktree active
```

**T+2: Human starts a second task (main checkout stays on dev)**
```
Human: "Fix database connection pool"
Coordinator → Step 0d (for second task):
  git worktree add ../wt/fix-db-pool -b agent/fix-db-pool dev
  Bootstrap venv.
  → Test-writer #2 spawned in wt/fix-db-pool
```

**T+3: Both test-writers running in parallel**
```
wt/feat-auth: implementer writing auth service code
wt/fix-db-pool: implementer writing db pool fix
Main checkout: Human debugging local issue on dev (no interference)
```

**T+4: Complete feat-auth**
```
Code-critic APPROVED
Human: `git merge --no-ff agent/feat-auth` (in main checkout)
Coordinator → Step 8: Cleanup
  Verify wt/feat-auth clean
  git worktree remove ../wt/feat-auth
  Prune dangling refs
  → wt/feat-auth gone, dev now has latest code
```

**T+5: Still working on fix-db-pool (in wt/fix-db-pool)**
```
No interference; still in own worktree
Main checkout available for dev work
```

---

## 9. Manifest & Config Changes

### `.github/.af-manifest` — add when scripts/hooks are created

The manifest controls which files `deploy.ps1` owns and syncs. New entries required when Phase 2/3 ships:

```
# Worktree scripts (Phase 3)
scripts/setup-worktree.ps1
scripts/setup-worktree.sh
scripts/cleanup-worktree.ps1
scripts/cleanup-worktree.sh

# Worktree cleanup hook (Phase 2)
hooks/scripts/coordinator-postmerge.ps1
hooks/scripts/coordinator-postmerge.sh
```

`skills/` and `hooks/scripts/` are already declared as directories in the manifest — new files inside them are automatically covered. The 4 new scripts under `scripts/` need explicit entries because the manifest lists scripts individually.

**Do NOT update the manifest before the files exist** — deploy.ps1 warns on missing listed files.

### `af-env.conf` — add WORKTREE_DIR on Phase 1

Already declared `[customizable]` in the manifest (protected from AF updates). Only the file *content* changes — no manifest entry needed:

```bash
# Git Worktree Configuration
WORKTREE_DIR=../wt
WORKTREE_BRANCH_PREFIX=agent
```

---

## 10. Dependencies / Blockers

- ✅ Git 2.7+ (worktree support) — standard on all modern systems.
- ✅ Bash 4+ / PowerShell 5.1+ (script execution).
- ⏳ Quality-gates.instructions.md may need expansion for context checks (soft dependency; can defer).

---

## 10. Open Questions / Follow-Up

1. **Rebase policy:** Should agents rebase feature branches daily? Or merge-only? (Recommended: merge-only to avoid history rewrite friction.)
2. **Stale worktree audit:** Auto-delete worktrees older than N days? Or only manual + warnings?
3. **Performance baseline:** What's the overhead of 3-5 parallel worktrees on CI agents? (Expected: negligible, <5% memory.)
4. **venv sharing:** Should each worktree have its own venv or share the main venv? (Recommendation: share via symlink to save space.)
5. **Hook duplication:** Should we extract context checks into a shared utility module (e.g., `scripts/verify-context.ps1`) to avoid hook code duplication?

---

## Notes

- Document is **living** — update as implementation progresses.
- Each phase should result in a commit to AAIG main with ticket ref.
- Testing should cover at least 3 parallel task scenarios before merge.
