<!-- Delete whatever does not apply. -->

## What changed

## Why

<!--
Required only when this pull request changes files under
flavors/github-copilot/.github/hooks/

test-hooks-integration.ps1 reads Copilot session events, bound to an exact
workspace and session. A hosted runner has no developer session evidence,
so CI excludes the live suite. If you touched the hooks, run it locally after
a fresh Copilot session with the change deployed and uncomment the line below.
The regression job fails without it. Preserve the JSON report and session id.

    powershell -NoProfile -ExecutionPolicy Bypass -File flavors\github-copilot\.github\scripts\test-hooks-integration.ps1 -Workspace <deployed-project> -SessionId <copilot-session-id>

The report checks lifecycle pairing and observed hook failures, not individual
AF script identities, verdicts or timeouts (not exposed by this stream).
Never present lifecycle success alone as proof that a particular gate worked.
An ambiguous session, missing lifecycle or incomplete record exits 2, not pass.
Automatic CLI attestation and its three licence cases remain separate (#553);
the local-check marker remains the fallback until that capability is verified.

This line is an attestation, not evidence. It records that you state you ran
the suite; nothing checks that you did, and it must never be cited as proof
that the hooks were tested. It exists because the failure it prevents is
forgetting, not lying.

On a dev -> main promotion, leave it commented out. You did not run the suite
for those changes and could not mean the statement; CI checks the pull
requests that did instead (#234).
-->

<!-- local-check: test-hooks-integration.ps1 -->

<!--
Required only when this pull request changes .vscode/, .githooks/ or the
repository's own .github/ -- the files that decide which guards run and what
CI enforces. Payload hooks under flavors/ are covered by the line above
instead.

Uncomment and state why, in your own words. The regression job fails on an
empty reason, because a marker with nothing after it is a checkbox, and a
checkbox gets ticked.

On a dev -> main promotion, leave it commented out, for the same reason as
above (#234).
-->

<!-- env-change: -->

## Closes

<!--
Put closing keywords on a plain line of body text, not inside a heading or a
table. #160 records a release where `Closes #N` inside a `###` heading
registered the link but did not close the issue.
-->
