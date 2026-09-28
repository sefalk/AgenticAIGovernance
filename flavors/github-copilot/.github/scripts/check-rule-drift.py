#!/usr/bin/env python3
"""Derive the rule-duplication inventory of the always-on and agent set (#304).

A hand-written inventory of duplicated rules was stale before anyone acted on
it: the files it covered grew by a third to double while #30 sat open. This
derives it instead -- deterministically, offline, no model in the path -- so a
later run can be diffed against a committed baseline rather than re-judged.

Corpus (relative to --root, a `.github` directory):
    MANIFEST.md, copilot-instructions.md, instructions/*.instructions.md,
    agents/*.agent.md

A *rule* is a sentence carrying a modal or imperative: must, must not, never,
always, do not, don't, may only, shall. Frontmatter, fenced code, HTML
comments, headings and table rows are skipped -- tables are gate definitions
whose repetition is structural, and quoting a rule in a code block is not
restating it.

Two rules in different files form a cluster when their content-word sets
(modals and stopwords removed, plurals folded) overlap by Jaccard >= 0.6 and
each keeps at least three content words. Verdict: `agree` when every
normalised wording is identical, `diverge` otherwise -- the case that matters,
because two wordings of one rule drift apart.

Without --baseline it only reports and always exits 0.

The gate (#305): with --baseline FILE every cluster must appear in FILE with a
`decision` (`keep` or `aligned`) and a `reason`; otherwise exit 1. A cluster
is identified by its members' file and normalised wording, not their line, so
moving a rule keeps its decision while a new duplicate -- or a reworded member,
which is how two copies start to drift -- has none. A baseline cluster that no
longer occurs passes: resolving a duplicate is always allowed.

--write-baseline FILE writes the inventory to FILE, carrying each decision over
by the same key. It writes the file itself because a PowerShell pipe once
stored every dash of the baseline as cp437 mojibake.

Usage:
    check-rule-drift.py [--root DIR] [--json] [--baseline FILE | --write-baseline FILE]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SIMILARITY = 0.6
MIN_CONTENT_WORDS = 3
DECISIONS = frozenset({"keep", "aligned"})
MIN_REASON_CHARS = 20

_MODAL = re.compile(r"\b(must|never|always|do not|don't|may only|shall)\b", re.IGNORECASE)
_FENCE = re.compile(r"^\s*(```|~~~)")
_LIST_ITEM = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+")
_INLINE_COMMENT = re.compile(r"<!--.*?-->")
# A sentence may end inside emphasis or a quote: `rule.**`, `rule.*`, `rule."`.
_SENTENCE_END = re.compile(
    r"(?:(?<=[.!?])|(?<=[.!?]\*\*)|(?<=[.!?]\*)|(?<=[.!?]`)|(?<=[.!?]\")|(?<=[.!?]\)))\s+(?=[A-Z*`\"'(\[])"
)
_LINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")
_NON_WORD = re.compile(r"[^a-z0-9]+")

MODAL_WORDS = frozenset({"must", "never", "always", "do", "not", "don", "t", "may", "only", "shall"})
STOPWORDS = frozenset(
    [
        "a",
        "an",
        "the",
        "to",
        "of",
        "in",
        "on",
        "at",
        "by",
        "for",
        "with",
        "and",
        "or",
        "but",
        "if",
        "then",
        "than",
        "that",
        "this",
        "these",
        "those",
        "it",
        "its",
        "is",
        "are",
        "be",
        "been",
        "was",
        "were",
        "as",
        "from",
        "into",
        "any",
        "every",
        "each",
        "all",
        "no",
        "so",
        "such",
        "can",
        "will",
        "would",
        "should",
        "their",
        "there",
        "here",
        "when",
        "which",
        "who",
        "what",
        "your",
        "you",
        "we",
        "our",
        "they",
        "them",
        "he",
        "she",
        "his",
        "her",
    ]
)


def corpus(root: Path) -> list[Path]:
    files = [root / "MANIFEST.md", root / "copilot-instructions.md"]
    files += sorted((root / "instructions").glob("*.instructions.md"))
    files += sorted((root / "agents").glob("*.agent.md"))
    return [f for f in files if f.is_file()]


def statements(path: Path) -> list[tuple[int, str]]:
    """(line number, sentence) for every rule-bearing sentence outside skipped blocks.

    Wrapped lines are joined into paragraphs first -- a list item starts a new
    one -- so a rule is compared as a sentence, not as a line fragment. The line
    reported is the one the sentence starts on.
    """
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    paragraphs: list[list[tuple[int, str]]] = []
    current: list[tuple[int, str]] = []
    in_fence = in_comment = False
    start = 0
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                start = i + 1
                break

    def flush() -> None:
        nonlocal current
        if current:
            paragraphs.append(current)
        current = []

    for index in range(start, len(lines)):
        raw = lines[index]
        if _FENCE.match(raw):
            flush()
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if "<!--" in raw and "-->" not in raw:
            flush()
            in_comment = True
            continue
        if in_comment:
            in_comment = "-->" not in raw
            continue
        text = _INLINE_COMMENT.sub("", raw).strip()
        if not text or text.startswith(("#", "|", ">")):
            flush()
            continue
        if _LIST_ITEM.match(raw):
            flush()
        current.append((index + 1, text))
    flush()

    out: list[tuple[int, str]] = []
    for para in paragraphs:
        joined, offsets = "", []
        for line_no, text in para:
            if joined:
                joined += " "
            offsets.append((len(joined), line_no))
            joined += text
        position = 0
        for sentence in _SENTENCE_END.split(joined):
            found = joined.find(sentence, position)
            position = found + len(sentence)
            if _MODAL.search(sentence):
                line_no = max(n for off, n in offsets if off <= found)
                out.append((line_no, sentence.strip()))
    return out


def normalise(sentence: str) -> str:
    text = _LINK.sub(r"\1", sentence).lower()
    text = re.sub(r"^\s*(?:[-*+]|\d+[.)])\s+", "", text)
    return " ".join(_NON_WORD.sub(" ", text).split())


def content_words(normalised: str) -> frozenset[str]:
    words = set()
    for word in normalised.split():
        if word in MODAL_WORDS or word in STOPWORDS or len(word) < 2:
            continue
        words.add(word[:-1] if len(word) > 3 and word.endswith("s") and not word.endswith("ss") else word)
    return frozenset(words)


def inventory(root: Path) -> dict[str, object]:
    rules = []
    for path in corpus(root):
        rel = path.relative_to(root).as_posix()
        for line, sentence in statements(path):
            norm = normalise(sentence)
            words = content_words(norm)
            if len(words) >= MIN_CONTENT_WORDS:
                rules.append({"file": rel, "line": line, "text": sentence, "norm": norm, "words": words})

    parent = list(range(len(rules)))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(len(rules)):
        for j in range(i + 1, len(rules)):
            a, b = rules[i], rules[j]
            if a["file"] == b["file"]:
                continue
            union = len(a["words"] | b["words"])
            if union and len(a["words"] & b["words"]) / union >= SIMILARITY:
                parent[find(i)] = find(j)

    groups: dict[int, list[int]] = {}
    for i in range(len(rules)):
        groups.setdefault(find(i), []).append(i)

    clusters = []
    for members in groups.values():
        if len({rules[m]["file"] for m in members}) < 2:
            continue
        members.sort(key=lambda m: (rules[m]["file"], rules[m]["line"]))
        verdict = "agree" if len({rules[m]["norm"] for m in members}) == 1 else "diverge"
        clusters.append(
            {
                "verdict": verdict,
                "statement": rules[members[0]]["text"],
                "locations": [
                    {"file": rules[m]["file"], "line": rules[m]["line"], "text": rules[m]["text"]} for m in members
                ],
            }
        )
    clusters.sort(key=lambda c: (c["verdict"], c["locations"][0]["file"], c["locations"][0]["line"]))
    return {
        "corpus": {"files": len(corpus(root)), "rules": len(rules)},
        "similarity": SIMILARITY,
        "summary": {
            "clusters": len(clusters),
            "agree": sum(1 for c in clusters if c["verdict"] == "agree"),
            "diverge": sum(1 for c in clusters if c["verdict"] == "diverge"),
        },
        "clusters": clusters,
    }


def render(inv: dict[str, object]) -> str:
    out = [
        f"rule-drift: {inv['corpus']['rules']} rules in {inv['corpus']['files']} files; "
        f"{inv['summary']['clusters']} clusters ({inv['summary']['agree']} agree, "
        f"{inv['summary']['diverge']} diverge); similarity >= {inv['similarity']}"
    ]
    for number, cluster in enumerate(inv["clusters"], start=1):
        out.append("")
        out.append(f"[{number}] {cluster['verdict']}: {cluster['statement']}")
        for loc in cluster["locations"]:
            out.append(f"    {loc['file']}:{loc['line']}  {loc['text']}")
    return "\n".join(out)


def cluster_key(cluster: dict[str, object]) -> str:
    return "\n".join(sorted(f"{loc['file']}\t{normalise(loc['text'])}" for loc in cluster["locations"]))


def load_decisions(path: Path) -> dict[str, dict[str, object]]:
    if not path.is_file():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return {cluster_key(c): c for c in data.get("clusters", [])}


def gate(inv: dict[str, object], decided: dict[str, dict[str, object]]) -> tuple[int, str]:
    findings = []
    current = set()
    for cluster in inv["clusters"]:
        key = cluster_key(cluster)
        current.add(key)
        where = ", ".join(f"{loc['file']}:{loc['line']}" for loc in cluster["locations"])
        entry = decided.get(key)
        if entry is None:
            findings.append(f"NEW        {cluster['verdict']}: {where}\n           {cluster['statement']}")
        elif entry.get("decision") not in DECISIONS or len(str(entry.get("reason") or "").strip()) < MIN_REASON_CHARS:
            findings.append(f"UNDECIDED  {cluster['verdict']}: {where}\n           {cluster['statement']}")
    resolved = sum(1 for key in decided if key not in current)
    head = (
        f"rule-drift gate: {len(inv['clusters'])} clusters, {len(findings)} without a recorded decision, "
        f"{resolved} resolved since the baseline"
    )
    if not findings:
        return 0, head
    hint = (
        "Resolve the duplicate, or record why each agent needs it: add `decision` "
        f"({' | '.join(sorted(DECISIONS))}) and `reason` to the cluster in the baseline."
    )
    return 1, "\n".join([head, *findings, hint])


def write_baseline(inv: dict[str, object], path: Path) -> None:
    decided = load_decisions(path)
    for index, cluster in enumerate(inv["clusters"]):
        entry = decided.get(cluster_key(cluster), {})
        inv["clusters"][index] = {"decision": entry.get("decision"), "reason": entry.get("reason"), **cluster}
    path.write_text(json.dumps(inv, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    parser.add_argument("--json", action="store_true")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--baseline", type=Path)
    # af-caller-ok: run by the maintainer who records a decision after the gate reports NEW.
    mode.add_argument("--write-baseline", type=Path)
    args = parser.parse_args(argv)
    inv = inventory(Path(args.root))
    code = 0
    if args.write_baseline:
        write_baseline(inv, args.write_baseline)
        text = f"rule-drift: baseline written to {args.write_baseline} ({inv['summary']['clusters']} clusters)"
    elif args.baseline:
        code, text = gate(inv, load_decisions(args.baseline))
    else:
        text = json.dumps(inv, indent=2, ensure_ascii=False) if args.json else render(inv)
    sys.stdout.buffer.write((text + "\n").encode("utf-8"))
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
