# Combo PID Proposal: DD 90

**To:** MCU Firmware Team  
**From:** EV Display App Team  
**Date:** November 2026  
**Status:** Proposal — pending firmware discussion

---

## Background

The EV Display app communicates with the MCU over BLE using an ELM327 OBD2 adapter and ISO 15765-2 CAN framing. Each data value currently requires its own request/response round-trip. At observed real-world latency of ~300 ms per round-trip, the app polls the most critical values (pack voltage and pack current) at roughly 1.7 Hz, and cell voltages and fault status at a slower rotation of approximately every 3 seconds.

---

## Proposed Change

Add a new firmware PID — **DD 90** — that returns five 16-bit values in a single response:

| Byte Offset | Value | Type | Scale | Existing PID |
|---|---|---|---|---|
| 0–1 | Pack voltage | Int16, little-endian | ÷ 10 → Volts | DD 83 |
| 2–3 | Pack current | Int16, little-endian | ÷ 10 → Amps (signed) | DD 84 |
| 4–5 | Cell minimum | UInt16, little-endian | ÷ 10000 → Volts | DD 86 |
| 6–7 | Cell maximum | UInt16, little-endian | ÷ 10000 → Volts | DD 87 |
| 8–9 | Fault status word | UInt16, little-endian | bitmask | DD 8F |

The encoding for current matches the existing DD 84 formula: `((signed(B) × 256) + A) / 10`, which is a standard little-endian signed Int16. All five values are the same 2-byte width, making the packing straightforward and uniform.

---

## ISO 15765-2 Frame Analysis

Each individual PID returns 2 bytes of data, which fits in a single CAN frame. The proposed DD 90 response carries 10 bytes of data. Here is how ISO 15765-2 packs that:

**Single Frame capacity:** 7 bytes payload (mode + PID + data) → max **4 bytes** of raw data  
**First Frame + 1 Consecutive Frame capacity:** 6 + 7 = 13 bytes → max **10 bytes** of raw data

The 10-byte combo response fits exactly within a **2-frame exchange** (First Frame + one Consecutive Frame). The ELM327 adapter handles the flow-control handshake transparently, so this requires no changes to the app's BLE layer.

---

## Performance Impact

### Current polling architecture (3-tier)

```
Tick % 3 == 0  →  DD 84  (pack current)
Tick % 3 == 1  →  DD 83  (pack voltage)
Tick % 3 == 2  →  slow slot: DD 8F / DD 86 / DD 87, rotating
                   every 67 slow slots: x-slow: DD 85 / DD 8E / DD 8C
```

At 300 ms/tick:
- Voltage and current: ~1.7 Hz (one of each per 3 ticks)
- Cell min/max and fault status: one item every ~2.7 s per rotation
- SOC, energy, temperature: one item every ~200 s per rotation

### Proposed architecture with DD 90 (2-tier)

```
Tick 0  →  DD 90  (voltage + current + cellMin + cellMax + status)
Tick 1  →  x-slow: DD 85 / DD 8E / DD 8C, rotating every N ticks
```

At 300 ms/tick:
- Voltage, current, cell min/max, fault status: **~3.3 Hz** (every other tick)
- SOC, energy, temperature: unchanged slow cadence

### Summary of improvements

| Value | Current update rate | With DD 90 |
|---|---|---|
| Pack voltage | ~1.7 Hz | ~3.3 Hz |
| Pack current | ~1.7 Hz | ~3.3 Hz |
| Cell min voltage | ~1 per 2.7 s | ~3.3 Hz |
| Cell max voltage | ~1 per 2.7 s | ~3.3 Hz |
| Fault status | ~1 per 2.7 s | ~3.3 Hz |
| SOC / energy / temp | ~1 per 200 s each | unchanged |

Cell voltages and fault status move from the slow queue into the fast lane — alert detection latency drops from ~2.7 s to ~300 ms.

---

## App-Side Implementation Plan

No changes are needed until the firmware is confirmed. When DD 90 is available:

1. Add `mcuComboReq = "22 DD 90"` to `MCUConstants`.
2. Add a `parseComboResponse(_:)` function that extracts the five Int16/UInt16 values using little-endian byte order.
3. Replace the 3-tick cycle with a 2-tick cycle: tick 0 sends DD 90, tick 1 services the x-slow queue.
4. Remove `slowPollQueue`, `slowQueueIndex`, `xSlowCounter` (no longer needed).
5. Update the `PollingCadenceSimulationTests` to reflect the new architecture.

The existing individual PIDs (DD 83, DD 84, DD 86, DD 87, DD 8F) can remain in the firmware for diagnostic use by the Panlong test app.

---

## Open Questions for Firmware Team

1. Is DD 90 a feasible PID number, or is that range reserved?
2. Should the 2-frame response be treated as a single atomic snapshot (all values from the same CAN message cycle), or is it acceptable to return values from two consecutive MCU sample points?
3. Are the scale factors for cellMin/cellMax in DD 90 the same as DD 86/DD 87 (÷ 10000)?
4. Any concern about the extra overhead of the ISO 15765-2 flow-control handshake at the firmware side?
