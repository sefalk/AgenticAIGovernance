### Fixed

- **The staged context-budget guard measures with `skills/default-skills.txt`
  (#495).** It exported only `skills/*/SKILL.md` into its temporary tree, so the
  #471 list never reached the checker. An activated optional skill was charged
  to AF again. MP's 1.28.2 payload commit was blocked at 3,584 > 3,400 while
  `check-context-budget.py` on the same tree reported 3,320 / 3,400. With the
  fix, the guard on that staged commit reports `AF catalogue 3,320/3,400` and
  passes.
