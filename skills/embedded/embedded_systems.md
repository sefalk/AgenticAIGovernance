---
title: Embedded Systems Development
description: Patterns for resource-constrained, real-time, or deeply embedded devices
applies_to: [embedded, iot, c, cpp, rust]
complexity: advanced
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [system_design, event_driven_architecture, ci_cd, secure_coding]
---
# Embedded Systems Development

## Purpose
To ensure firmware and embedded software are reliable, deterministic, secure, and maintainable, despite severe resource constraints (CPU, RAM, flash) and lack of direct human-in-the-loop recovery mechanisms.

## Principles
1. **Determinism over Flexibility:** Execution time and memory allocation must be predictable. Prioritize static analysis and worst-case execution time (WCET) guarantees over dynamic behaviors.
2. **Resource Frugality:** Treat CPU cycles, RAM, and power as scarce commodities. Optimize for the specific constraint of the target hardware.
3. **Hardware Abstraction:** Business logic must not directly couple to hardware registers. Use Hardware Abstraction Layers (HAL) or Board Support Packages (BSP) to enable testing off-target. *(AAIG L1: Separation of Concern)*
4. **Safe Failures:** When an unrecoverable error occurs, the system must enter a defined safe state (e.g., stopping motors, disabling heaters) and trigger a watchdog reset if appropriate. *(AAIG L1: Fail-Safe)*

## Techniques & Patterns

### 1. Memory Management
*   **No Dynamic Allocation:** Avoid `malloc`/`free` or `new`/`delete` after initialization. Pre-allocate all required memory statically to prevent fragmentation and Out-Of-Memory (OOM) crashes in long-running systems.
*   **Memory Pools:** If dynamic-like behavior is needed, use fixed-size memory block pools rather than variable-sized heap allocation.
*   **Stack Depth Analysis:** Use compiler tools to calculate maximum stack depth and ensure sufficient stack space to prevent overflows.

### 2. Concurrency & RTOS
*   **Bare Metal vs. RTOS:** Use an RTOS (e.g., FreeRTOS, Zephyr) when managing multiple complex, asynchronous tasks. Stick to Bare Metal (super-loop + interrupts) for very simple, deterministic control loops.
*   **Priority Inversion:** Prevent RTOS priority inversion using Priority Inheritance Protocols or Priority Ceiling Protocols on shared resources (mutexes).
*   **Interrupt Service Routines (ISRs):** Keep ISRs extremely short. Acknowledge the interrupt, set a flag or post to a queue, and defer the actual processing to a lower-priority background task.

### 3. Updates & Observability
*   **Over-The-Air (OTA) Updates:** Implement robust A/B (dual-bank) firmware updates. The system must automatically roll back to the known-good bank if the new firmware fails to boot or pass self-tests.
*   **Post-Mortem Debugging:** Save crash dumps (registers, stack snippet, error code) to persistent non-volatile memory (e.g., EEPROM, Flash) before a watchdog reset, so they can be retrieved and analyzed upon reboot.

## Quality Gates
*   **Compiler Warnings:** Build with `-Wall -Wextra -Werror` (or equivalent). Zero warnings allowed.
*   **Static Analysis:** Passes MISRA C / C++ or CERT C compliance checks (where applicable to the project scope).
*   **Off-Target Testing:** Core business logic achieves >80% coverage in off-target (e.g., x86) unit tests, mocking the HAL.
*   **Stack Analysis:** Static analysis proves maximum stack usage is <80% of allocated stack size.

## Anti-Patterns

| Anti-Pattern | Why it's harmful | Better Approach |
| :--- | :--- | :--- |
| **Blocking in ISR** | `delay()` or heavy computation inside an interrupt blocks all lower-priority tasks and other interrupts, ruining real-time guarantees. | Set a flag/queue in the ISR and process in a background task. |
| **Magic Numbers for Registers** | Writing `*0x40020000 = 0x01;` makes code unreadable, unportable, and brittle. | Use vendor-provided header files (`GPIOA->BSRR = GPIO_PIN_0;`) or a proper HAL. |
| **Heap Fragmentation** | Repeated dynamic allocation causes devices to crash unpredictably weeks after deployment. | Statically allocate buffers, or use fixed-size memory pools. |
| **Assuming Hardware Works** | Assuming a sensor always responds or an I2C bus never locks up leads to infinite `while(1)` loops. | Always implement timeouts on hardware polling and bus transactions. |

## See Also
*   [Secure Coding](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/security/secure_coding.md)
*   [CI/CD](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/devops/ci_cd.md)

## References
*   [MISRA C Guidelines](https://www.misra.org.uk/)
*   [Embedded Systems Architecture (Barr)](https://barrgroup.com/)
*   [Zephyr Project Best Practices](https://zephyrproject.org/)
