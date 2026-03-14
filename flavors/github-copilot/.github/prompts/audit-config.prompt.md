---
name: audit-config
description: 'Detect drift between Agent Framework config files and the actual project state — find stale module classifications, outdated architecture maps, and threshold mismatches.'
argument-hint: 'Optional: focus area (e.g., "architecture only", "thresholds")'
tools:
  - search
  - read
---

# Configuration Drift Audit

Re-run the discovery logic from `/onboard-project` but instead of writing
files, **diff** the current AF config against the discovered state. This is
**advisory only** — report drift, never auto-fix (the human may have
intentionally customised values).

## Step 1: Read Current Configuration

Read these AF config files and extract current settings:

- `.github/copilot-instructions.md` → project name, tech stack, repo URL,
  repository structure, coding standards, module lists
- `.github/instructions/architecture.instructions.md` → architecture layers,
  module classifications (which files are domain core, ports, adapters, etc.)
- `VERSION` → current AF version (if present)

## Step 2: Discover Actual Project State

Scan the project using the same logic as `/onboard-project`:

1. **Metadata:** Read `pyproject.toml`, `setup.py`, `package.json`, `README.md`
   for project name, version, dependencies
2. **Structure:** List all source directories and files
3. **Module classification:** For each Python/JS/TS module, analyse imports:
   - No I/O imports (no `spark`, `requests`, `os.path`, DB) → domain core
   - Abstract interfaces / Protocol classes → ports
   - I/O-dependent implementations → adapters
   - Wires components together → orchestrators
   - Mixed → flag for review
4. **Tools:** Check for configured formatter, linter, test runner, type checker
5. **Dependencies:** Read current dependency list

## Step 3: Compute Drift

Compare discovered state against current config. Check for:

### Architecture Drift
- **New modules** not listed in `architecture.instructions.md`
- **Removed modules** still listed in config but deleted from project
- **Layer changes** — module imports changed (e.g., was domain core, now
  imports `requests` → should be adapter)
- **New directories** not in the repository structure section

### Threshold Drift
- **Coverage actuals vs targets** — if coverage data is available (e.g.,
  from a recent pytest-cov run), compare actual coverage per module type
  against MANIFEST § 5 thresholds
- **Complexity actuals** — if radon data is available, compare against
  MANIFEST § 5 max complexity per module type

### Dependency Drift
- **New dependencies** added since onboarding but not mentioned in config
- **Removed dependencies** still listed in config
- **Version mismatches** between config expectations and lock files

### Convention Drift
- **README structure** — does the documented structure still match reality?
- **Naming convention violations** — any new files/modules that violate the
  stated conventions?

## Step 4: Version Comparison (if applicable)

If the project has a `VERSION` file:

1. Compare against the latest AF `CHANGELOG.md`
2. If there's a version gap, list what changed between versions
3. Flag any breaking changes that may require migration

## Output Format

```markdown
## 🔍 Configuration Drift Report

### Summary
- **Config files checked:** {count}
- **Drift items found:** {count}
- **Action needed:** {count items requiring human decision}

### Architecture Drift
| Module | Config Says | Actual State | Action |
|---|---|---|---|
| `{path}` | domain core | imports `requests` (adapter) | Reclassify |
| `{path}` | (not listed) | new module, pure logic | Add to architecture map |

### Threshold Drift
| Metric | Target | Actual | Status |
|---|---|---|---|
| Domain core coverage | ≥ 90% | 87% | ⚠️ Below target |

### Dependency Drift
| Package | Config | Actual | Action |
|---|---|---|---|
| `{name}` | not listed | in pyproject.toml | Add to dependencies list |

### Convention Drift
- {item}

### Recommendations
1. {Prioritised action item}
2. {Next action}

### No Drift Detected
{If all clean: "✅ Configuration is current — no drift detected."}
```

If the user specified a focus area, run only the relevant steps.
