---
category: testing
applies_to: [web, mobile]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [integration_testing, snapshot_testing, performance_testing, accessibility_testing, frontend_architecture, mobile_development]
---
# End-to-End Testing

## Purpose

End-to-end (E2E) testing validates the entire application from the user's perspective, exercising the full stack -- UI, backend, database, and external services -- in a production-like environment. E2E tests answer the question: "Does the system work as a whole for the end user?" Invoke this skill when the project requires automated user-journey validation, visual regression testing, or full-stack smoke tests.

## Principles

- **User-centric:** E2E tests simulate real user interactions. They click buttons, fill forms, navigate pages, and assert on what the user sees.
- **Minimal count, maximum coverage:** E2E tests are slow and brittle relative to unit/integration tests. Follow the testing pyramid: few E2E tests covering critical journeys, many unit tests covering details.
- **Determinism:** E2E tests must be deterministic despite testing a complex system. Achieve this through seeded data, controlled environments, and stable selectors.
- **Fail-Safe (AAIG L1):** A failing E2E test in CI should block deployment. False positives (flaky tests) must be fixed immediately, not skipped.

## Techniques & Patterns

### Framework Selection

| Framework | Best For | Key Strengths |
|-----------|----------|---------------|
| **Playwright** | Modern web apps (recommended default) | Multi-browser, auto-wait, codegen, trace viewer, API testing built-in |
| **Cypress** | Single-page apps, component testing | Developer-friendly, time-travel debugging, real-time reloading |
| **Selenium** | Legacy apps, multi-language teams | Broadest browser/language support, WebDriver standard |
| **Puppeteer** | Chrome-specific automation, PDF generation | Direct Chrome DevTools Protocol access |
| **Detox** | React Native mobile apps | Gray-box testing, synchronization with native navigation |
| **Appium** | Cross-platform mobile (iOS + Android) | WebDriver protocol for mobile, supports native and hybrid apps |

**Default recommendation:** Playwright for web applications. It has the best auto-waiting, multi-browser support, and debugging toolchain.

### Page Object Model (POM)

Encapsulate page structure and interactions in reusable classes. Tests read like user stories, not DOM selectors.

```javascript
// page-objects/login-page.js
class LoginPage {
  constructor(page) {
    this.page = page;
    this.emailInput = page.getByLabel('Email');
    this.passwordInput = page.getByLabel('Password');
    this.submitButton = page.getByRole('button', { name: 'Sign in' });
    this.errorMessage = page.getByRole('alert');
  }

  async login(email, password) {
    await this.emailInput.fill(email);
    await this.passwordInput.fill(password);
    await this.submitButton.click();
  }
}

// tests/login.spec.js
test('successful login redirects to dashboard', async ({ page }) => {
  const loginPage = new LoginPage(page);
  await page.goto('/login');
  await loginPage.login('user@test.com', 'password123');
  await expect(page).toHaveURL('/dashboard');
});
```

**Rules:**
- One Page Object per page/component.
- Page Objects expose *behaviors* (methods), not *elements* (locators).
- Assertions live in tests, not in Page Objects.

### Selector Strategy

Use **user-facing selectors** (what the user sees) over implementation details (CSS classes, XPaths):

| Priority | Selector Type | Example | Stability |
|----------|--------------|---------|-----------|
| 1 (best) | Role + name | `getByRole('button', { name: 'Submit' })` | Very high |
| 2 | Label | `getByLabel('Email address')` | High |
| 3 | Text | `getByText('Welcome back')` | High |
| 4 | Test ID | `getByTestId('checkout-form')` | High |
| 5 | CSS class | `.btn-primary` | Low (breaks on refactor) |
| 6 (worst) | XPath | `//div[3]/form/input[2]` | Very low |

### Visual Regression Testing

Capture screenshots and compare against baselines to detect unintended visual changes.

**Tools:**
- Playwright: Built-in `expect(page).toHaveScreenshot()` with pixel-level comparison.
- Percy (BrowserStack): Cloud-based, cross-browser visual testing.
- Chromatic: Purpose-built for Storybook component visual testing.
- BackstopJS: Open-source, Docker-based visual regression.

**Best practices:**
- Use threshold-based comparison (allow minor anti-aliasing differences).
- Run visual tests in a single, controlled browser version (avoid cross-browser pixel diffs).
- Store baselines in version control. Review visual diffs in PRs.

### Test Data Management

- **Seed before suite:** Create test users, products, etc. before the test suite runs.
- **API backdoor:** Use API calls (not UI) to set up test state -- much faster and more reliable.
- **Isolated environments:** Each test run gets a fresh environment (or namespace-isolated data).
- **Clean up after:** Delete test-created data in `afterAll` / teardown hooks.

### CI/CD Integration

```yaml
# Example: Playwright in GitHub Actions
e2e-tests:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - run: npm ci
    - run: npx playwright install --with-deps
    - run: npx playwright test
    - uses: actions/upload-artifact@v4
      if: failure()
      with:
        name: playwright-report
        path: playwright-report/
```

**Key practices:**
- Run E2E tests in CI on every PR (at minimum, critical path tests).
- Archive test reports, screenshots, and traces on failure.
- Use parallelism (Playwright sharding) to keep suite time under budget.
- Set a hard timeout per test (default: 30s) to catch hangs.

### Handling Flakiness

Flaky E2E tests destroy confidence. Address systematically:

| Cause | Fix |
|-------|-----|
| Race conditions / timing | Use auto-waiting (Playwright does this), not `setTimeout`. |
| Shared test state | Isolate test data per test. Use unique identifiers. |
| Animation / transition | Disable CSS animations in test mode, or wait for animation completion. |
| Third-party dependencies | Mock external APIs at the network level (`page.route()` in Playwright). |
| Viewport inconsistencies | Set a fixed viewport size in test config. |

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Critical path coverage** | 100% of critical user journeys | Login, signup, purchase, data CRUD -- all must have E2E tests. |
| **Flaky test rate** | 0% | Any flaky test is a P1 bug. Quarantine and fix within one sprint. |
| **Suite execution time** | < 10 min (with parallelism) | Use sharding and prioritization to stay under budget. |
| **Visual regression review** | All diffs reviewed | Every visual diff must be explicitly approved or rejected. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Testing everything via E2E** | Slow, brittle, expensive. Testing pyramid inverted. | Move logic validation to unit tests. E2E tests only critical journeys. |
| **Unstable selectors** | Tests break on every CSS refactor. | Use role/label/testid selectors, never CSS classes or XPaths. |
| **setUp via UI** | Creating test data by clicking through forms. Slow and fragile. | Use API calls or database seeding for setup. |
| **No failure artifacts** | Test fails in CI but no screenshot/trace to diagnose. | Always capture screenshots, videos, and traces on failure. |
| **Ignoring flaky tests** | Marking flaky tests as skip/pending permanently. | Fix root cause. Quarantine temporarily with a ticket and deadline. |


## See Also

- [Integration Testing](../testing/integration_testing.md)
- [Snapshot Testing](../testing/snapshot_testing.md)
- [Performance Testing](../testing/performance_testing.md)

## References

- Playwright documentation: https://playwright.dev/docs/intro
- Cypress documentation: https://docs.cypress.io/
- Martin Fowler, ["TestPyramid"](https://martinfowler.com/bliki/TestPyramid.html) -- the foundational testing strategy.
- Google Testing Blog, ["Just Say No to More End-to-End Tests"](https://testing.googleblog.com/2015/04/just-say-no-to-more-end-to-end-tests.html) -- pragmatic E2E test scoping.
