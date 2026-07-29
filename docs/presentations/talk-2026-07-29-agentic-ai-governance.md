---
title: "Talk — Agentic AI Governance: Capability vs. Accountability"
type: presentation-base
description: Content base, narrative thread and evidence inventory for a 25-minute conference talk on AAIG. This is NOT the presentation itself.
tags: [aaig, presentation, talk, governance, storytelling]
updated: 2026-07-29
status: DRAFT — content agreed, slides not yet built
sources: [docs/wiki/, core/L1_Core_Principles.md, core/L1_Framework_Architecture.md, flavors/github-copilot/.github/]
---

# Talk — Agentic AI Governance: Capability vs. Accountability

> **What this document is.** The content base, the narrative thread and the
> evidence inventory for the talk. It holds *what* is said, *why* it is
> defensible, and *which artefacts* back it up.
>
> **What this document is not.** It is not the slide deck. Building the deck is
> a separate, dedicated step. Nothing here prescribes layout, styling or slide
> counts beyond a rough budget.
>
> **Handover.** This document plus
> [talk-2026-07-29-artefacts.md](talk-2026-07-29-artefacts.md) are
> self-contained: every decision, its rationale, and the rejected alternatives
> are recorded here. §11 maps each section to the wiki page that carries its
> background, so the deck can be built without re-reading the codebase.

---

## 1. Parameters

| Parameter | Decision |
|---|---|
| **Date** | **2026-08-10** — eight days after EU AI Act Article 50 became enforceable (see §4 E.4). |
| **Duration** | **25 minutes** talk + ~5 minutes Q&A (30 min slot). 20 min is not a hard floor; 25 is the working budget. |
| **Audience** | Mixed, cross-company, **heterogeneous prior knowledge**. Cannot assume familiarity with VS Code, Copilot, agent frameworks or the EU AI Act. |
| **Pacing** | Gentle on-ramp so nobody is lost, then a **steep climb** into the substance of AAIG. |
| **Language** | **English** (document and presentation). |
| **Format** | Slides + **prepared artefacts** (screenshots, code snippets, log excerpts). **No live demo** — too time-expensive and too fragile. Exactly **one animated sequence** provides the motion (artefact 1a, see §6); everything else is a still the presenter advances. |
| **Project context** | **No concrete customer/project details.** It may be stated that the framework is *in productive use in real projects* — but no project names, no real data, no real repository content on screen. |
| **Positioning** | AAIG is **not a product**. It is a tool that emerged *alongside* real work to increase efficiency. The talk is not a sales pitch for the framework. |
| **Intent** | **Demonstrate competence.** The message is the advertisement: we have been working with generative AI since the LLM era, we understand agentic systems, and this is a current example of that. |

### Consequences of these parameters

- Artefacts must be **sanitised or synthetic** — realistic in shape, neutral in content.
- The tone is **experience report**, not vendor pitch. That permits — and requires —
  an honest limitations section, which is the single most credibility-building
  slide in a governance talk.
- "We have the competence" is *shown*, not *claimed*: through the precision of the
  distinctions drawn, through knowing exactly where enforcement ends and
  convention begins, and through naming the prior art fairly.

---

## 2. The core message

The talk has **one** thesis. Everything else serves it.

> **Orchestration for *capability* has become less necessary.
> Orchestration for *evidence* has not.**
>
> An agent with good instructions delivers a **result**.
> An agent inside a harness delivers the result **plus the proof of how it got there**.
> Where the process must be auditable, the proof *is* the deliverable.

### Why this framing and not the obvious one

The intuitive framing — *"models are black boxes, so we built our own agent
system to control them"* — is weaker than it looks, for three reasons:

1. **"Self-built" is not the load-bearing part.** Determinism and audit trails
   are also achievable with CI gates, branch policies, policy-as-code (OPA) or
   vendor hook systems. Claiming that only a bespoke framework can do this
   invites an easy takedown in Q&A.
2. **There is a fresh, prominent counter-position.** GitHub published *"The
   harness is all you need (mostly)"* on **2026-07-27**, in which Burke Holland
   argues you need neither multiple agents, nor custom agents, nor MCP servers,
   nor custom instructions to be highly successful with AI. Two days before this
   document was written. Someone in the room will have read it.
3. **Conceding "models are good enough now" and then fighting back is a losing
   sequence.** Better to *accept it up front* and pivot to the axis where it
   does not apply.

The chosen framing turns the counter-position into a **supporting witness**:
Burke Holland optimises for *individual developer productivity*. This talk
optimises for *organisational defensibility*. Different objective functions, no
contradiction. Saying that out loud is stronger than ignoring it.

### The honest historical arc (say this explicitly)

AAIG was started at a time when a dedicated harness was genuinely necessary
**for good results** — models needed the decomposition, the role separation and
the explicit process to produce usable output at all.

**That aspect has been overtaken by model capability.** Modern reasoning models
resolve broad instructions into concrete, competent work without bespoke agent
definitions.

