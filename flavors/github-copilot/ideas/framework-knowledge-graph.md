# Idea: Framework Knowledge Graph

> Status: **RESEARCH / PROPOSAL**
> Date: 2026-04-02
> Author: AI-assisted analysis
> Related: Ideas.md (backlog), agent-framework-map.v2.html (static predecessor)

---

## 1. Problem Statement

The AAIG GitHub Copilot flavor has grown to **~130 files** across 10+
directories. Relationships between files are implicit — encoded as
markdown links, YAML references, shell script paths, frontmatter fields,
and human knowledge. Today's pain points:

| Pain | Example |
|------|---------|
| **Broken references go undetected** | A skill is renamed but 3 agents still reference the old name |
| **Impact analysis is manual** | "What breaks if I change MANIFEST.md §5 thresholds?" requires grep + reading |
| **Onboarding is slow** | New contributors must read README → MANIFEST → agents → instructions to grasp the web |
| **Static map drifts** | `agent-framework-map.v2.html` was generated at v1.17.0; now at v1.18.4, it's stale |
| **audit-tools.ps1 is narrow** | It validates tool assignments but nothing else (no skill refs, no template refs, no instruction refs) |
| **Orphan detection is ad-hoc** | We found `agent-hooks.json` is dead weight only by inspecting VS Code logs |

A **knowledge graph** would make all relationships explicit, queryable,
and visualizable — at both file level and content level.

---

## 2. What the Graph Would Model

### 2.1 Node Types

| Node Type | Count | Examples |
|-----------|-------|---------|
| **Agent** | 11 | coordinator, planner, implementer, ... |
| **Instruction** | 6 | architecture, git-workflow, provenance, ... |
| **Skill** | 50 | 16 active + 34 available |
| **Hook Script** | 26 | 13 pairs (.ps1 / .sh) |
| **Prompt** | 14 | tdd-feature, quick-fix, onboard-project, ... |
| **Template** | 3 | PLAN.md, INVESTIGATION.md, WIP.md |
| **Governance Doc** | 4 | MANIFEST, GOVERNANCE, TOOLS, TROUBLESHOOTING |
| **Config** | 4 | .af-manifest, af-env.conf, tasks.json, settings.json |
| **Script** | 7 | run-tests, run-deps, run-metrics, audit-tools, validate-skills, test-hooks, test-hooks-integration |
| **Section** | ~50+ | MANIFEST §1-§12, GOVERNANCE R-SD-01..R-SD-27 (content-level) |
| **Tool** | ~60 | VS Code tools from tools-reference.txt |
| **Workflow** | 5 | Full TDD, Quick Fix, Trivial Fix, Review, Plan Only |

### 2.2 Edge Types

| Edge Type | From → To | Example |
|-----------|-----------|---------|
| `INVOKES` | Agent → Agent | coordinator → planner |
| `USES_TOOL` | Agent → Tool | implementer → edit/editFiles |
| `APPLIES_TO` | Instruction → Glob | testing.instructions → `**/test_*.py` |
| `READS_SKILL` | Agent → Skill | test-writer → unit-testing |
| `ENFORCES` | Hook → Agent | test-writer-pretooluse → test-writer |
| `REFERENCES` | Doc → Doc | MANIFEST → GOVERNANCE |
| `REFERENCES_SECTION` | Doc → Section | quality-gates.instructions → MANIFEST §5 |
| `USES_TEMPLATE` | Agent → Template | planner → PLAN.md |
| `TRIGGERS` | Prompt → Workflow | /af-tdd-feature → Full TDD |
| `CALLS_SCRIPT` | Hook/Task → Script | implementer-stop → run-tests.ps1 |
| `DEFINES_THRESHOLD` | Section → Metric | MANIFEST §5 → "Domain ≥ 90%" |
| `VALIDATES` | Script → Config | audit-tools → TOOLS.md |
| `DEPLOYED_BY` | File → .af-manifest entry | All AF files → manifest lines |
| `PLATFORM_PAIR` | Script → Script | block-dangerous.ps1 ↔ block-dangerous.sh |
| `SUPERSEDES` | Skill → Skill | active/unit-testing → _available/unit-testing |
| `LIFECYCLE_EVENT` | Hook → Event | session-context → SessionStart |

### 2.3 Node Properties (metadata)

