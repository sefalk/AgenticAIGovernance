**Version: 1.0 | Date: 2026-03-04**
**Level: 2 | Domain: Embedded Systems**
**Derived from:** [L1_Core_Principles.md](../L1_Core_Principles.md) (Level 1, v3.8)

---

# Level 2 — Embedded Systems Domain Rules

## Purpose

This artifact derives domain-specific rules for embedded software, firmware, and hardware-adjacent systems from the Level-1 Core Principles. These rules apply to C, C++, Rust, and assembly projects targeting microcontrollers, RTOS platforms, and other resource-constrained environments. They supplement — and in some cases override — the generic `L2_Software_Development.md` rules where embedded constraints differ fundamentally.

> **Precedence:** Where a rule in this document conflicts with `L2_Software_Development.md`, this document takes precedence for embedded projects.

> **Note:** Rule IDs are grouped by their parent L1 principle, not assigned sequentially.

---

## Derived Rules

### From: Verifiability & Quality Assurance (L1)

**R-ES-01:** Builds SHALL be deterministic and reproducible. Given the same source, toolchain version, and linker script, the build artifact (`.elf`, `.hex`, `.bin`) MUST be bitwise-identical (or functionally equivalent for targets with non-deterministic LTO). Build command and toolchain version SHALL be documented.

**R-ES-02:** Tests SHALL be executed at minimum in a simulator or emulator (e.g., QEMU, Renode, Proteus) when hardware is unavailable. Hardware-in-the-loop (HIL) test results, when available, SHALL supersede simulator results. The test environment (simulator vs. HIL vs. real hardware) SHALL be documented in the test report.

**R-ES-03:** Static analysis SHALL be run with a safety-oriented analyzer (e.g., `cppcheck`, `PC-lint`, `Polyspace`, `clang-tidy`). For safety-critical projects (ISO 26262, IEC 61508), MISRA-C or MISRA-C++ compliance SHALL be enforced. Deviation records are required for any permitted MISRA violation.

**R-ES-04:** Code coverage SHALL be measured via instrumented builds (e.g., GCOV/LCOV) if the toolchain and target support it. If coverage measurement is not feasible on the target, coverage of the simulator test suite is an acceptable proxy. Coverage thresholds are defined at Level 4.

**R-ES-05:** Real-Time Constraint Documentation (WCET): For tasks with hard real-time requirements, the Worst-Case Execution Time (WCET) SHALL be measured or formally estimated and documented. WCET analysis results SHALL be version-controlled alongside the code.

### From: Transparency/Traceability (L1)

**R-ES-06:** Memory usage (stack, heap, flash, RAM) SHALL be documented and verified at build time. Unresolvable linker-section overflows SHALL be treated as build failures, not warnings. Memory maps SHALL be committed alongside build artifacts to the release record.

**R-ES-07:** Interrupt Service Routines (ISRs) SHALL be documented with their maximum execution time, any global state they modify, and the interrupt priority level. Undocumented ISR side effects are a traceability violation.

**R-ES-08:** All external hardware interfaces (I2C, SPI, UART, CAN, GPIO) SHALL be documented with their protocol, timing constraints, and error handling approach. Undocumented hardware dependencies are a traceability violation.

### From: Safety & Security (L1)

**R-ES-09:** Watchdog timers SHALL be enabled and regularly serviced in all production firmware. Disabling or trivially bypassing the watchdog (e.g., feeding it in an infinite loop unrelated to application state) SHALL NOT be permitted without documented justification.

**R-ES-10:** Safe Failure States: When an unrecoverable error is detected (stack overflow, assertion failure, hardware fault), the firmware SHALL enter a defined safe state (e.g., disable actuators, set outputs to known-safe levels) before attempting reset. Uncontrolled failure is a safety violation.

**R-ES-11:** All cryptographic operations on embedded targets SHALL use vetted, constant-time implementations (e.g., mbed TLS, WolfSSL). Ad-hoc cryptography and home-grown cipher implementations SHALL NOT be used.

**R-ES-12:** Firmware update mechanisms SHALL authenticate the update image (e.g., via ECDSA signature verification) before flashing. Unsigned firmware SHALL NOT be accepted by the bootloader in production configurations.

### From: Fail-Safe & Ask First (L1)

**R-ES-13:** Hardware Abstraction: Business logic SHALL NOT directly access hardware registers. A Hardware Abstraction Layer (HAL) or Board Support Package (BSP) MUST separate hardware-specific code from application logic. This enables off-target testing and protects against hardware vendor lock-in.

**R-ES-14:** All peripheral driver code SHALL handle hardware fault conditions explicitly (e.g., I2C bus lockup, SPI timeout, ADC overrun). Hanging on hardware errors without timeout and recovery is a Fail-Safe violation.

### From: Efficiency / Pragmatism (L1)

**R-ES-15:** Dynamic memory allocation (malloc/free, new/delete) SHALL NOT be used in interrupt contexts or safety-critical code paths. In resource-constrained environments, heap fragmentation is a reliability risk. Use static allocation or memory pools where possible.

---

## Applicability

These rules apply to all embedded and firmware projects governed by the AAIG framework. For mixed projects (e.g., a Python host application controlling an embedded device), apply `L2_Software_Development.md` to the host and this document to the firmware.

## Relationship to Skills Toolbox

- R-ES-01, R-ES-04 → `skills/embedded/embedded_systems.md`
- R-ES-03 → `skills/testing/static_analysis.md`
- R-ES-02 → `skills/testing/unit_testing.md` (adapted for embedded)
- R-ES-11, R-ES-12 → `skills/security/secure_coding.md`
- R-ES-13 → `skills/architecture/system_design.md`