**The other aspect has not been overtaken:** traceability and auditability of
the *process itself*. That is where the investment still pays, and that is what
the framework is now about. Admitting that half of the original motivation has
expired is exactly the kind of statement that makes the other half believable.

---

## 3. Narrative arc — the red thread

Five beats. Each one hands a question to the next.

| # | Beat | The question it leaves open |
|---|---|---|
| **A** | Tools mean side effects | *If it can act on my systems — how do I control it?* |
| **B** | We wrote it all down in Markdown | *…but what actually rejects a violation?* |
| **C** | Capability ≠ accountability | *So what does a harness that produces evidence look like?* |
| **D** | This is what it looks like | *Does that actually hold up?* |
| **E** | Here is what it cost and where it breaks | → Q&A |

The intro is not a history lesson — it already carries the punchline. The
limitations section is not an apology — it is the proof that the distinctions in
B and D were drawn honestly.

---

## 4. Section-by-section content

### Time budget

| Section | Minutes | Approx. slides |
|---|---|---|
| A · Entry: from LLM to side effects | 3 | 1–2 |
| B · Instruction ≠ Enforcement | 4 | 2 |
| C · The pivot: capability vs. accountability | 3 | 1 |
| D · What a governed run looks like | 10 | 5–6 |
| E · Limits, cost, close | 4 | 2 |
| Buffer | 1 | — |
| **Total** | **25** | **11–13** |

The hard rule: **D must not be a framework tour.** Two or three mechanisms shown
properly beat ten mechanisms listed.

---

### A · Entry — from LLM to side effects · 3 min

**Goal.** Bring everyone to a common baseline *without* spending the audience's
patience, and set up the thesis in the same breath.

**Do not** narrate the usual LLM → Chatbot → Agent history. Every audience has
heard it since 2024, and told neutrally it is three minutes of nothing.

**Instead: one single axis — *what is the system allowed to touch?***

| Stage | What it does | What it can touch |
|---|---|---|
| **LLM** | Predicts the most probable continuation of the input | Text in, text out. Nothing. |
| **Chatbot** | Turns that into a conversation; optionally grounded in a knowledge base | Its own context. Still nothing outside. |
| **Agent** | Has **tools** and decides autonomously when to use them | **Your files. Your repository. Your pipelines. Your systems.** |

**The line to land it:**

> The interesting step is not that it became smarter.
> The interesting step is that it acquired **side effects**.

That single sentence converts the on-ramp into the setup. From here the rest of
the talk is the answer to a question the audience is now already asking.

**Optional, if the room is very mixed:** one sentence on what "tool" means
concretely — read a file, run a test suite, create a commit, call an API. Keep
it to one sentence.

→ *Diagram 1.*

---

### B · Instruction ≠ Enforcement · 4 min

**Goal.** Establish the gap that the whole framework exists to close.

**B.1 — The obvious answer, and it is a real one.**

The simplest and most widely known means of steering an agent is the semantic
one: `copilot-instructions.md`, `AGENTS.md`, `CLAUDE.md` — a natural-language
definition of what to do and what not to do. Coding standards, architecture
rules, forbidden patterns.

This is, in essence, a **more civilised form of prompt engineering** — with the
important difference that today's reasoning models are genuinely good at
resolving general instructions into concrete, sensible decisions. It works. It
is not a strawman, and the talk must not treat it as one.

> **Precision note:** `AGENTS.md` is **emerging practice, not a ratified
> cross-vendor standard.** No formal specification was found. Say "convention",
> not "standard".

**B.2 — The turn.**

> So — we wrote everything down. Are we done?
>
> How would we actually *check*?

**B.3 — Name the problem precisely. "Black box" is the wrong word.**

The problem is not opacity. Traces and logs exist; you *can* look. The problem
is structural:

> **Nothing in the runtime rejects a violation.**
> Instruction files are **advisory**. There is no rejection path.

The headline for the slide:

> ### Instruction ≠ Enforcement

Corollaries worth one line each:

- The same task can be executed differently on every run — the model is not
  obliged to follow your process, and non-compliance is often **invisible in the
  result**. A correct-looking diff does not tell you whether the tests were
  written first.
- An agent asked to check its own work is not a control. It is the same
  judgement, applied twice.

**B.4 — The strongest evidence is our own framework's own wording.**

Two verbatim, quotable lines from the framework's own rule set — both are
statements *against interest*, which is exactly why they are persuasive:

> "An agent's self-check of its own structural output is always SOFT, not HARD.
> Only a *different* agent or an automated tool can enforce a HARD gate."
> — `quality-gates.instructions.md`

> "Agent prompts are conventions, **not the security boundary**."
> — `git-workflow.instructions.md`

The second line is the credibility anchor of the entire talk: we drew the border
between *suggestion* and *enforcement* ourselves, wrote it down, and did not
market across it.

