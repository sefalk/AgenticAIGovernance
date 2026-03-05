# AAIG Governance Changelog

All changes to **Level 0** and **Level 1** governance documents are recorded here, as required by the [Governance Change Protocol](L1_Framework_Architecture.md#8-governance-change-protocol).

---

## [2026-03-05] Full-Spectrum Assimilation

**Affected Documents:**

| Document | Old Version | New Version |
|----------|-------------|-------------|
| `L0_Assimilation_Protocol.md` | 1.1 | 1.2 |
| `L1_Framework_Architecture.md` | 1.0 | 1.1 |

**Supporting Documents Updated:**

| Document | Old Version | New Version |
|----------|-------------|-------------|
| `domains/_index.md` | 1.0 | 1.1 |
| `L4_Project_Template.md` | 1.0 | 1.1 |

### What Changed

The Assimilation Protocol was redesigned from **selective loading** (load only detected domains) to **Full-Spectrum Deployment** (deploy all AAIG capabilities, activate user-selected subset).

**Key changes:**
- **L0 Phase 3** renamed from "Native Dynamic Generation & Integration" to "Full-Spectrum Deployment & Integration."
- **Monorepo Scoping restriction removed:** The "Do NOT load all domains simultaneously" prohibition was removed from L0 Step 2 and `domains/_index.md`.
- **Specialization Prompt added** (L0 Phase 3, Step 3): An interactive step where the agent presents all available domains and skills, and the User selects active specializations — or states "all."
- **On-Demand Activation** mechanism defined: Dormant capabilities can be activated at any time without re-running the Assimilation Protocol.
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
