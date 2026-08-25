---
name: 'Quality Gate System'
description: 'Generic quality gate framework — taxonomy, complexity tiers, and handoff protocol. Applies to all agents and all file types. Per-agent gate tables live in each agent file.'
applyTo: '**'
---

# Quality Gate System

Every agent must satisfy its exit gates before handing off work. This file
defines what they are, how they scale with task complexity, and how to report
them.

## Gate Taxonomy

Three types:

| Type | Definition | Enforcement |
|---|---|---|
| **HARD** | Automated, measurable, binary pass/fail. Blocks handoff. | Agent verifies programmatically (run tool, check output). Coordinator rejects if missing or failed. |
| **SOFT** | Judgment-based. A reviewer (critic agent or human) decides pass/fail. | Listed in the agent's return for the reviewer to evaluate. Rejection triggers retry (MANIFEST § 4). |
| **ADVISORY** | Informational metric, never blocks. | Agent reports the value. Useful for trend tracking. |

**Maker-Checker rule:** An agent's self-check of its own structural output
is always SOFT, not HARD. Only a _different_ agent (critic) or an automated
tool can enforce a HARD gate. This prevents the cognitive bias of
proofreading your own work.

**BLOCKED state:** If a tool required for a HARD gate is unavailable
(terminal down, Pylance MCP unreachable, pytest not installed), report
the gate as **BLOCKED** — not PASS or FAIL — and include the reason.
The coordinator treats BLOCKED gates as escalation triggers.

**Evidence durability:** when the deliverable is a value, not a file, the
artifact is the gate. Return a reference a third party can open — run id, URL,
table, committed file — not the number. No durable channel → BLOCKED.

## Complexity Tiers

The complexity tier determines which gates activate and at what strictness. The
planner sets it in the plan file; the coordinator sets it for Trivial Fix and
Quick Fix workflows.

| Tier | When | Examples | Gate Behaviour |
|---|---|---|---|
| **Trivial** | ≤ 2 files, no logic changes, no architectural impact | Rename, format, config edit, doc fix, typo | HARD: Gate 1 (Auto-Check) only. No SOFT gates. No critic invoked. |
| **Standard** | 3–5 files, within existing architecture | Bug fix, small feature, local refactor | HARD: Auto-Check + applicable skill gates. SOFT: Critics review. ADVISORY: Reported. |
| **Deep** | 6+ files, or new architectural elements, or cross-cutting | New module, new port/adapter, major feature | HARD: All gates at full thresholds. SOFT: All critics + arbiter available. ADVISORY: All reported. |

**Layer override:** If any touched file is in domain core or ports, the
minimum tier is **Standard** regardless of file count. Domain core changes
carry architectural risk disproportionate to their size.

**Exemption:** pure documentation changes (docstrings, comments, README
updates) in domain core files do not trigger the layer override — the change
must affect **logic** (executable code, type signatures, imports) to count.

**Human override:** The human can change the tier at plan approval time.

## Agent Naming Convention (Provider Workers)

The `{provider}-{capability}-{role}` pattern and its examples live in
MANIFEST § 7 (Agent Identity). Naming violations are SOFT unless they cause
broken orchestration references, which is treated as HARD.

## Per-Agent Exit Gates

Each agent's gate table lives in its own file (`agents/{agent}.agent.md`,
section **Exit Gates**), loaded exactly when that agent runs instead of every
agent carrying all of them. Use the table in your own file; never another
agent's.

## Agent Exit Protocol

Before returning results, every agent:

1. **Determine the complexity tier** from the plan file (or the coordinator's
   prompt for Trivial Fix and Quick Fix). Default to **Standard** if unclear.
2. **Identify applicable gates** from the Exit Gates table in your own agent
   file, filtered by the current tier.
3. **Evaluate HARD gates** using the specified verification method.
   - If a HARD gate fails: fix the issue and retry (internally, up to 2
     attempts).
   - If a required tool is unavailable: report the gate as **BLOCKED**.
   - If still failing after retries: report the failure (do not suppress).
4. **Report SOFT gates** as "evaluated" — the reviewer (critic or human)
   decides pass/fail.
5. **Report ADVISORY gates** as metric values.
6. **Include a Gate Summary** in the return format (see below).

## Gate Summary Format

Append this section to every return:

```markdown
### Gate Summary
- **Tier:** {Trivial | Standard | Deep}
- **HARD gates:** {passed}/{total} passed
- **SOFT gates:** {count} evaluated (reviewer decides)
- **ADVISORY:** {metric_name} = {value}
- **BLOCKED gates:** {list, or "none"}
- **Failed HARD gates:** {list, or "none"}
- **Skills Read:** {list of SKILL.md files read, or "none — no applicable skills"}
```

**Collapse it when everything passed.** If `OUTPUT_VERBOSITY` (`af-env.conf`)
is `standard` or `lean` **and** all HARD gates passed with nothing BLOCKED and
no SOFT gate needing a judgment call, emit one line instead:

```markdown
### Gate Summary
{Tier} · HARD {passed}/{total} · SOFT {count} evaluated · BLOCKED none · Skills: {list or none}
```

Any failure, BLOCKED gate, or ADVISORY metric worth reporting → emit the full
block regardless of mode. When in doubt, emit the full block: the cost of an
extra table is small, the cost of a silently dropped gate failure is not.

**Skills Read compliance (producer agents only — test-writer, implementer,
refactorer):** The `Skills Read:` line is a SOFT gate. If missing or empty,
the reviewing critic flags it as a SOFT gate failure. If the producer claims
"none — no applicable skills", that is acceptable — silence is not.

The coordinator uses this summary to decide next actions:
- All HARD passed → proceed to next step
- Any HARD failed → treat as implicit REJECTED (retry or escalate)
- Any HARD BLOCKED → escalate to human