**B.5 — External support.**

> "A change is not cheap just because the code was cheap to generate. It's cheap
> only if a human can confidently review and own the result."
> — Dalia Abuadas, GitHub, *"The cost of saying yes has changed"*, 2026-07-17

→ *Diagram 2.*

**Trap to avoid.** Do **not** quote any instruction-adherence failure rate.
No vendor publishes one. The argument is structural — *there is no rejection
path* — and it does not need a statistic. A made-up number would destroy the
credibility that B.4 just built.

---

### C · The pivot — capability vs. accountability · 3 min

**Goal.** Convert the gap from B into the thesis, and disarm the obvious
objection before it is raised.

**C.1 — Concede the part that is genuinely over.**

AAIG was started when a bespoke harness was necessary *for the result*. Today it
is not. Modern models handle broadly specified tasks competently on their own.
Say this plainly — it costs nothing and buys everything that follows.

**C.2 — Pre-empt the counter-position by name.**

Referencing GitHub's *"The harness is all you need (mostly)"* directly, and
agreeing with it, is far stronger than hoping nobody brings it up. The
resolution:

> He is right — **for productivity**.
> Productivity asks: *did I get a good result, faster?*
> Governance asks: *can I demonstrate how this result came about?*
> Those are different questions, and only one of them is answered by a better model.

**C.3 — The thesis slide.**

> **Capability ≠ Accountability.**
>
> A strong model can reach the goal.
> Without a harness you cannot **prove** how it got there,
> you cannot **block** the paths you forbade,
> and you have **no artefact** left to review.
>
> If only the result matters, the investment is not worth it.
> If the **process** must be demonstrable — *while it runs* — it is.

**C.4 — Sharpen the scope honestly.**

The claim is deliberately *not* "you must build your own framework". It is: **a
harness must exist, and it must enforce outside the model.** Whether it is
self-built, bought, or assembled from CI and branch policies is a second-order
question. Overreaching here is the single easiest way to lose a knowledgeable
room.

---

### D · What a governed run looks like · 10 min

**Goal.** Make it concrete and demonstrable rather than aspirational.

**Structural decision: concrete first, abstract second.**

The framework is *designed* top-down (principles → domain rules → workflows →
project binding). It is *understood* bottom-up. For 25 minutes and a mixed room,
presenting the L0–L4 abstraction hierarchy first is the wrong opening move.

Order:

1. **One real run through the pipeline** (~6 min) — with three artefacts shown.
2. **Then** the abstraction (~4 min) — as the answer to *"and why is this not
   hardcoded for one project?"*

#### D.1 — The run (~6 min)

Walk a single task through the pipeline and stop at exactly **three** places to
show an artefact. These three are the substance of the talk.

They are not chosen because they look impressive. Each one demonstrates a
**different class of thing that CI structurally cannot do** — which pre-empts
the most likely objection in the room by answering it three times before it is
asked.

| Stop | Moment | What CI cannot do | Why |
|---|---|---|---|
| **1** | **Red-phase block.** The coordinator dispatches the test-writer. It returns a test that *passes*. The stop hook blocks the handoff: the Red phase requires the test to fail against existing code. | Assert an **inverted condition on a transient state** | A green suite is CI's *success* condition and this gate's *violation*. And without the harness the Red state never becomes an artefact at all — an unconstrained agent writes test and implementation in one motion, so there is no commit for CI to inspect. |
| **2** | **Maker-checker rejection.** The implementer reports its own gate summary as fully passed. A *different* agent — the code-critic — issues a parseable `REJECTED` naming the gate that actually failed, and the work loops back. | Enforce **separation of actors** | CI checks *what* was produced. It has no concept of *who* checked it, and no way to reject "the maker approved itself". |
| **3** | **Pre-action denial.** An agent attempts a forbidden operation (force push, push to a protected branch). The action is classified and refused *before execution*. | **Prevent** rather than **detect** | CI and branch protection are always downstream of the attempt. By the time they react, local history has already been rewritten. Prevention and detection are different controls. |

> **The one-liner for this slide:**
> CI verifies the **artefacts** of a process.
> It cannot verify that the **process happened**.

Supporting points, one line each — resist elaborating:

- **Gate taxonomy: HARD / SOFT / ADVISORY.** HARD is automated and binary and
  blocks the handoff. SOFT is a judgement call and goes to a reviewer. ADVISORY
  is measured and never blocks. Deciding *which* is which is the actual
  engineering work.
- **The gate blocks the handoff, not the commit.** Stop 1 fires between two
  agents — the implementer never sees the bad test. That boundary is invisible
  to every tool whose smallest unit is a commit.
- **Complexity tiers.** Gates scale with the size and risk of the change.
  Governance that costs the same for a typo as for a new module gets switched
  off. This is not a footnote — it is the reason the framework survives contact
  with daily work.
- **Escalation is a designed exit.** Agents halt and hand back to a human on
  ambiguity or repeated failure, rather than improvising.