| Property | Applies To | Source |
|----------|-----------|--------|
| `file_path` | All file nodes | Filesystem |
| `last_modified` | All file nodes | git log |
| `version_introduced` | All | CHANGELOG parsing |
| `customizable` | Config/Instructions | .af-manifest annotation |
| `platform` | Scripts | File extension (.ps1/.sh) |
| `applyTo` | Instructions | YAML frontmatter |
| `model_tier` | Agents | Frontmatter `model:` |
| `tool_count` | Agents | Frontmatter `tools:` length |
| `line_count` | All files | wc -l |
| `complexity_tier` | Agents | MANIFEST classification |
| `status` | Skills | active vs _available |

---

## 3. Feasibility Assessment

### 3.1 Is It Feasible?

**Yes.** The data already exists — it's just scattered across files in
parseable formats (YAML frontmatter, markdown links, shell script paths,
JSON config). Extraction is mechanical, not heuristic.

### 3.2 Extraction Complexity

| Data Source | Parsing Method | Difficulty |
|-------------|---------------|------------|
| Agent frontmatter (tools, model, description) | YAML parse | Easy |
| Agent body (subagent invocations, skill references) | Regex on markdown | Medium |
| Instruction frontmatter (applyTo) | YAML parse | Easy |
| Markdown cross-references (links) | Regex `\[...\]\(...\)` | Easy |
| Section references ("MANIFEST §5") | Regex `§\d+` or heading anchors | Medium |
| Hook scripts (script paths, tool patterns) | Regex on PS1/Bash | Medium |
| .af-manifest (file ownership, annotations) | Line parsing | Easy |
| CHANGELOG (version_introduced) | Heading + date parsing | Medium |
| tasks.json (script calls) | JSON parse | Easy |
| TOOLS.md (agent-tool matrix) | Markdown table parsing | Medium |
| skills/INDEX.md (agent-skill matrix) | Markdown table parsing | Medium |

**Estimated extraction effort:** 1-2 days for a Python script that
produces the complete graph. Most parsing is regex + YAML.

### 3.3 Is the Gain Worth the Work?

| Benefit | Value | Without Graph |
|---------|-------|---------------|
| **Broken reference detection** | Automated: query for edges pointing to non-existent nodes | Manual grep, error-prone |
| **Impact analysis** | "What uses MANIFEST §5?" → instant subgraph | Read 130 files |
| **Orphan detection** | Nodes with zero inbound edges | Ad-hoc discovery (took us a session to find agent-hooks.json is dead) |
| **Stale map replacement** | Generate `agent-framework-map.v3.html` FROM the graph | Hand-maintain static HTML |
| **Onboarding visualization** | Interactive explorer for new users | Read README file tree |
| **Audit expansion** | Validate ALL cross-references, not just tools | audit-tools.ps1 covers 1 edge type |
| **Changelog automation** | Diff two graph snapshots = what changed | Manual CHANGELOG writing |
| **Skill gap analysis** | Agents × Skills matrix gaps | Manual INDEX.md reading |
| **Platform parity check** | .ps1 without .sh pair = gap | Manual listing |

**Verdict: HIGH VALUE.** The graph pays for itself immediately through
automated broken-reference detection, stale map replacement, and expanded
auditing. Ongoing value compounds as the framework grows.

---

## 4. Implementation Options

### Option A: Static JSON Graph + Python Scripts

**Approach:** Python script extracts graph → writes `graph.json` (nodes +
edges). Separate scripts query/validate/visualize.

```
scripts/
  extract-graph.py      # Parse all files → graph.json
  validate-graph.py     # Find broken refs, orphans, parity gaps
  render-graph.html     # Generate interactive HTML from graph.json
graph.json              # The graph (committed, version-controlled)
```

| Pro | Con |
|-----|-----|
| Zero dependencies beyond Python stdlib + json | No query language — custom Python for each question |
| Committed to repo, diffable | graph.json could be large (~500 nodes, ~2000 edges) |
| Easy CI integration (run on every PR) | No interactive exploration without HTML renderer |
| Framework-native Python | Rebuild required on every file change |

**Best for:** Validation pipeline (CI/CD). Run `extract-graph.py` →
`validate-graph.py` on every commit. Catch broken refs before merge.

**Estimated effort:** 2-3 days.

### Option B: SQLite Graph (Lightweight Relational)

**Approach:** Same extraction, but load into SQLite with `nodes` and `edges`
tables. Query with SQL.

```sql
-- Find all orphaned files (no inbound edges)
SELECT n.id, n.type, n.file_path
FROM nodes n
LEFT JOIN edges e ON e.target = n.id
WHERE e.id IS NULL AND n.type != 'Config';

-- Impact analysis: what depends on MANIFEST.md?
SELECT e.type, n2.id, n2.type
FROM edges e
JOIN nodes n1 ON e.source = n1.id
JOIN nodes n2 ON e.target = n2.id  -- reversed: what has edges TO manifest
WHERE n1.file_path LIKE '%MANIFEST.md';
```

