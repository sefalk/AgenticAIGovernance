<!-- Delete whatever does not apply. -->

## What changed

## Why

<!--
Required only when this pull request changes files under
flavors/github-copilot/.github/hooks/

test-hooks-integration.ps1 reads VS Code's own hook log to confirm that hooks
fired during a real agent session. A hosted runner has no such log, so CI
excludes the suite and cannot run it. If you touched the hooks, run it locally
and uncomment the line below. The regression job fails without it.

    powershell -NoProfile -ExecutionPolicy Bypass -File flavors\github-copilot\.github\scripts\test-hooks-integration.ps1

This line is an attestation, not evidence. It records that you state you ran
the suite; nothing checks that you did, and it must never be cited as proof
that the hooks were tested. It exists because the failure it prevents is
forgetting, not lying.
-->

<!-- local-check: test-hooks-integration.ps1 -->

## Closes

<!--
Put closing keywords on a plain line of body text, not inside a heading or a
table. #160 records a release where `Closes #N` inside a `###` heading
registered the link but did not close the issue.
-->