→ *Diagram 3.*

#### D.2 — Then the abstraction (~4 min)

Now, and only now, the layer model — framed as the answer to *"is this one
project's bespoke setup, or is it reusable?"*

- **Top-down derivation.** A small set of guiding principles — separation of
  concerns, least privilege, security, traceability, maker-checker — from which
  domain rule sets and workflows are *derived*. Everything at this level is
  generic and free of any project specifics.
- **Assimilation instead of configuration.** Rolling the framework into a
  project is not a copy job. The framework is *adapted* to the identified tech
  stack — inferred from the existing codebase, requirements and planning
  documents where they exist, and elicited through targeted questions where they
  do not.
- **Curation as context hygiene.** Only the agents and skills that actually
  match the project stay active; the rest are deactivated and physically moved
  aside. The purpose is to keep the context free of irrelevant definitions —
  which is both a quality and a cost argument.
- **Configuration as the seam.** Project-specific tool integration and settings
  live in a configuration layer, not in the generic definitions. That separation
  between *generic framework* and *concrete project knowledge* is what makes the
  thing reusable at all.
- **Backflow.** Improvements discovered in a project can be generalised and
  flow **back** into the framework. This is the part that makes it compound
  rather than fork.
- **Non-destructive updates.** A re-deploy updates the framework inside a
  running project **while preserving local adaptations** — through three-way
  comparison, explicit conflict classification, and managed regions that let
  generic and local content coexist inside one file.

**One sentence to close D:**

> None of this is about making the agent smarter.
> All of it is about making the run **reviewable**.

→ *Diagrams 4 and 5.*

**Explicitly out of scope for the talk** (available for Q&A, not for slides):
benchmark and rubric machinery, the full domain rule catalogue, deploy tooling
internals, MCP transport details, worktree mechanics.

---

### E · Limits, cost, and close · 4 min

**Goal.** Convert the talk from a presentation into a credible experience report.
This section is not optional — without it, a governance talk reads as marketing.

**E.1 — Where the boundary genuinely is.**

Two limitations, both **structural trade-offs rather than open to-dos**. That
distinction matters: a to-do says "we are not finished yet", a trade-off says
"we understood the problem and picked a side". Only the second builds
credibility, and only the second is safe to say in front of a mixed room.

**Limitation 1 — the gate is only as strong as the machine it runs on, and it is
deliberately fail-open.**

- The good part first: these hooks are executed by the **IDE runtime, not by the
  agent**. The agent does not decide whether the gate runs, does not see it
  coming, and cannot talk its way past it. That is genuine enforcement — which
  is precisely why it belongs in the same category as a server-side policy and
  not in the category of instruction files.
- The honest part: it is nevertheless a **client-side** control. Correct
  workstation provisioning is a precondition. And if the verifier itself is
  missing — no test runner installed, say — the gate **skips with a warning
  instead of blocking**.
- That is a deliberate choice, not an oversight. A fail-closed gate would make
  every governed repository a single point of failure on every developer
  machine: the first tooling hiccup halts all work, and the framework gets
  switched off within a week. At this ring, availability was chosen over
  strictness.
- The conclusion is architectural, and it is the actual point of the slide:

| | Local hooks | Server-side policy |
|---|---|---|
| When | immediately, in-process | after the fact |
| Scope | every agent handoff | the integration boundary |
| Can the **agent** bypass it? | no | no |
| Can the **human** bypass it? | yes — it is their machine | no |
| Failure mode | fail-open | fail-closed |

> Two rings, different jobs. Neither replaces the other — and anyone offering
> you just one of them as a complete answer is selling something.

**Limitation 2 — the harness proves the process, not the result.**

Best delivered as a callback to stop 1 from section D:

- The hook can mechanically verify **that** the new tests fail. It cannot verify
  that they fail **for the right reason** — a test that fails on a typo'd import
  produces the same exit code as one that fails because the behaviour genuinely
  does not exist yet.
- So that judgement is not automated away. It is classified **SOFT**, handed to
  a critic, and ultimately to a human. HARD gates only ever cover the
  *mechanically decidable* subset of what "correct" means.
- Stated plainly: **evidence ≠ correctness.** The harness makes the run
  reviewable, and makes review cheaper and better targeted. It does not remove
  the reviewer.

That is not a hole in the thesis — it *is* the thesis. The claim was never "the
agent is now trustworthy". The claim is "the run is now inspectable".

**E.2 — Own the cost.**

Maker-checker deliberately **adds** refinement loops. That is not a side effect,
it is the mechanism. Pretending it is free would be the one dishonest moment in
the talk.

The defensible framing, using published figures:

- ~**60 %** of an agentic task's cost is tied to *refining* answers, not to the
  first pass. (McKinsey, 2026-07-13)
- The same task can vary by a **factor of 30** between completions.
  (McKinsey, 2026-07-13)