| Pro | Con |
|-----|-----|
| SQL query language — flexible ad-hoc queries | SQLite file not human-readable in diffs |
| Python `sqlite3` is stdlib — zero deps | Slight overhead vs flat JSON |
| Can store historical snapshots (date column) | Need wrapper scripts for common queries |
| Fast for ~2000 edges | Not a "real" graph DB — no traversal primitives |

**Best for:** Ad-hoc analysis + validation. Good middle ground.

**Estimated effort:** 3-4 days.

### Option C: NetworkX In-Memory Graph

**Approach:** Python `networkx` library for in-memory graph operations.
Extract → build DiGraph → analyze/visualize.

```python
import networkx as nx

G = nx.DiGraph()
G.add_node("coordinator", type="Agent", file="agents/coordinator.agent.md")
G.add_edge("coordinator", "planner", type="INVOKES")

# Orphan detection
orphans = [n for n in G.nodes if G.in_degree(n) == 0]

# Impact analysis — all transitive dependents of MANIFEST
dependents = nx.descendants(G, "MANIFEST.md")

# Shortest path: how does test-writer relate to GOVERNANCE?
path = nx.shortest_path(G, "test-writer", "GOVERNANCE.md")
```

| Pro | Con |
|-----|-----|
| Rich graph algorithms (centrality, shortest path, cycle detection, communities) | Requires `networkx` dependency |
| Native graph traversal (BFS, DFS, transitive closure) | In-memory only — no persistence without serialization |
| Export to GraphML, GEXF, JSON for visualization tools | Heavier than needed for simple validation |
| Integrates with matplotlib/plotly for visualization | Not CI-friendly without wrapping |

**Best for:** Deep analysis + visualization. Finding structural patterns,
centrality (what's the most critical file?), communities (which files
cluster together?).

**Estimated effort:** 3-4 days.

### Option D: Neo4j / Graph Database

**Approach:** Full graph database with Cypher query language.

```cypher
// All agents that read a skill but don't have a hook enforcing them
MATCH (a:Agent)-[:READS_SKILL]->(s:Skill)
WHERE NOT EXISTS { (h:Hook)-[:ENFORCES]->(a) }
RETURN a.name, s.name

// Transitive impact of changing MANIFEST §5
MATCH p=(n)-[:REFERENCES_SECTION*1..3]->(s:Section {id: "MANIFEST-§5"})
RETURN p
```

| Pro | Con |
|-----|-----|
| Purpose-built for graph traversal | Heavy: requires Neo4j server (Docker or cloud) |
| Cypher is expressive and readable | Massive overkill for ~500 nodes |
| Rich visualization (Neo4j Browser) | Dependency on external service |
| Scales to millions of nodes | Setup/maintenance overhead |

**Best for:** Only if the graph grows significantly (multiple flavors,
cross-project analysis, runtime telemetry integration).

**Estimated effort:** 5-7 days.

### Option E: Hybrid — JSON Extract + NetworkX Analysis + HTML Render

**Approach:** Combine Options A and C. Extract to JSON (committed,
diffable, CI-friendly), load into NetworkX for analysis, render to HTML
for interactive exploration.

```
scripts/
  extract-graph.py      # Parse all files → graph.json
  analyze-graph.py      # Load graph.json → NetworkX → reports
  render-graph.py       # NetworkX → interactive HTML (pyvis or d3.js)
  validate-graph.py     # CI gate: broken refs, orphans, parity gaps

graph.json              # Committed artifact (source of truth)
agent-framework-map.v3.html   # Auto-generated (replaces static v2)
```

**Workflow:**
1. `extract-graph.py` runs → updates `graph.json`
2. `validate-graph.py` runs → reports issues (CI gate)
3. `analyze-graph.py` runs → prints centrality, orphans, clusters
4. `render-graph.py` runs → generates interactive HTML map
5. On deploy: if `graph.json` changed, regenerate HTML

| Pro | Con |
|-----|-----|
| JSON is diffable + CI-friendly | Two scripts to maintain vs one |
| NetworkX gives real graph analysis | `networkx` + `pyvis` dependencies |
| Auto-generated HTML replaces stale v2 map | Initial setup is ~4 days |
| Can run without NetworkX (just JSON validation) | — |

**Best for:** This project. Balances power, simplicity, and CI integration.

**Estimated effort:** 4-5 days.

---

## 5. Recommendation

**Option E (Hybrid)** is the sweet spot:

