---
category: project_management
applies_to: [all]
complexity: foundational
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [task_decomposition, risk_management, documentation]
---
# Stakeholder Communication

## Purpose

Stakeholder communication ensures that the right people receive the right information at the right time, enabling informed decisions and maintaining alignment. Invoke this skill when defining communication plans, writing status reports, or creating Level-3 communication workflows.

## Principles

- **Audience-first:** Tailor message granularity, format, and channel to the audience. Executives want impact; engineers want details.
- **Proactive, not reactive:** Share progress, risks, and blockers before they become surprises.
- **Transparency (AAIG L1):** Decisions, risks, and status must be documented and shared with stakeholders.
- **Efficiency (AAIG L1):** Communicate what matters. Information overload is as bad as information scarcity.

## Techniques & Patterns

### Stakeholder Map

| Stakeholder Type | Interest | Information Need | Cadence |
|-----------------|----------|-----------------|---------|
| **Sponsor / Executive** | ROI, timeline, risks | High-level status, decisions needed | Weekly or bi-weekly |
| **Product Owner** | Features, priorities, quality | Detailed progress, trade-offs, blockers | Daily or per-sprint |
| **Dev Team** | Technical details, dependencies | Task status, blockers, design decisions | Daily (standup) |
| **End Users** | Functionality, experience | Release notes, known issues, timelines | Per release |
| **Ops / SRE** | Reliability, deployment | Change logs, runbooks, incident updates | Per deployment |

### Status Report Template

```markdown
# Status Report: [Project Name]
**Period:** [Date range]  |  **Author:** [Name]  |  **Status:** ðŸŸ¢ On Track / ðŸŸ¡ At Risk / ðŸ"´ Off Track

## Summary
[2-3 sentence executive summary of where the project stands.]

## Progress
- [x] Completed item 1
- [x] Completed item 2
- [/] In progress: item 3 (expected completion: [date])

## Upcoming
- [ ] Next milestone 1 (target: [date])
- [ ] Next milestone 2 (target: [date])

## Risks & Issues
| Risk/Issue | Impact | Mitigation | Owner |
|-----------|--------|------------|-------|
| [Description] | [H/M/L] | [Action] | [Who] |

## Decisions Needed
1. [Decision needed, options, recommendation]

## Metrics
| Metric | Current | Target |
|--------|---------|--------|
| [e.g., Sprint velocity] | [value] | [target] |
```

### Communication Channels

| Channel | Best For | Not For |
|---------|----------|---------|
| **Standup / sync meeting** | Blockers, coordination, quick alignment | Deep discussion, decisions |
| **Written status report** | Async updates, record keeping | Urgent issues |
| **PR / code review** | Technical discussion on specific changes | Strategic decisions |
| **ADR / Decision Log** | Documenting architectural decisions | Routine updates |
| **Incident report** | Post-incident analysis and learning | Blame |
| **Demo / showcase** | Showing working software, gathering feedback | Status updates (show, don't tell) |
| **1:1 conversation** | Sensitive feedback, career discussion | Broadcasting information |

### Escalation Framework

| Level | When to Escalate | To Whom |
|-------|-----------------|---------|
| **L1: Team** | Blocker that the team can resolve | Tech lead / PM |
| **L2: Cross-team** | Dependency or conflict across teams | Engineering manager |
| **L3: Leadership** | Timeline risk, budget impact, strategic conflict | Director / VP |

**Rules:**
- Escalate early, not late. "I think we might have a problem" is better than "We missed the deadline."
- Always propose a solution (or options) when escalating.
- Document the escalation and resolution in the Decision Log.

### Difficult Communications

| Situation | Approach |
|-----------|---------|
| **Deadline at risk** | Name it early. Present: current state, root cause, revised timeline, mitigation options. |
| **Scope change request** | Quantify impact on timeline and resources. Present trade-offs, not just "no." |
| **Quality concern** | Present data (test results, metrics). Avoid subjective language. Propose specific improvements. |
| **Post-incident** | Blameless post-mortem. Focus on system improvements, not individual failures. |

### Meeting Effectiveness

**For every meeting, define:**
- **Purpose:** Why are we meeting? (Decision, brainstorm, status, or coordination?)
- **Agenda:** What will we cover? (Shared in advance.)
- **Output:** What should we have at the end? (Decision, action items, aligned understanding?)
- **Participants:** Who actually needs to be there?

**Rules:**
- No agenda = no meeting.
- Document decisions and action items within 24 hours.
- Default to 25-minute meetings, not 30. Give people a buffer.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Status report delivered** | On schedule | Weekly or per agreed cadence. |
| **Risks documented** | All known risks | Updated in status reports and risk register. |
| **Decisions logged** | 100% of architectural/strategic decisions | ADR or Decision Log entry. |
| **Escalations timely** | < 24h from identification | Blockers escalated within one business day. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Surprise deadline miss** | Stakeholders learn about delays at the last moment. | Proactive communication. Flag risks weekly. |
| **Information asymmetry** | Some stakeholders know things others don't. | Use shared channels and status reports. |
| **Meeting overload** | Calendar full of status meetings. No time to work. | Text-based async updates. Meetings only for decisions. |
| **No written record** | "We agreed on X." "No, we agreed on Y." | Document decisions immediately. Use Decision Log. |
| **All bad news, no good news** | Communication only happens when there's a problem. | Include wins and progress, not just risks. |


## See Also

- [Task Decomposition](../project_management/task_decomposition.md)
- [Risk Management](../project_management/risk_management.md)
- [Documentation](../code_quality/documentation.md)

## References

- Patrick Lencioni, *The Advantage* (2012) -- organizational communication health.
- Esther Derby & Diana Larsen, *Agile Retrospectives* (2006) -- effective team communication.
- Atlassian Team Playbook: https://www.atlassian.com/team-playbook