- **93 %** of surveyed organisations exceed their AI budgets; about **one fifth**
  have constrained AI use because of operating cost. (McKinsey, 2026-07-13)

> Governance does not create the refinement cost — it makes it **predictable**.
> A factor-of-30 spread is not a quality problem, it is a **planning** problem.
> Bounded autonomy is what turns it into a number you can budget.

And the counter-example that shows scaffolding is a real lever rather than
overhead: GitHub replaced its code-review agent's tools with "better" generic
ones and the output got **worse**; rewriting the tool instructions to match the
actual reviewer workflow then cut average review cost by roughly **20 %** at
equal quality. (GitHub, 2026-07-10)

**E.3 — Fair positioning against prior art.**

One slide. Naming the neighbours accurately is a competence signal in itself.

| | What it covers | Relation |
|---|---|---|
| **GitHub Spec Kit** | Spec-driven development: constitution → specify → plan → tasks → implement. Large community, many agent integrations. | **Complementary.** Spec Kit is the *workflow*; this is the *harness*. Say so plainly. |
| **Claude Code** | Tool restrictions, human confirmation for irreversible actions | Overlapping enforcement primitives; no published audit-trail framework |
| **GitHub Copilot** | Subagent routing, internal benchmarks and traces | Observability without a public hook system; CI + branch protection carry the gating |
| **Cursor Rules** | Editor-level behavioural constraints | Semantic layer only |
| **Policy-as-code (e.g. OPA)** | Deterministic policy enforcement | The right idea, but not wired into the agent coordination loop |

**What is table stakes in 2026:** instruction files, tool restrictions,
subagent routing, spec-first workflows.
**What is still uncommon:** deterministic hooks, provenance marking, and an
explicit gate taxonomy **integrated into the agent coordination loop itself**
rather than bolted on around it.

**E.4 — Regulation, handled carefully.**

Tempting and easy to overclaim. What is actually defensible:

- **ISO/IEC 42001** (AI management systems) and the **NIST AI RMF Generative AI
  Profile** expect traceability and documentation as management controls. Both
  are **voluntary**.
- The **EU AI Act, Article 50** (transparency / marking of AI-generated content)
  became enforceable on **2026-08-02** — **eight days before this talk**. Use the
  timing, it is a gift: the subject is not hypothetical this week. But do not
  overreach — whether an *internal* coding agent falls under Article 50 is
  genuinely contestable. Present it as a direction of travel that has just
  started moving, not as an obligation the audience is already in breach of.
- **IEC 62304 does not require AI provenance.** Do not say it does.

The safe and still-strong formulation:

> Provenance is the process argument you will be asked for —
> before there is an explicit clause requiring it.

**E.5 — Close (1 min).**

Three sentences, then the Q&A slide:

- **What it bought us:** a run that can be reviewed, and a process that survives
  the person who designed it.
- **What it cost us:** more loops, more artefacts, and the discipline to keep the
  gates cheap enough that nobody disables them.
- **What we would do differently:** start from enforcement and add semantics —
  not the other way around.

Closing line, tying back to A:

> Better models removed the need to orchestrate for **capability**.
> They did not remove the need to orchestrate for **evidence**.

---

## 5. Diagram proposals

Draft form only. Final visual treatment belongs to the deck-building step.

### Diagram 1 — The side-effect axis (Section A)

```mermaid
flowchart LR
    A["<b>LLM</b><br/>predicts the next tokens"] --> B["<b>Chatbot</b><br/>+ conversation<br/>+ knowledge base"]
    B --> C["<b>Agent</b><br/>+ tools<br/>+ autonomous action"]
    C --> D{{"<b>Side effects</b><br/>in your systems"}}
```

*Intent:* one axis, one punchline. The arrow into "side effects" is the whole
message of section A.

### Diagram 2 — Instruction vs. Enforcement (Section B)

```mermaid
flowchart TB
    subgraph ADV["ADVISORY — the model may comply"]
        direction LR
        I1["instruction files"]
        I2["agent personas"]
        I3["prompt conventions"]
    end
    subgraph ENF["ENFORCED — the runtime rejects"]
        direction LR
        E1["pre-tool-use hooks"]
        E2["exit gates on handoff"]
        E3["git pre-commit hooks"]
        E4["server-side branch policies"]
    end
    ADV -.->|"no rejection path"| X["violation ships"]
    ENF ==>|"blocked before the action"| Y["violation stopped"]
```

*Intent:* the visual argument of the talk. Dotted line = hope; solid line =
mechanism. If the audience remembers one image, this should be it.

### Diagram 3 — A governed run (Section D.1)

```mermaid
flowchart LR
    H["human task"] --> CO["coordinator"]
    CO --> PL["plan"]
    PL --> TW["write failing tests"]
    TW --> TC{"test critic"}
    TC -->|REJECTED| TW
    TC -->|APPROVED| IM["implement"]
    IM --> CC{"code critic"}
    CC -->|REJECTED| IM
    CC -->|APPROVED| RF["refactor"]
    RF --> DOC["document"]
    DOC --> ART[("workflow log<br/>gate summary<br/>provenance")]
```

