#!/usr/bin/env python3
"""Report the retry and escalation economy per agent from the workflow logs.

A failed gate is the most expensive single event in a workflow: it pays the step
twice, and it pushes the coordinator's context toward the next compaction, which
is where the spend actually goes. Token counts per agent say how big a prompt
is; retry rate says which agent is wasting it (issue #43).

**Source.** `.github/logs/*.yaml` -- the framework's own record, committed with
the work, carrying the agent name on every step. Issue #43 named the VS Code
`transcripts/*.jsonl` instead. Those were measured and rejected as the primary
source: 143 MB of uncommitted machine-local state in which a retry has to be
inferred from an undocumented event shape, against a committed log that already
names the agent. The cost is that this reads a *self-report* -- a retry the
documenter did not write down is invisible here -- so the gap between what the
logs claim and what their own steps show is reported rather than smoothed over.

**This does not gate anything.** It reports. But it refuses to report zero
quietly: an unparsable log, a verdict outside the MANIFEST closed set, or a
summary that contradicts its own steps all exit 1 with the offenders named.
A measurement that cannot fail is not a measurement (#12, #125).

Exit codes:
    0  report produced, no drift
    1  report produced, drift found (named in the Drift section)
    2  cannot measure at all -- no logs, or no YAML parser

No hook runs this: it answers a question a human asked, at a terminal, about a
corpus that already exists (af-caller-ok).
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

# MANIFEST S 13 (Inter-Agent Contracts -> Verdict Format) defines the closed set.
CANONICAL = {"APPROVED", "REJECTED", "ESCALATE", "RESOLVED", "COMPROMISE"}
# Values that carry the same meaning and are not worth flagging on their own.
ABSENT = {"NULL", "NONE", "", "N/A"}

MAKERS = {"planner", "test-writer", "implementer", "refactorer", "documenter"}


class NoEvidence(Exception):
    """Nothing measurable was found -- reported as failure, never as zero."""


def _normalise(verdict: Any) -> str:
    """Map a verdict onto the closed set, or return the raw token upcased."""
    text = str(verdict).strip().upper()
    if text in ABSENT:
        return ""
    for name in CANONICAL:
        # `APPROVED (Attempt 2)` and `REJECTED (provisional)` both occur.
        if text == name or text.startswith((name + " ", name + "(")):
            return name
    return text


def _gate_failed(step: dict[str, Any]) -> bool:
    metrics = step.get("metrics")
    if not isinstance(metrics, dict):
        return False
    passed, total = metrics.get("hard_gates_passed"), metrics.get("hard_gates_total")
    return isinstance(passed, int) and isinstance(total, int) and passed < total


def _load(path: Path, drift: list[str]) -> dict[str, Any] | None:
    try:
        import yaml
    except ImportError as exc:  # pragma: no cover - environment, not logic
        raise NoEvidence("PyYAML is required to read workflow logs: pip install pyyaml") from exc
    try:
        doc = yaml.safe_load(path.read_text(encoding="utf-8", errors="replace"))
    except yaml.YAMLError as exc:
        drift.append(f"{path.name}: not parsable as YAML ({type(exc).__name__}) -- excluded from every number below")
        return None
    if not isinstance(doc, dict):
        drift.append(f"{path.name}: top level is not a mapping -- excluded")
        return None
    return doc


class Economy:
    """Per-agent retry and escalation counts, derived from step sequences."""

    def __init__(self) -> None:
        self.steps: Counter[str] = Counter()
        self.retries: Counter[str] = Counter()
        self.causes: defaultdict[str, Counter[str]] = defaultdict(Counter)
        self.escalations: Counter[str] = Counter()
        self.escalated_at: defaultdict[str, list[int]] = defaultdict(list)
        self.rejections_issued: Counter[str] = Counter()
        self.rejections_received: Counter[str] = Counter()
        self.workflows_seen: defaultdict[str, set[str]] = defaultdict(set)
        self.workflows_retried: defaultdict[str, set[str]] = defaultdict(set)
        self.per_workflow: dict[str, int] = {}
        self.mismatch: list[tuple[str, int, int, int, int]] = []
        self.unknown_verdicts: Counter[str] = Counter()

    def add(self, workflow: str, doc: dict[str, Any]) -> None:
        steps = [s for s in (doc.get("steps") or []) if isinstance(s, dict)]
        agents = [str(s.get("agent", "?")).strip() for s in steps]
        verdicts = [_normalise(s.get("verdict")) for s in steps]

        for agent, verdict, raw in zip(agents, verdicts, (s.get("verdict") for s in steps)):
            self.steps[agent] += 1
            self.workflows_seen[agent].add(workflow)
            if verdict and verdict not in CANONICAL:
                self.unknown_verdicts[str(raw).strip()] += 1
            if verdict == "REJECTED":
                self.rejections_issued[agent] += 1

        retries = escalations = 0
        runs: dict[str, int] = {}
        last_index: dict[str, int] = {}
        for index, (agent, verdict) in enumerate(zip(agents, verdicts)):
            if verdict == "ESCALATE":
                escalations += 1
                self.escalations[agent] += 1
                self.escalated_at[agent].append(runs.get(agent, 0))
            if agent in runs:
                retries += 1
                self.retries[agent] += 1
                self.workflows_retried[agent].add(workflow)
                cause, blamed = self._cause(steps, verdicts, last_index[agent], index)
                self.causes[agent][cause] += 1
                if blamed:
                    self.rejections_received[agent] += 1
            runs[agent] = runs.get(agent, 0) + 1
            last_index[agent] = index

        summary = doc.get("summary") if isinstance(doc.get("summary"), dict) else {}
        claimed_r = summary.get("retries")
        claimed_e = summary.get("escalations")
        if doc.get("escalation"):
            escalations = max(escalations, 1)
        self.per_workflow[workflow] = retries
        if (
            isinstance(claimed_r, int)
            and claimed_r != retries
            or isinstance(claimed_e, int)
            and claimed_e != escalations
        ):
            self.mismatch.append(
                (
                    workflow,
                    claimed_r if isinstance(claimed_r, int) else -1,
                    retries,
                    claimed_e if isinstance(claimed_e, int) else -1,
                    escalations,
                )
            )

    @staticmethod
    def _cause(steps: list[dict[str, Any]], verdicts: list[str], previous: int, current: int) -> tuple[str, bool]:
        """Why the agent ran again. Stated as a heuristic, not as a fact."""
        between = list(range(previous + 1, current))
        for i in between:
            if verdicts[i] in {"REJECTED", "ESCALATE"}:
                return "critic-rejected", True
        for i in between:
            if _gate_failed(steps[i]):
                return "gate-failed", False
        if _gate_failed(steps[previous]):
            return "gate-failed", False
        if not between:
            return "consecutive-pass", False
        return "unattributed", False


HEURISTIC = """\
Heuristic -- read this before the numbers:
  * A RETRY is the same agent appearing more than once in one workflow's `steps`.
    Occurrence n>1 is counted as retry n-1. This is structure, not intent: a
    deliberate second pass and a forced rework look identical in the log.
  * The CAUSE is read from the steps in between. A REJECTED or ESCALATE verdict
    there -> `critic-rejected`. A step reporting hard_gates_passed <
    hard_gates_total -> `gate-failed`. No step in between at all ->
    `consecutive-pass` (the agent simply ran twice in a row). Otherwise
    `unattributed`.
  * TOOL ERRORS, the third cause issue #43 asks for, are NOT derivable from
    these logs. No step records them. That column is missing, not zero.
  * Everything here is a self-report written after the fact by the documenter.
    A retry nobody logged does not appear."""


def report(economy: Economy, logs: int, drift: list[str], as_json: bool) -> int:
    if as_json:
        payload = {
            "logs_read": logs,
            "steps": dict(economy.steps),
            "retries": dict(economy.retries),
            "causes": {a: dict(c) for a, c in economy.causes.items()},
            "escalations": dict(economy.escalations),
            "rejections_issued": dict(economy.rejections_issued),
            "retries_per_workflow": economy.per_workflow,
            "summary_mismatch": economy.mismatch,
            "unknown_verdicts": dict(economy.unknown_verdicts),
            "drift": drift,
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1 if drift or economy.mismatch or economy.unknown_verdicts else 0

    print(HEURISTIC)
    print()
    print(f"Corpus: {logs} workflow log(s) read, {len(drift)} excluded.")
    print()

    print("Retries per agent")
    print(f"  {'agent':<24} {'steps':>6} {'retries':>8} {'rate':>7}  causes")
    for agent, count in economy.steps.most_common():
        retries = economy.retries[agent]
        rate = f"{retries / count:.2f}" if count else "-"
        causes = ", ".join(f"{k}={v}" for k, v in economy.causes[agent].most_common()) or "-"
        print(f"  {agent:<24} {count:>6} {retries:>8} {rate:>7}  {causes}")
    print()

    print("Distribution -- one agent retrying constantly is not every agent retrying once")
    print(f"  {'agent':<24} {'workflows':>10} {'with retry':>11} {'share':>7}")
    for agent, _ in economy.steps.most_common():
        seen = len(economy.workflows_seen[agent])
        retried = len(economy.workflows_retried[agent])
        share = f"{retried / seen:.0%}" if seen else "-"
        print(f"  {agent:<24} {seen:>10} {retried:>11} {share:>7}")
    print()
    histogram = Counter(economy.per_workflow.values())
    spread = " ".join(f"{n}x{histogram[n]}" for n in sorted(histogram))
    print(f"  retries per workflow: {spread}   (retries x workflows)")
    print()

    print("Escalations")
    if not economy.escalations:
        print("  none recorded in any step verdict.")
    for agent, count in economy.escalations.most_common():
        at = ", ".join(str(n) for n in economy.escalated_at[agent])
        print(f"  {agent:<24} {count:>3}   after retry number(s): {at}")
    print()

    print("Critic verdicts issued")
    for agent, count in economy.rejections_issued.most_common():
        print(f"  {agent:<24} {count:>3} REJECTED")
    print()

    exit_code = 0
    if economy.mismatch:
        exit_code = 1
        print("Drift -- the summary contradicts its own steps")
        print(f"  {'workflow':<44} {'claimed':>8} {'counted':>8}  escalations")
        for workflow, cr, r, ce, e in economy.mismatch:
            print(f"  {workflow:<44} {cr:>8} {r:>8}  claimed {ce}, counted {e}")
        print()
    if economy.unknown_verdicts:
        exit_code = 1
        print(f"Drift -- verdicts outside the MANIFEST closed set ({'/'.join(sorted(CANONICAL))})")
        for value, count in economy.unknown_verdicts.most_common():
            print(f"  {value!r:<44} x{count}")
        print()
    if drift:
        exit_code = 1
        print("Drift -- logs that could not be read")
        for line in drift:
            print(f"  {line}")
        print()
    if exit_code == 0:
        print("No drift: every log parsed, every verdict canonical, every summary agreed.")
    return exit_code


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--logs-dir", default=".github/logs", help="directory of workflow log YAML files")
    parser.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    args = parser.parse_args(argv)

    directory = Path(args.logs_dir)
    if not directory.is_dir():
        print(f"ERROR: no such directory: {directory}", file=sys.stderr)
        return 2
    files = sorted(directory.rglob("*.yaml")) + sorted(directory.rglob("*.yml"))
    if not files:
        print(
            f"ERROR: no workflow logs under {directory} -- nothing to measure. "
            "Reporting zero here would be a lie about the framework, not a fact "
            "about it.",
            file=sys.stderr,
        )
        return 2

    drift: list[str] = []
    economy = Economy()
    read = 0
    try:
        for path in files:
            doc = _load(path, drift)
            if doc is None:
                continue
            read += 1
            economy.add(str(doc.get("workflow_id") or path.stem), doc)
    except NoEvidence as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if read == 0:
        print(f"ERROR: {len(files)} log(s) found, none readable -- see below.", file=sys.stderr)
        for line in drift:
            print(f"  {line}", file=sys.stderr)
        return 2
    return report(economy, read, drift, args.json)


if __name__ == "__main__":
    sys.exit(main())