1. **graph.json** is the portable, committable artifact — works anywhere
2. **validate-graph.py** replaces and expands `audit-tools.ps1` scope
3. **render-graph.py** auto-generates the interactive map, killing the
   stale `agent-framework-map.v2.html` problem permanently
4. **analyze-graph.py** is optional luxury — useful but not required for
   core value

### Phased Rollout

| Phase | Deliverable | Effort | Value Unlocked |
|-------|-------------|--------|----------------|
| **Phase 1** | `extract-graph.py` → `graph.json` | 1-2 days | Machine-readable relationship data |
| **Phase 2** | `validate-graph.py` → CI gate | 1 day | Broken ref + orphan detection |
| **Phase 3** | `render-graph.py` → `.html` map | 1-2 days | Auto-generated interactive visualization |
| **Phase 4** | `analyze-graph.py` → reports | 1 day | Centrality, clusters, impact analysis |

Phases 1-2 deliver 80% of the value. Phases 3-4 are polish.

### Dependencies

- **Python 3.10+** (already available)
- **PyYAML** (for agent frontmatter parsing) — or use regex to avoid dep
- **networkx** (Phase 3-4 only) — optional, pip install
- **pyvis** or custom D3.js template (Phase 3 only) — for HTML rendering

### File Placement

```
flavors/github-copilot/
  scripts/
    extract-graph.py
    validate-graph.py
    analyze-graph.py        # Phase 4
    render-graph.py         # Phase 3
  graph/
    graph.json              # Extracted graph (committed)
    schema.json             # JSON Schema for graph.json
  agent-framework-map.v3.html  # Auto-generated (replaces v2)
```

---

## 6. Content-Level Graph (Beyond Files)

The real power is **content-level** nodes — not just "MANIFEST.md" but
"MANIFEST §5 — Metric Thresholds" as a queryable entity.

### What This Enables

| Query | File-Level Answer | Content-Level Answer |
|-------|-------------------|---------------------|
| "What uses MANIFEST?" | 30 files reference it | §5 thresholds → 8 agents + 2 scripts; §7 commits → git-workflow; §9 hooks → 13 scripts |
| "What breaks if I change coverage threshold?" | "Everything that references MANIFEST" (too broad) | "implementer-stop.ps1 line 47, code-critic quality gate, quality-gates.instructions §Implementer" (precise) |
| "Which rules have no enforcing hook?" | Can't answer | GOVERNANCE R-SD-17 has no hook → gap detected |

### Implementation

Content-level extraction requires:
1. **Heading-based section splitting** for markdown files (## headings → Section nodes)
2. **Section reference parsing** ("MANIFEST §5", "GOVERNANCE R-SD-17")
3. **Threshold extraction** (regex for "≥ 90%", "≤ 10" patterns)
4. **Rule-to-hook mapping** (which governance rules have enforcement hooks?)

This is Phase 4+ work — valuable but not required for the core graph.

---

## 7. Relationship to Existing Assets

| Existing Asset | Relationship to Graph |
|---------------|----------------------|
| `audit-tools.ps1` | **Subsumed** by validate-graph.py (tools are one edge type among many) |
| `validate-skills.py` | **Subsumed** — skill validation becomes a graph query |
| `agent-framework-map.v2.html` | **Replaced** by auto-generated v3 from graph data |
| `tools-reference.txt` | **Input** to extraction (tool nodes) |
| `skills/INDEX.md` | **Input** to extraction (skill-agent matrix) |
| `.af-manifest` | **Input** to extraction (ownership edges) |
| `CHANGELOG.md` | **Input** to extraction (version_introduced metadata) |
| `test-hooks-integration.ps1` | **Complementary** — validates runtime behavior; graph validates static structure |

---

## 8. Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Extraction regexes miss edge cases | Medium | Medium | Start with high-confidence patterns; iterate |
| Graph drifts from reality (stale) | Medium | High | Make extraction part of CI or deploy |
| Over-engineering for ~130 files | Low | Medium | Phase 1-2 only is still valuable; stop there if enough |
| NetworkX dependency unwanted | Low | Low | Phase 1-2 work without it (pure Python + JSON) |
| Maintenance burden of extraction script | Medium | Medium | Design for extensibility; add extractors incrementally |

---

## 9. Decision Needed

- [ ] **Approve concept** — proceed to Phase 1 implementation
- [ ] **Choose option** — confirm Option E (Hybrid) or select alternative
- [ ] **Scope** — Phase 1-2 only (validation) or full Phase 1-4 (analysis + viz)?
- [ ] **Dependencies** — accept PyYAML + networkx, or pure stdlib only?
- [ ] **Placement** — `scripts/` + `graph/` as proposed, or different structure?