*Intent:* show that the loop-backs are the point. Overlay the three artefact
stops (hook denial, verdict, evidence) as callouts on this diagram rather than
as separate slides.

### Diagram 4 — Generic vs. project-specific (Section D.2)

```mermaid
flowchart TB
    subgraph CORE["generic framework — reusable"]
        P["principles"] --> R["domain rules"] --> W["workflows"] --> S["skills"]
    end
    subgraph PRJ["project binding — concrete"]
        CFG["configuration<br/>(tools, thresholds, integrations)"]
        CUR["curated agents & skills"]
        LOC["local adaptations"]
    end
    CORE -->|"assimilation + deploy"| PRJ
    PRJ -.->|"generalised learnings flow back"| CORE
```

*Intent:* the reusability argument in one picture. The dotted backflow arrow is
what separates a framework from a template.

### Diagram 5 — Lifecycle and non-destructive update (Section D.2)

```mermaid
flowchart LR
    D["deliver"] --> O["onboard<br/>(assimilate to the stack)"]
    O --> C["curate<br/>(deactivate what does not fit)"]
    C --> WK["governed work"]
    WK --> UP["framework update"]
    UP --> M{"three-way compare"}
    M -->|unchanged| WK
    M -->|"locally customised"| PRE["preserve / merge<br/>never overwrite"]
    PRE --> WK
```

*Intent:* answers *"what happens to my customisations when you ship v2?"* —
the first question any practitioner in the room will have.

---

## 6. Artefact inventory

All artefacts must be **sanitised or synthetic**: realistic in structure,
neutral in content. No project names, no customer data, no real repository paths.

The set maps 1:1 onto the three stops in D.1. Ready-to-use drafts are in
[talk-2026-07-29-artefacts.md](talk-2026-07-29-artefacts.md).

| # | Artefact | Section | Form | Status |
|---|---|---|---|---|
| 1a | **Red-phase block, front of house** — the chat transcript: a task is dispatched, the subagent believes it is finished, the hook refuses the handoff, the subagent self-corrects | D.1 stop 1 | **GIF, 8 frames, 26.6 s** + static fallback | **rendered** |
| 1b | **Red-phase block, backstage** — dispatch, the *passing* test that comes back, the run, the raw hook JSON, the refused handoff | D.1 stop 1 | **5 stills**, presenter-advanced | **rendered** |
| 2 | Implementer's self-reported gate summary (all green) | D.1 stop 2 | Text block | text drafted |
| 3 | Code-critic `REJECTED` verdict naming the gate that actually failed | D.1 stop 2 | Text block | text drafted |
| 4 | Pre-action denial of a forbidden git operation | D.1 stop 3 | Terminal still | text drafted |
| 5 | Workflow log excerpt (YAML) — the record the run leaves behind | D.1 wrap-up | Code block | text drafted |
| 6 | Provenance marker in a generated file | D.1 wrap-up | 2-line snippet | text drafted |
| 7 | Re-deploy conflict classification (customised file preserved) | D.2 | Text block | text drafted |
| 8 | The two self-quotes (self-check is SOFT; prompts are not the security boundary) | B.4 / E.1 | Pull quote | ready — verbatim in the repo |

> **On artefact 1 — why it is split.** The two halves answer different
> questions and therefore need different media. **1a is a reversal**: it looks
> like success, then it is refused. A reversal needs a time axis, so it is the
> talk's only animation — it loops beside you while you narrate, and it shows
> the **user's** point of view, which is the one the audience can put itself in.
> **1b is evidence**: JSON, assertions, exit codes. Evidence has to be *read*,
> and a loop that moves on mid-sentence fights the reader — so it is five stills
> the presenter advances. Shown side by side, 1a supplies the feeling and 1b
> supplies the proof.
>
> Both are rendered from scripts rather than screen-recorded, and the chat panel
> is deliberately stylised rather than an imitation of a real client. Name that
> in half a sentence on the day: a convincing fake screenshot would cast doubt
> on every genuine artefact around it. Always prepare the static fallback frame
> — embedded video is the most reliable way to derail a conference talk.

> **Sanitisation rule.** Realistic in structure, neutral in content: generic
> module names (`payments`, `orders`), no project or customer names, no real
> paths or identifiers. The *shape* follows the real hook output so that anyone
> who later sees the framework recognises it.

---

## 7. Defensible facts and sources

Everything cited on a slide must appear in this table. Nothing else gets cited.

