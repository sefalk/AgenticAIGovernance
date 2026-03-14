---
category: testing
applies_to: [web, cli, library]
complexity: foundational
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [unit_testing, e2e_testing]
---
# Snapshot Testing

## Purpose

Snapshot testing captures the output of a function, component, or system at a known-good state and compares future outputs against this baseline. It excels at detecting unintended changes in large, structured outputs that are tedious to assert manually. Invoke this skill when the project produces complex outputs (rendered UIs, serialized data, generated configs) where change detection matters more than specific value assertions.

## Principles

- **Change detection, not correctness verification:** Snapshots detect *changes*, not *bugs*. A new snapshot is accepted by a developer who verifies the change is intentional.
- **Human review is mandatory:** Every snapshot update must be manually reviewed. Auto-accepting snapshot updates defeats the purpose.
- **Verifiability (AAIG L1):** Snapshot diffs are reviewable artifacts. Snapshot updates in PRs must be reviewed like code changes.
- **Efficiency (AAIG L1):** Snapshots reduce boilerplate assertions for complex outputs but add a maintenance burden. Use judiciously.

## Techniques & Patterns

### When to Use Snapshots

| Good Fit | Bad Fit |
|----------|---------|
| UI component rendered HTML/JSX | Timestamps, random IDs, or other non-deterministic output |
| Serialized data structures (JSON, XML) | Frequently changing outputs (snapshots become noise) |
| Generated code / config | Simple values with clear expected outputs (use assertions) |
| CLI output | Binary data |
| API response schemas | Performance-sensitive tests (snapshot I/O adds overhead) |
| Error messages and diagnostics | Anything requiring semantic understanding, not textual match |

### Inline vs. File Snapshots

| Type | Storage | Best For |
|------|---------|----------|
| **File snapshot** | Stored in `__snapshots__/` directory alongside tests | Large outputs (rendered HTML, JSON blobs) |
| **Inline snapshot** | Stored directly in the test file | Small outputs where seeing the snapshot in context aids readability |

### Framework Support

#### JavaScript / TypeScript
```javascript
// Jest / Vitest
test('renders user card', () => {
  const tree = render(<UserCard name="Alice" role="Admin" />);
  expect(tree).toMatchSnapshot();        // file snapshot
  expect(tree).toMatchInlineSnapshot(`   // inline snapshot
    <div class="user-card">
      <h2>Alice</h2>
      <span>Admin</span>
    </div>
  `);
});

// Update snapshots: npx jest --updateSnapshot  (or npx vitest -u)
```

#### Python
```python
# pytest-snapshot or syrupy (recommended)
# syrupy produces cleaner diffs and supports multiple serializers

def test_api_response(snapshot):
    result = generate_report(test_data)
    assert result == snapshot  # auto-creates/compares .ambr snapshot file

# Update snapshots: pytest --snapshot-update
```

#### Java
```java
// approval-tests (ApprovalTests.Java)
@Test
void testReportGeneration() {
    String report = generator.generateReport(testData);
    Approvals.verify(report);  // compares against .approved.txt
}

// To approve: rename .received.txt to .approved.txt
```

#### Rust
```rust
// insta crate (recommended)
#[test]
fn test_config_serialization() {
    let config = generate_config();
    insta::assert_snapshot!(config);
}

// Review: cargo insta review (interactive TUI)
```

#### Go
```go
// cupaloy
func TestOutput(t *testing.T) {
    result := generateOutput()
    cupaloy.SnapshotT(t, result)
}

// Update: UPDATE_SNAPSHOTS=true go test ./...
```

### Serialization Strategies

The snapshot serializer determines readability and diff quality.

| Strategy | Pros | Cons |
|----------|------|------|
| **Pretty-printed JSON** | Highly readable diffs, universal format | Verbose for deeply nested structures |
| **Custom string format** | Optimized for domain output | Must maintain custom serializer |
| **YAML** | Readable, compact | Whitespace-sensitive, can be surprising |
| **Raw HTML** | Captures exact rendering | Noisy diffs on style changes |
| **Shallow rendering** | Component structure without children | May miss integration issues |

**Best practice:** Use a deterministic serializer. Sort object keys, format consistently, omit non-deterministic fields.

### Handling Non-Deterministic Output

Snapshots break when output contains timestamps, UUIDs, auto-incremented IDs, or random values.

**Solutions:**
1. **Redact:** Replace non-deterministic values with placeholders before snapshotting.
   ```javascript
   expect(sanitize(output)).toMatchSnapshot();
   // where sanitize replaces UUIDs with "[UUID]", timestamps with "[TIMESTAMP]"
   ```
2. **Property matchers (Jest):** `expect(output).toMatchSnapshot({ id: expect.any(String), createdAt: expect.any(Date) })`.
3. **Snapshot serializers:** Custom serializers that normalize before comparison.
4. **Freeze time/randomness:** In tests, pin `Date.now()`, seed random generators.

### Review Workflow

```
1. Developer makes a code change.
2. Snapshot tests fail (expected).
3. Developer reviews the snapshot diff:
   a. If the change is intentional --> update snapshots, commit new snapshots.
   b. If the change is unintended --> fix the code, re-run.
4. PR reviewer verifies snapshot diffs in the PR.
```

**CI enforcement:** Fail CI if snapshot files are outdated. Never auto-update snapshots in CI.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Snapshots up to date** | 100% | CI must fail if any snapshot is outdated. |
| **Snapshot review in PR** | All diffs reviewed | Snapshot file changes must be explicitly reviewed, not rubber-stamped. |
| **No non-deterministic snapshots** | 0 | Flaky snapshots must be fixed (redact, freeze, or pin). |
| **Snapshot count justified** | < 2x test count | If snapshot files vastly outnumber tests, snapshots may be overused. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Blind snapshot updates** | Running `--updateSnapshot` without reviewing diffs. Bugs auto-accepted. | Always review diffs. Use interactive review tools (`cargo insta review`). |
| **Snapshot everything** | Thousands of snapshot files, huge diffs, reviewer fatigue. | Snapshot only complex outputs. Use assertions for simple values. |
| **Non-deterministic snapshots** | Timestamps/UUIDs cause constant diff noise. | Redact, freeze, or mock non-deterministic values. |
| **Huge snapshots** | Snapshots of entire page HTML (10,000+ lines). Unusable diffs. | Snapshot components, not pages. Use shallow rendering. |
| **Snapshots as the only tests** | Snapshots detect change but don't verify correctness. | Combine with unit tests that assert specific behaviors. |


## See Also

- [Unit Testing](../testing/unit_testing.md)
- [E2E Testing](../testing/e2e_testing.md)

## References

- Jest snapshot testing: https://jestjs.io/docs/snapshot-testing
- Vitest snapshots: https://vitest.dev/guide/snapshot
- syrupy (Python): https://github.com/toptal/syrupy
- insta (Rust): https://insta.rs/
- ApprovalTests: https://approvaltests.com/
