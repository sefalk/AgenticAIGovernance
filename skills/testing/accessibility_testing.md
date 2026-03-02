---
category: testing
applies_to: [web, mobile]
complexity: intermediate
maturity: reviewed
version: "1.0"
last_reviewed: 2026-02-26
related: [e2e_testing, static_analysis, code_review, frontend_architecture, mobile_development]
---
# Accessibility Testing

## Purpose

Accessibility testing ensures that applications are usable by people with disabilities, including visual, auditory, motor, and cognitive impairments. It verifies compliance with WCAG (Web Content Accessibility Guidelines) and relevant legislation (ADA, EAA, Section 508). Invoke this skill when building web or mobile UIs, defining Level-3 testing workflows, or setting up Level-4 accessibility standards.

## Principles

- **Verifiability (AAIG L1):** Accessibility claims must be backed by automated tests and manual audits. "We think it's accessible" is not sufficient.
- **Continuous Improvement (AAIG L1):** Accessibility is not a one-time audit. It must be tested continuously as the UI evolves.
- **Inclusive design:** Accessibility is not an afterthought or a compliance checkbox. It's a design principle that improves usability for everyone.
- **POUR principles:** Content must be Perceivable, Operable, Understandable, and Robust (WCAG foundation).

## Techniques & Patterns

### WCAG Compliance Levels

| Level | Meaning | Target |
|-------|---------|--------|
| **A** | Minimum accessibility | Legal minimum in many jurisdictions |
| **AA** | Standard target | Industry standard. Default target for most projects. |
| **AAA** | Enhanced accessibility | Specialized apps (government, education) |

### Testing Layers

```
Layer 1: Automated scanning     (catches ~30-40% of issues)
Layer 2: Semi-automated tools   (guided manual checks, +20%)
Layer 3: Manual expert audit    (keyboard, screen reader, +30%)
Layer 4: User testing           (people with disabilities, +10%)
```

**Key insight:** No single layer catches everything. Automated tools find only structural issues (missing alt text, low contrast). Semantic and interaction issues require human testing.

### Automated Testing Tools

| Tool | Type | Integration | Notes |
|------|------|-------------|-------|
| **axe-core** | Engine | CI, Playwright, Cypress, Jest | Industry standard. Low false-positive rate. |
| **Lighthouse** | Browser audit | CI (via CLI), Chrome DevTools | Quick audits. Limited depth. |
| **pa11y** | CLI scanner | CI pipelines | Headless, scriptable. |
| **WAVE** | Browser extension | Manual testing | Visual feedback overlay. Good for developers. |
| **Tenon** | API service | CI, custom integrations | Detailed reports, API-first. |

### Playwright + axe Integration

```javascript
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

test('homepage has no a11y violations', async ({ page }) => {
  await page.goto('/');
  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa'])
    .analyze();
  expect(results.violations).toEqual([]);
});

test('form has no a11y violations', async ({ page }) => {
  await page.goto('/contact');
  await page.fill('#name', 'Test User');
  // Test accessibility AFTER interaction
  const results = await new AxeBuilder({ page })
    .include('#contact-form')
    .analyze();
  expect(results.violations).toEqual([]);
});
```

### Manual Testing Checklist

**Keyboard navigation:**
- [ ] All interactive elements focusable via Tab
- [ ] Focus order follows visual layout
- [ ] Focus indicator visible (outline, highlight)
- [ ] No keyboard traps (can always Tab away)
- [ ] Custom widgets support expected keys (Enter, Space, Arrow, Escape)

**Screen reader:**
- [ ] All images have meaningful alt text (or `alt=""` for decorative)
- [ ] Form inputs have associated labels
- [ ] Headings form a logical hierarchy (h1 > h2 > h3)
- [ ] Dynamic content updates announced (ARIA live regions)
- [ ] Custom components have correct ARIA roles and states

**Visual:**
- [ ] Color contrast >= 4.5:1 (normal text), >= 3:1 (large text)
- [ ] Information not conveyed by color alone
- [ ] Text resizable to 200% without loss of content
- [ ] Responsive layout works at 320px width

**Screen Readers for Testing:**
| OS | Screen Reader | Notes |
|----|---------------|-------|
| Windows | NVDA (free) | Most popular free reader |
| Windows | JAWS | Enterprise standard |
| macOS/iOS | VoiceOver (built-in) | Toggle with Cmd+F5 |
| Android | TalkBack (built-in) | In accessibility settings |

### Common ARIA Patterns

| Widget | Role | Key Attributes |
|--------|------|---------------|
| **Modal dialog** | `role="dialog"` | `aria-modal="true"`, `aria-labelledby` |
| **Tab panel** | `role="tablist"`, `role="tab"`, `role="tabpanel"` | `aria-selected`, `aria-controls` |
| **Accordion** | `role="region"`, button trigger | `aria-expanded`, `aria-controls` |
| **Dropdown menu** | `role="menu"`, `role="menuitem"` | `aria-haspopup`, `aria-expanded` |
| **Toast/notification** | `role="alert"` or `role="status"` | `aria-live="polite"` or `"assertive"` |

**First rule of ARIA:** Don't use ARIA if a native HTML element exists. `<button>` is better than `<div role="button">`.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **axe-core CI scan** | Zero violations (wcag2aa) | Run on every PR. Block merge on violations. |
| **Keyboard navigation** | All flows passable | Manual quarterly audit + automated focus tests |
| **Color contrast** | WCAG AA (4.5:1 / 3:1) | Enforced via design system tokens |
| **Screen reader audit** | Quarterly | Test with NVDA (Windows) and VoiceOver (macOS) |
| **Alt text coverage** | 100% of meaningful images | Automated check for `img` without `alt` |
| **WCAG compliance** | Level AA | Target for all user-facing applications |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Accessibility as afterthought** | "We'll add a11y before launch." By then, too many issues to fix. | Integrate a11y from sprint 1. axe-core in CI from day one. |
| **ARIA overuse** | Piling ARIA attributes on everything. More ARIA != more accessible. | Use native HTML first. ARIA only for custom widgets. |
| **Click-only interactions** | Custom components only respond to mouse clicks. Keyboard users locked out. | All interactive elements must respond to keyboard (Enter, Space). |
| **Relying on automated tools alone** | "axe says zero violations, so we're accessible." False confidence. | Automated catches ~30%. Manual keyboard + screen reader testing required. |
| **Placeholder-only labels** | Using placeholder text as the only label for form inputs. Disappears on focus. | Use visible `<label>` elements. Placeholders are supplementary hints. |

## See Also

- [E2E Testing](../testing/e2e_testing.md)
- [Static Analysis](../code_quality/static_analysis.md)
- [Code Review](../code_quality/code_review.md)

## References

- WCAG 2.2: https://www.w3.org/TR/WCAG22/
- axe-core: https://github.com/dequelabs/axe-core
- WAI-ARIA Authoring Practices: https://www.w3.org/WAI/ARIA/apg/
- European Accessibility Act: https://ec.europa.eu/social/main.jsp?catId=1202