| Claim | Figure | Source | Date |
|---|---|---|---|
| Better generic tools made an agent *worse*; re-tuning instructions cut review cost | **~20 %** lower cost at equal quality | GitHub Engineering — *"Better tools made Copilot code review worse — here's how we actually improved it"* | 2026-07-10 |
| Multi-agent complexity is optional; the harness is the lever | qualitative | GitHub — *"The harness is all you need (mostly)"* (Burke Holland) | 2026-07-27 |
| Cheap generation ≠ cheap change; reviewability is the real cost | qualitative | GitHub — *"The cost of saying yes has changed"* (Dalia Abuadas) | 2026-07-17 |
| Organisations exceeding AI budgets | **93 %** | McKinsey — *"Is that AI agent worth it?"* | 2026-07-13 |
| Organisations constraining AI use due to operating cost | **~1 in 5** | McKinsey, ibid. | 2026-07-13 |
| Share of agentic task cost tied to refining answers | **~60 %** | McKinsey, ibid. | 2026-07-13 |
| Variation between completions of the same task | **factor 30** | McKinsey, ibid. | 2026-07-13 |
| EU AI Act Article 50 transparency obligations enforceable | date | EU AI Act, Art. 50 | since **2026-08-02** (8 days before the talk) |
| AI management system standard (voluntary) | — | ISO/IEC 42001:2023 | 2023-12 |
| Generative AI risk profile (voluntary) | — | NIST AI RMF, NIST.AI.600-1 | 2024-07-26 |
| Spec-driven development, large ecosystem | 240+ contributors, 35+ agent integrations | GitHub Spec Kit | 2026-07 |

### Claims that must NOT be made

| ✗ Do not say | Why |
|---|---|
| "Scaffolding is obsolete now that models are strong." | The opposite is evidenced — GitHub's win came *from improving* scaffolding. |
| "X % of agent runs violate their instructions." | No vendor publishes adherence rates. Any number here is invented. |
| "Y % of AI-generated code contains defects." | No credible published statistic was found. |
| "IEC 62304 requires AI provenance marking." | False. It does not address AI-generated code at all. |
| "`AGENTS.md` is a cross-vendor standard." | It is emerging *practice*. No published specification found. |
| "We solved multi-agent orchestration." | Overclaim; the field is still learning. Frame as deterministic harness + human review. |
| "The EU AI Act obliges us to mark AI-generated code." | Contestable for internal tooling. Present as direction of travel. |
| Anything naming a real project, customer or dataset. | Explicitly out of scope per §1. |

---

## 8. Anticipated Q&A

Five minutes, so three or four questions at most. These are the likely ones.

| Question | Answer in one breath |
|---|---|
| **"Why not just do this in CI?"** | Three reasons, and the demo already showed all three. **(1)** Some conditions are *inverted* — the Red gate demands that tests **fail**; a green suite is CI's success criterion. **(2)** Some states are *transient* — without the harness the Red state never becomes a commit, so there is nothing for CI to inspect. **(3)** Some controls must *prevent*, not *detect* — CI reacts after the attempt. Short version: **CI verifies the artefacts of a process; it cannot verify that the process happened.** Use both — CI is the outer ring, hooks the inner one. |
| **"GitHub says the harness is all you need — isn't this over-engineering?"** | Agreed, for productivity. The disagreement is about the question being asked: *good result faster* vs. *demonstrable process*. Only the first is solved by a better model. |
| **"What does this cost in tokens and time?"** | It adds refinement loops on purpose. Published figures put ~60 % of agentic task cost in refinement anyway, with a factor-30 spread between runs. The gain is predictability, and the tiering keeps small changes cheap. |
| **"Do the agents actually follow this?"** | The semantic layer — sometimes. That is precisely why the enforcement layer exists outside the model, and why self-checks are classified as non-binding by design. |
| **"Isn't this locked to one vendor?"** | The generic layer is vendor-neutral; the vendor-specific part is an exchangeable adapter. That separation is the reason for the layered structure. |
| **"Can we get it?"** | It is not a product — it grew out of real project work. Happy to talk about the principles and what transfers. |

---

## 9. Open items before the deck is built

- [x] ~~Decide which single limitation from E.1 is named concretely.~~ Two are
      named: fail-open client-side enforcement, and evidence ≠ correctness.
- [x] ~~Confirm the talk date against the EU AI Act milestone.~~ 2026-08-10,
      i.e. eight days *after* — tense updated to "since".
- [x] ~~Draft the artefacts.~~ See
      [talk-2026-07-29-artefacts.md](talk-2026-07-29-artefacts.md).
- [x] ~~Record the GIF for artefact 1, plus a static fallback frame.~~ Rendered
      into `assets/` by [render-chat-loop.py](render-chat-loop.py) (1a) and
      [render-backstage-frames.py](render-backstage-frames.py) (1b).
- [ ] Typeset artefacts 2–7 for slide legibility — font size beats completeness;
      trim any block that does not read at presentation size.
- [ ] Verify each figure in §7 against its source once more immediately before
      the talk (all are from July 2026; none is load-bearing if dropped).
- [ ] Rehearse for time. Section D is the one that will overrun; section A is the
      one that must not.
