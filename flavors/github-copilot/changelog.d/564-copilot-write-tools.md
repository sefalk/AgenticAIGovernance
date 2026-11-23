### Security

- **Write gates now recognise the Copilot harness's file tools (#564).** Under
  the Copilot harness, `create`, `edit`, `apply_patch` and their PascalCase
  names `Write` and `Edit` were not counted as writes. A native `apply_patch`
  reached the hooks as `Edit` with the patch as a plain string. As a result,
  plan-directory confinement, test-only writes, the trust-store deny, the
  coordinator write rules and the secret scan all returned `{}`, which looks
  the same as an approval. All four write-tool lists now include these names.
  Every path extractor also reads the target paths from patch text
  (`Add`/`Update`/`Delete File`, `Move to`), whether the patch arrives as a
  bare string or under `input`. `test-copilot-write-tools.ps1` uses the
  captured payload shape as its fixture.
