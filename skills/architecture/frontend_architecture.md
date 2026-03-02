---
title: Frontend Architecture
description: Component design, state management, and structure for complex user interfaces
applies_to: [web, mobile]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [api_design, e2e_testing, accessibility_testing, design_patterns, mobile_development]
---
# Frontend Architecture

## Purpose
To structure complex client-side applications so they remain maintainable, performant, and testable as the codebase and team scale, preventing "prop drilling," tangled state, and brittle UI.

## Principles
1. **Component Isolation:** UI components should do one thing well. Separate presentation (how it looks) from business logic (how it works). *(AAIG L1: Separation of Concern)*
2. **Predictable State:** The UI should be a deterministic function of the application state. State mutations must be intentional, traceable, and unidirectional.
3. **Progressive Enhancement:** Core content and functionality should be accessible baseline, with advanced features enhancing the experience where supported.
4. **Performance by Default:** Optimize for Core Web Vitals (LCP, FID/INP, CLS). Avoid shipping unnecessary JavaScript payload.

## Techniques & Patterns

### 1. Component Design
*   **Container vs. Presentational (Smart vs. Dumb):**
    *   *Presentational:* Pure UI components. Take props, emit events callback. Have no awareness of the global store or network. Highly reusable and testable.
    *   *Container:* Logic components. Fetch data, read from global state, dispatch actions, and pass data down to Presentational components.
*   **Composition over Inheritance:** Build complex UIs by composing smaller, focused components (e.g., using `children` or slots) rather than creating massive configuration objects.

### 2. State Management Strategy
*   **Local State:** For UI-only state (is a dropdown open, current tab) confined to a single component or its immediate children. (e.g., `useState`).
*   **Server State:** For data fetched from an API. Use specialized libraries (e.g., React Query, SWR, Apollo) to handle caching, deduplication, background fetching, and loading/error states. Do not put server state in global UI stores like Redux if avoidable.
*   **Global Client State:** For app-wide UI state (theme, current user preferences, global modal visibility). Use lightweight context or libraries (e.g., Zustand, Redux Toolkit, Vuex) sparingly.

### 3. Styling Architecture
*   **Scoping:** Prevent CSS global namespace collisions. Pick a strategy and enforce it: CSS Modules, CSS-in-JS (Styled Components), or Utility-first (Tailwind CSS).
*   **Design Tokens:** Extract colors, spacing, typography, and breakpoints into a single source of truth (variables or theme object) to maintain visual consistency.

### 4. Rendering Patterns
*   **Client-Side Rendering (CSR):** Fast interactions after initial load, but slower time-to-first-byte and poor SEO. Best for highly interactive dashboard apps.
*   **Server-Side Rendering (SSR) / Static Site Generation (SSG):** Pre-render HTML for fast paint and SEO (e.g., Next.js, Nuxt/Astro). Use SSG for content that changes rarely, SSR for dynamic content.

## Quality Gates
*   **Bundle Size:** CI fails if the main JavaScript bundle exceeds the configured budget (e.g., 200KB minified/gzipped).
*   **Accessibility (a11y):** Automated Axe-core scans pass with zero critical or serious WCAG violations.
*   **Linting:** Strict linting rules implemented for component structure and hooks (e.g., `eslint-plugin-react-hooks`).

## Anti-Patterns

| Anti-Pattern | Why it's harmful | Better Approach |
| :--- | :--- | :--- |
| **Prop Drilling** | Passing props down 5 levels of components tightly couples the intermediate components to data they don't care about. | Use composition, Context, or a lightweight global store. |
| **God Components** | A 1000-line component handling fetching, local state, complex rendering, and side effects is untestable. | Split into a Container for logic and Presentational components for UI. |
| **Duplicating Server State** | Fetching data and manually copying it into a Redux store leads to stale data and synchronized bugs. | Use a server-state caching library (React Query/SWR) directly. |
| **Tying UI to APIs** | The UI component directly parses deeply nested API JSON structures, breaking when the backend changes. | Map API responses to UI-friendly domain models at the network boundary. |

## See Also
*   [E2E Testing](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/testing/e2e_testing.md)
*   [Accessibility Testing](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/testing/accessibility_testing.md)

## References
*   [Thinking in React](https://react.dev/learn/thinking-in-react)
*   [Patterns.dev - Modern Web App Patterns](https://www.patterns.dev/)