- [ ] Decide whether the closing slide shows contact/discussion pointers.

---

## 10. Rejected alternatives (for the record)

| Considered | Rejected because |
|---|---|
| Opening with the L0–L4 layer model | Correct as design, wrong as pedagogy. Abstract-first loses a mixed room in 25 minutes. |
| Full framework tour in section D | Ten mechanisms listed convince nobody; three shown properly do. |
| Thesis "only self-built agent systems can guarantee this" | Easy to refute — CI, OPA and vendor hooks also enforce. Narrowed to "a harness must exist and must enforce outside the model". |
| Live demo | Too expensive in a 25-minute slot and too fragile. Replaced by artefacts + one short animation. |
| Leading with regulation | Overclaims quickly, and the audience is mixed-industry. Regulation supports the argument; it does not carry it. |
| Quoting instruction-adherence failure rates | No such published figures exist. The structural argument is stronger anyway. |
| "Don't Build Multi-Agents" (Cognition) as a cited source | The post could not be located during research. Not cited anywhere. Do not reintroduce without verifying it exists. |

### Limitation candidates that were considered and dropped

The limitations section went through one full round. These three were proposed
and rejected — recorded so they are not proposed again:

| Candidate | Rejected because |
|---|---|
| "Agent prompts are only conventions, so enforcement is weak" | Misstates the architecture. The hooks are executed by the **IDE runtime, not by the agent** — the agent cannot decline them. Prompts being conventions is true of the *semantic* layer only, and that distinction is already the point of section B. Reframed into the *client-side / fail-open* trade-off in E.1. |
| "Parts of the framework are aspirational, not implemented" | True but irrelevant, and actively misleading as a *limitation*. AAIG is built alongside production work; what is unimplemented reflects available time, not a design ceiling. The idea is the deliverable. Presenting a backlog as a structural weakness would understate the work. |
| "Parallel governed workstreams are constrained" | Not a real limitation — git worktrees address it and the approach has already been prototyped. Would have invited a question with an unsatisfying answer for no gain. |

What replaced them: two limitations derived from reading the hook
implementations rather than from the backlog — **fail-open client-side
enforcement** and **evidence ≠ correctness**. Both are trade-offs with a
rationale, not gaps awaiting work.

---

## 11. Where the background knowledge lives

The wiki was re-synchronised with the code on 2026-07-29 specifically so that
building this talk does not require reading source. Use it as the knowledge
base; go to source only for the two verbatim quotes and the hook behaviour.

| Talk section | Background |
|---|---|
| B · Instruction ≠ Enforcement | [11-hooks-and-autonomy.md](../wiki/11-hooks-and-autonomy.md) — hook inventory, autonomy categories, real git hooks |
| C · Thesis | [01-overview.md](../wiki/01-overview.md), [03-core-principles.md](../wiki/03-core-principles.md) |
| D.1 · The governed run | [10-agents.md](../wiki/10-agents.md) (roster, delegation), [06-workflows.md](../wiki/06-workflows.md) (TDD phases and gates) |
| D.2 · Abstraction and reuse | [02-architecture.md](../wiki/02-architecture.md) (L0–L4), [04-assimilation.md](../wiki/04-assimilation.md), [07-skills-toolbox.md](../wiki/07-skills-toolbox.md) (curation) |
| D.2 · Lifecycle and updates | [12-deployment.md](../wiki/12-deployment.md) — deliver → onboard → curate, three-way merge, managed regions |
| D.2 · Configuration seam | [13-configuration.md](../wiki/13-configuration.md) — `af-env.conf`, model tiers, autonomy switches |
| E · Limitations | [11-hooks-and-autonomy.md](../wiki/11-hooks-and-autonomy.md) plus the two hook scripts named below |
| Terminology | [15-glossary.md](../wiki/15-glossary.md) |

### Verified against source (not the wiki)

These few claims were checked directly in the code, because the talk asserts
precise behaviour:

| Claim | Verified in |
|---|---|
| The Red gate blocks the handoff when the suite passes | `flavors/github-copilot/.github/hooks/scripts/test-writer-stop.ps1` — exit code 0 → `decision: "block"` |
| Hooks are **fail-open** when the verifier is missing | same file, and `implementer-stop.ps1` — both emit "gate skipped" when the test runner is absent |
| The gate cannot judge *why* a test fails | same file — only the process exit code is evaluated |
| "Self-check is always SOFT, never HARD" | `.github/instructions/quality-gates.instructions.md` |
| "Agent prompts are conventions, not the security boundary" | `.github/instructions/git-workflow.instructions.md` |

### Provenance of the external figures

All figures in §7 come from a single research pass on **2026-07-29** against
published sources (GitHub Engineering blog, McKinsey QuantumBlack, the EU AI Act
reference site, ISO and NIST). Nothing was inferred or estimated. The
do-not-claim table in §7 lists what that research explicitly could **not**
substantiate — treat it as binding.
