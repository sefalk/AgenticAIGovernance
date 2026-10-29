### Fixed

- **The context budget no longer charges a consumer's activated optional skills
  to the framework's catalogue share (#471).** An optional skill the project
  moved from `skills/_available/` to `skills/` is deployed and therefore listed
  in `.af-hashes`, so `check-context-budget.py` counted it as AF's own: MP failed
  the AF catalogue ceiling at 3,584 > 3,400 tokens although no AF catalogue entry
  had changed. The payload now ships `skills/default-skills.txt`, the skills AF
  itself activates; any other active skill counts against the project share.
  Measured on a copy of MP's tree: AF catalogue 3,320 / 3,400. Without the list
  (an older payload) attribution is unchanged, and `test-context-budget.ps1`
  pins the list to the source tree's active skills.
