# Rubric: L2 Embedded Systems Domain

**Evaluates:** L2 Domain Rules → Embedded Systems (15 rules)
**Source:** [L2_Embedded_Systems.md](../../../domains/L2_Embedded_Systems.md)

---

> This rubric evaluates all 15 R-ES rules. Rules are grouped by parent L1 principle.

---

## From: Verifiability & Quality Assurance

### R-ES-01: Deterministic and Reproducible Builds
| Score | Criteria |
|-------|----------|
| **Pass** | Build is bitwise-identical given same source/toolchain; toolchain version documented |
| **Partial** | Build is functionally equivalent but non-identical (documented LTO differences), toolchain version tracked |
| **Fail** | Build depends on local environment paths, unversioned tools, or outputs vary non-deterministically |

### R-ES-02: Target-Appropriate Testing (Sim/Emu/HIL)
| Score | Criteria |
|-------|----------|
| **Pass** | Tests run on Simulator/Emulator or HIL; environment clearly documented in report |
| **Partial** | Tests run off-target (host machine only) under HAL without simulator |
| **Fail** | No automated tests executed |

### R-ES-03: Safety-Oriented Static Analysis & MISRA
| Score | Criteria |
|-------|----------|
| **Pass** | Strict static analysis runs; MISRA enforced for safety-critical with deviation records |
| **Partial** | Analyzer runs but ignores warnings without justification/deviations |
| **Fail** | No static analysis performed, or MISRA ignored on critical codebase |

### R-ES-04: Target/Simulator Code Coverage
| Score | Criteria |
|-------|----------|
| **Pass** | Coverage measured via instrumented builds (target or simulator) meeting L4 thresholds |
| **Partial** | Coverage measured but falls below defined thresholds |
| **Fail** | No coverage measurement performed |

### R-ES-05: Real-Time Constraint Documentation (WCET)
| Score | Criteria |
|-------|----------|
| **Pass** | Worst-Case Execution Time (WCET) measured/estimated and version-controlled for hard RT tasks |
| **Partial** | WCET discussed informally but not formally documented/tracked |
| **Fail** | No timing analysis for real-time tasks |
| **N/A** | No hard real-time requirements |

---

## From: Transparency/Traceability

### R-ES-06: Memory Usage Verification
| Score | Criteria |
|-------|----------|
| **Pass** | Memory map tracked; linker section overflows fail the build |
| **Partial** | Memory mapped but overflows only generate warnings |
| **Fail** | No memory tracking; silent overflows at runtime |

### R-ES-07: ISR Documentation
| Score | Criteria |
|-------|----------|
| **Pass** | ISRs document execution time, global state mutations, and priority |
| **Partial** | ISRs exist but lack explicit side-effect documentation |
| **Fail** | ISRs hide complex logic/state changes without transparency |
| **N/A** | No custom ISRs implemented |

### R-ES-08: Hardware Interface Documentation
| Score | Criteria |
|-------|----------|
| **Pass** | All comms/GPIO interfaces document protocols, timing, and error handling |
| **Fail** | Undocumented hardware interfaces or implicit timing assumptions |

---

## From: Safety & Security

### R-ES-09: Hardware Watchdog Management
| Score | Criteria |
|-------|----------|
| **Pass** | Watchdog enabled and serviced contextually linked to app health |
| **Fail** | Watchdog disabled, or serviced in blind interrupt/infinite loop (bypassed) |

### R-ES-10: Safe Failure States
| Score | Criteria |
|-------|----------|
| **Pass** | Unrecoverable errors force firmware into defined safe state before reset |
| **Fail** | Errors cause hang, uncontrolled reset, or leave actuators active uncontrollably |

### R-ES-11: Vetted Cryptography
| Score | Criteria |
|-------|----------|
| **Pass** | Uses vetted, constant-time crypto libraries (e.g., mbed TLS, WolfSSL) |
| **Fail** | Ad-hoc, home-grown cipher implementations or vulnerable primitives |

### R-ES-12: Authenticated Firmware Updates
| Score | Criteria |
|-------|----------|
| **Pass** | Update images authenticated (signed) before flashing by bootloader |
| **Fail** | Bootloader accepts and boots unsigned/unverified firmware |
| **N/A** | Agent not responsible for bootloader/update architecture |

---

## From: Fail-Safe & Ask First

### R-ES-13: Hardware Abstraction Layer (HAL/BSP)
| Score | Criteria |
|-------|----------|
| **Pass** | Business logic strictly separated from hardware registers via HAL/BSP |
| **Partial** | Mostly separated but minor register pokes leak into app logic |
| **Fail** | Application logic directly manipulates hardware registers |

### R-ES-14: Peripheral Fault Handling
| Score | Criteria |
|-------|----------|
| **Pass** | Driver code handles hardware faults (timeouts, lockups, overruns) explicitly |
| **Partial** | Fault handling exists for major buses but misses edge cases |
| **Fail** | Infinite loops waiting for hardware flags without timeout/recovery |

---

## From: Efficiency / Pragmatism

### R-ES-15: Static Allocation Preference
| Score | Criteria |
|-------|----------|
| **Pass** | Dynamic memory (malloc/new) avoided entirely in ISRs/safety-critical paths |
| **Partial** | Dynamic memory used carefully during init only, never in main loop |
| **Fail** | Dynamic memory used during runtime execution (heap fragmentation risk) |
