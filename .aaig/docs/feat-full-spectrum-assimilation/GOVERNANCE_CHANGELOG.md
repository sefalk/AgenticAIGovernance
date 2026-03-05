# AAIG Governance Changelog

All changes to **Level 0** and **Level 1** governance documents are recorded here, as required by the [Governance Change Protocol](L1_Framework_Architecture.md#8-governance-change-protocol).

---

## [2026-03-05] Full-Spectrum Assimilation

**Affected Documents:**

| Document | Old Version | New Version |
|----------|-------------|-------------|
| `L0_Assimilation_Protocol.md` | 1.1 | 1.3 |
| `L1_Framework_Architecture.md` | 1.0 | 1.1 |

**Supporting Documents Updated:**

| Document | Old Version | New Version |
| `domains/_index.md` | 1.0 | 1.1 |
| `L4_Project_Template.md` | 1.0 | 1.1 |
| `workflows/_index.md` | 1.0 | 1.1 |
| `skills/_index.md` | 2.4 | 2.5 |

### What Changed

The Assimilation Protocol was redesigned from **selective loading** (load only detected domains) to **Full-Spectrum Deployment** (deploy all AAIG capabilities, activate user-selected subset).

**Key changes:**
- **L0 Phase 3** renamed from "Native Dynamic Generation & Integration" to "Full-Spectrum Deployment & Integration."
- **Selective loading restrictions removed:** The "Do NOT load all [X]" prohibitions were removed from L0 Step 2, `domains/_index.md`, `workflows/_index.md`, and `skills/_index.md`. All domains, workflows, and skills are now deployed fully.
- **Specialization Prompt added** (L0 Phase 3, Step 3): An interactive step where the agent presents all available domains and skills, and the User selects active specializations — or states "all."
- **On-Demand Activation** mechanism defined: Dormant capabilities can be activated at any time without re-running the Assimilation Protocol.
- **Native Multi-Agent Orchestration added** (L0 Phase 3, Step 6): Mandates that environments natively supporting subagents (e.g., GitHub Copilot) must explicitly map AAIG Workflows and Reviewer roles to native subagents.
- **L4 Template** updated with "Active Specializations" (Section 6) and "Deployed Capabilities (Dormant)" (Section 8).

### Why

The original one-time, selective assimilation was brittle: requirements change over time (especially in empty/evolving projects), and no synchronization mechanism existed to pick up new domains. Implementing synchronization was impractical. Full-spectrum deployment eliminates this gap — everything is already present, and the Specialization Prompt prevents context overload.

### Cross-Level Impact Assessment

| Level | Impact | Detail |
|-------|--------|--------|
| L2 Domains | Low | Domain content unchanged; only the loading strategy changed |
| L3 Workflows | Low | Workflow content unchanged; selection logic unchanged |
| L4 Instantiation | Medium | Template updated; new sections for Active vs. Dormant capabilities |
| Token Efficiency | Medium | Shifted from framework-enforced minimalism to user-controlled context density |

### Independent Review

#### ✅ Pros

1. **Eliminates the synchronization problem.** The core flaw — no mechanism to pick up new domains after initial assimilation — is solved by front-loading everything. This is the right architectural choice.
2. **User-controlled context density.** The Specialization Prompt shifts the overload decision from framework-imposed to user-defined. This is more flexible than hard-coded restrictions.
3. **On-demand activation is low-friction.** No protocol restart required; just reference the dormant capability and update the L4 Contract. This is clean and practical.
4. **Consistent terminology.** "Active" vs. "Deployed (Dormant)" is used consistently across L0, L1, `_index.md`, and L4 template.
5. **L4 template cleanly separates concerns** — Section 6 (Active) vs. Section 8 (Dormant) gives agents and humans clear visibility.

#### ⚠️ Cons

1. **Token overhead for small agents.** The old selective approach preserved token budget by design. Full-spectrum deployment trades efficiency for flexibility. Agents with very limited context windows (e.g., some Copilot modes) may struggle with 7 domains + all skills loaded as reference.
2. **Mandatory interactive step slows cold starts.** The Specialization Prompt requires user interaction during every assimilation. Users wanting a quick, zero-config start must still answer the prompt (even if just saying "all").
3. **"Deployed but dormant" is conceptually clear but mechanistically vague.** The protocol doesn't precisely define what "deployed" means in practice — is it: (a) files copied to a local folder? (b) listed in a manifest? (c) loaded into agent context? This ambiguity could lead to inconsistent implementations.

#### 🔴 Gaps

1. **L1 §8 contradicts the changelog location.** `L1_Framework_Architecture.md` line 67 specifies the changelog should be *"at the repository root"* (`GOVERNANCE_CHANGELOG.md`). This changelog has been moved to `.aaig/docs/feat-full-spectrum-assimilation/`. Either L1 §8 must be updated or the changelog must be at the root. **Status: Open — requires decision.**
2. **"All applicable skills" in L0 Step 2 reintroduces selectivity.** The phrase *"all applicable skills"* uses the qualifier "applicable," which implicitly requires the agent to judge what's applicable — partially reverting to the selective model. Should read **"all skills"** for consistency with the full-spectrum intent, or explicitly define the applicability filter.
3. **Empty-project flow has a logical ordering issue.** Step 1 says HALT for empty projects to get a tech stack definition. Step 2 says deploy ALL domains. Step 3 then asks the user to select specializations. For empty projects where Step 1 halts, should the Specialization Prompt happen during the same HALT interaction, or after? The ordering is ambiguous.
4. **New domains added to the framework later are not addressed.** Full-spectrum assimilation deploys "all domains at assimilation time." If a new `L2_Quantum_Computing.md` domain is added to the framework after a project's initial assimilation, that project still has no sync mechanism. The synchronization problem is shifted from "project requirements changing" to "framework capabilities expanding." This is a smaller surface area but not fully solved.
5. **`domains/_index.md` Domain Selection Guide table header still says "Load."** Line 18 uses the column header "Load" which is a holdover from the selective-loading model. Should be updated to neutral terminology (e.g., "Domain File" or "Reference").
6. **L4 Template "Derived from" field (line 4) hardcodes `L2_Software_Development.md`.** In a full-spectrum model where multiple domains are active, the derivation chain is multi-source. The template should allow listing multiple L2 sources.
7. **No guidance on persisting on-demand activation changes.** When a dormant capability is activated mid-session, the L4 Contract must be updated. But should this be a git commit? An ephemeral in-memory change? If ephemeral, the activation is lost between sessions.

#### 💡 Suggested Improvements

1. **Define "deployed" mechanistically.** Add a definition to L0 Phase 3: *"Deployed means all L2/skill files are referenced in the L4 Contract's Deployed Capabilities manifest. Active means additionally loaded into the native IDE integration folder and agent context."*
2. **Add a "recommended specialization" heuristic.** Instead of a cold menu, the agent should auto-suggest based on Phase 1 discovery (detected stack → suggested domains) and let the user confirm or modify. This preserves the interactive prompt while reducing friction.
3. **Fix "applicable" in Step 2.** Change to "all skills" or define the filter explicitly.
4. **Update L1 §8** to reference the `.aaig/docs/` changelog convention, or keep a root-level changelog as the canonical location.
5. **Fix the "Load" column header** in `domains/_index.md` Domain Selection Guide.
6. **Address framework evolution.** Add a note: *"When new L2 domains are added to the AAIG framework, existing projects should update their Deployed Capabilities manifest during the next agent session."*

