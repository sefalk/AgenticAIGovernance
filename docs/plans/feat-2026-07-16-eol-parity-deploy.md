# Feat: EOL/BOM Parity between deploy.ps1/.sh and the MCP deploy

- **Branch:** `agent/eol-parity-deploy`
- **Status:** COMPLETED
- **Complexity tier:** Standard
- **Date:** 2026-07-16

## Problem

Switching between the two deploy paths (`deploy.ps1`/`deploy.sh` and the MCP
`af_deploy_mcp`) produces spurious whole-file diffs caused by line-ending
divergence (LF vs CRLF), even when content is byte-identical. A 1.20.1 → 1.20.3
MCP redeploy after a `deploy.ps1` rollout reported ~59 UPDATE that were pure EOL
diffs. This makes the 3-way `.af-hashes` merge lose meaning and creates churn.

## Root Cause (verified)

- **No `.gitattributes`** in the AAIG repo + `core.autocrlf=true` ⇒ the Windows
  working tree is CRLF (`w/crlf`) while the git blob is LF (`i/lf`).
- Both tools' **payload write paths are already byte-exact** (`Copy-Item` /
  `WriteAllText` UTF8-no-BOM / `_write_bytes(resolved_source_bytes)` /
  `cp`+`printf`). The divergence is **input**: `deploy.ps1`/editable-MCP read the
  CRLF working tree; a wheel payload built from an LF state writes LF.
- `.gitattributes` alone does **not** fix an existing Windows working tree (git
  treats it as clean via the clean filter); a physical re-checkout would be
  required (destructive, human-gated).

## Design Decision (chosen: Hybrid)

Canonical deployed byte representation = **UTF-8 without BOM, LF line endings**.

1. **`.gitattributes`** (`* text=auto eol=lf` + binary safety) — deterministic
   blobs, LF fresh clones, correct `.sh` shims.
2. **Defensive LF-canonicalization at hash + write in both tools** — strip BOM,
   `\r\n`/`\r` → `\n`, resolve tier tokens (always LF), UTF-8 no BOM. No-op when
   the source is already LF (correct clone); safety net for a CRLF working tree
   or a stale wheel. Hash basis == write bytes, identical across tools.
3. **Migration:** one re-deploy (`deploy.ps1 -Force` / MCP `apply`) normalizes
   non-customizable files to LF (self-heals as UPDATE), then
   `-UpdateHashes` / `update_hashes` re-baselines. Customizable files keep their
   EOL until an intentional edit.

Alternative rejected: strict "preserve source" (Option A) — fragile because
existing Windows working trees stay CRLF on disk without a destructive
re-checkout.

Provenance: framework files are exempt from in-code markers (carve-out), so no
markers are added; git history + CHANGELOG trace the change.

## Subtasks

- [x] AC1: `resolved_source_bytes` (MCP) canonicalizes CRLF/CR→LF + strips BOM;
      LF input is a no-op; tier + non-tier covered. `source_hash_resolved` is
      EOL-independent.
- [x] AC2: `deploy.ps1` `Get-CanonicalBytes`/`Get-BytesHashUpper`;
      `Publish-SingleFile`, `Get-SourceHashResolved`, UpdateHashes/Diff, and
      `.af-hashes`/`.af-version` writes all use canonical LF/UTF-8-no-BOM bytes.
- [x] AC3: `deploy.sh` strips CR on the copy + hash path (canonical LF).
- [x] AC4: `.gitattributes` added at AAIG root.
- [x] AC5: Cross-tool parity: after `deploy.ps1 -Force`, MCP `dry_run` = 0
      UPDATE/CONFLICT; representative byte-sample identical SHA-256.
- [x] AC6: VERSION minor bump + CHANGELOG (feature + design + migration).

## Tests

- pytest (mcp-deploy): CRLF→LF, BOM strip, LF no-op, tier-from-CRLF,
  apply-writes-LF-no-BOM, hash EOL-independence, binary passthrough.
- `scripts/test-eol-parity.ps1`: deploy.ps1 → MCP dry_run = 0 changes.
