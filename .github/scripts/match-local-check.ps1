<#
.SYNOPSIS
    Decide whether a pull request body attests that test-hooks-integration.ps1
    was run locally.

.DESCRIPTION
    Two steps in regression.yml ask the same question of a pull request body:
    the per-feature attestation gate, and the promotion check that walks the
    pull requests contributing to a dev -> main release. They used to carry a
    literal each. Two literals are two opinions about what the marker looks
    like, and #313 is what it costs when one of them is narrower than the way
    authors actually write: a body that attested correctly was rejected, and
    the message sent the author to add a line that was already there.

    This is the single definition. Both steps invoke it; neither matches on
    its own.

.OUTPUTS
    A verdict word on stdout, and an exit code the caller branches on:

        0  MATCH      -- the body attests.
        1  ABSENT     -- nothing resembling the marker is in the body.
        2  MALFORMED  -- a `local-check:` line is present but does not name the
                        suite in a form this gate can read. Distinguishing this
                        from ABSENT is the point of the file: "you did not
                        attest" and "I could not read your attestation" are
                        different problems and #313 is the second one being
                        reported as the first.

.EXAMPLE
    & .github/scripts/match-local-check.ps1 -Body $body
    switch ($LASTEXITCODE) { 0 { 'attested' } 2 { 'unreadable' } default { 'absent' } }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [AllowNull()]
    [string]$Body
)

Set-StrictMode -Version Latest

# HTML comments go first, and nothing below may undo that. The pull request
# template ships the marker commented out (.github/pull_request_template.md
# line 28), so a template nobody edited would otherwise satisfy a check about
# work somebody did -- the property #234 installed and the one most at risk
# from any normalisation added later.
$stripped = [regex]::Replace([string]$Body, '(?s)<!--.*?-->', '')

# Backticks around a filename are ordinary markdown, not a mistake, so the
# marker is recognised with or without them. They are tolerated at the one
# position that actually broke -- between the colon and the filename -- rather
# than stripped from the body at large: a global strip would be a
# normalisation with no boundary, and the next person to add one would have to
# re-derive why the comment strip above has to run first.
#
# Deliberately not anchored to the start of a line. The literal substring it
# replaces matched anywhere in the body, and tightening that here would reject
# bodies that pass today -- a second false rejection is not the fix for the
# first one.
$markerPattern = 'local-check:[ \t]*`?test-hooks-integration\.ps1'

# What a near miss looks like: the author reached for the marker and the gate
# could not read what they wrote. Only ever reached when the gate is already
# rejecting, so at worst it makes a message more specific than it needed to be.
$nearMissPattern = 'local-check:'

if ([regex]::IsMatch($stripped, $markerPattern)) {
    Write-Output 'MATCH'
    exit 0
}

if ([regex]::IsMatch($stripped, $nearMissPattern)) {
    Write-Output 'MALFORMED'
    exit 2
}

Write-Output 'ABSENT'
exit 1
