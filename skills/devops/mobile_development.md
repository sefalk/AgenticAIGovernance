---
title: Mobile Development
description: Architecture, build pipelines, and distribution for iOS and Android
applies_to: [mobile]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [ci_cd, e2e_testing, accessibility_testing, frontend_architecture]
---
# Mobile Development

## Purpose
To manage the unique lifecycle of mobile applications (iOS/Android), including native integration, complex build pipelines, code signing, and app store distribution, overcoming the challenges of fragmented devices and delayed update cycles.

## Principles
1. **Offline First:** Mobile devices frequently lose connectivity. The application must handle offline states gracefully and synchronize when connectivity returns. *(AAIG L1: Fail-Safe)*
2. **Battery and Bandwidth Frugality:** Minimize heavy background processing, polling, and large payload downloads. Utilize push notifications to wake the app instead of polling.
3. **Automated Distribution:** Humans should not manually build `.ipa` or `.apk`/`.aab` files from their local machines. All builds and code signing must happen in CI. *(AAIG L1: Verifiability & Quality Assurance)*
4. **No Forced Updates (Usually):** Users control when they update. The backend API must gracefully support older versions of the mobile client indefinitely or employ a strict deprecation window.

## Techniques & Patterns

### 1. Build and Release Pipelines (CI/CD)
*   **Fastlane:** Use Fastlane (or similar tools) to automate taking screenshots, managing provisioning profiles, incrementing build numbers, and submitting to the App Store / Google Play.
*   **Code Signing Management:** Store provisioning profiles and certificates securely. Use tools like `match` to sync certificates across the CI environment and developer machines without manual key distribution.
*   **Release Tracks:** Utilize Alpha/Beta testing tracks (TestFlight, Google Play Console internal testing) before pushing to production. Phased (staged) rollouts are mandatory for large user bases.

### 2. App Architecture
*   **State Management:** Separate UI from business logic (e.g., MVVM, BLoC, Redux). Keep views as dumb as possible to facilitate unit testing of the view models.
*   **Deep Linking:** Implement Universal Links (iOS) and App Links (Android) to route users from web URLs directly to specific screens within the app. Ensure fallback behavior if the app is not installed.

### 3. Device Testing
*   **Device Farms:** Emulators are insufficient for catching hardware-specific bugs (camera, sensors, vendor-specific Android forks). Run automated E2E UI tests on real devices using AWS Device Farm, Firebase Test Lab, or similar.
*   **Crash Analytics:** Integrate a robust crash reporting mechanism (e.g., Sentry, Firebase Crashlytics). Mobile app crashes offer no console output to the user; telemetry is the only visibility.

### 4. Over-The-Air (OTA) Updates
*   **JavaScript/Bundle Updates:** If using React Native, Expo, or Ionic, utilize OTA update services (e.g., CodePush, Expo Updates) to push hotfixes for JavaScript logic directly to users, bypassing the multi-day app store review process. Note: Native module changes still require store review.

## Quality Gates
*   **Automated UI Tests:** Critical flows (login, checkout) pass an Appium, Maestro, or Detox suite against at least one iOS and one Android emulator.
*   **Linting/Formatting:** SwiftLint (iOS), ktlint (Android), or ESLint/Prettier (React Native) enforce rigid style rules automatically.
*   **Asset Size Warning:** The pipeline warns if the final app binary size increases by more than 5% compared to the previous release, preventing asset bloat.

## Anti-Patterns

| Anti-Pattern | Why it's harmful | Better Approach |
| :--- | :--- | :--- |
| **Assuming Fast Network** | Developing only on strong Wi-Fi hides timeout issues and blank screens that users on 3G will face. | Use network link conditioners during testing to simulate poor/flaky connections. |
| **Coupling API to App Version 1:1** | Changing an API endpoint response format immediately breaks all users who haven't updated the app. | Version API endpoints (`/v1/`, `/v2/`) or use GraphQL to gracefully handle older clients. |
| **Manual Provisioning** | Managing iOS certificates manually results in "it works on my machine" and sudden build failures when keys expire. | Automate certificate management via Fastlane Match or cloud CI secrets. |
| **Blocking Main Thread** | Heavy JSON parsing or database queries on the UI thread causes "jank" and frozen screens. | Offload all I/O and heavy computation to background threads/web workers. |

## See Also
*   [Frontend Architecture](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/architecture/frontend_architecture.md)
*   [CI/CD](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/devops/ci_cd.md)

## References
*   [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
*   [Google Material Design](https://m3.material.io/)
*   [Fastlane Documentation](https://docs.fastlane.tools/)
