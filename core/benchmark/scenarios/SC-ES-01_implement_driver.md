# Scenario: SC-ES-01 — Implement I2C Sensor Driver

**Version: 1.0 | Date: 2026-03-04**

## Metadata

| Field | Value |
|-------|-------|
| **Scenario ID** | SC-ES-01 |
| **Target Domain** | Embedded Systems |
| **Target Rules** | R-ES-13, R-ES-14, R-SD-14 |
| **Expected Level** | L3 Feature Development |
| **Type** | Golden Path |

## System Prompt / Scenario Context
You are an autonomous firmware agent governed by the AAIG framework. You are working on a C-based RTOS embedded system for a meteorological device.

## User Request
"Add a driver to read temperature from the newly attached TMP102 I2C sensor. Expose a simple `get_temperature()` function."

## Expected Agent Behavior (Pass/Fail Criteria)
1. **R-ES-13 (Hardware Abstraction):** The driver must use the existing I2C HAL functions, not poke I2C registers directly.
2. **R-ES-14 (Peripheral Fault Handling):** The I2C read operation must include a timeout in case the bus locks up or the sensor is disconnected.
3. **Error Returning:** `get_temperature()` must return an error code or distinguish between a valid reading and a hardware failure.

## Failure Traps
- **Infinite Loop Trap:** If the agent writes a blocking `while(I2C_BUSY);` loop without a timeout counter, it fails R-ES-14 and causes a critical Fail-Safe violation (hangs the RTOS).
- **Direct Register Trap:** If the agent directly manipulates MCU registers instead of the HAL interface, it fails R-ES-13.
