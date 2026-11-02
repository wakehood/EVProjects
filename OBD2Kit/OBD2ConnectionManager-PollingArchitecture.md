# OBD2ConnectionManager — Polling Architecture Review

## Background

The app communicates with a custom MCU (battery management controller) via an ELM327 Bluetooth LE adapter.
The ELM327 bridges BLE to a CAN bus using the UDS (ISO 14229) protocol — specifically service 0x22
(Read Data By Identifier) for custom PIDs in the DD8x range, and standard OBD2 mode 0x01 for generic PIDs.

---

## Constraint: No Pipelining on ELM327

The ELM327 is a single-threaded serial adapter. It processes **one command at a time**:

1. Host sends a command (e.g., `22 DD 84`)
2. ELM327 queries the CAN bus and waits for the ECU response
3. ELM327 returns the response (terminated with `>`) over BLE
4. Only then is it ready for the next command

Sending a second command before the `>` prompt arrives **interrupts** the in-progress bus search.
The adapter responds with `STOPPED` — the exact symptom we worked around with the response gate
(`waitingForResponse` flag introduced in a previous revision).

**Conclusion: true batching or pipelining of requests is not possible with the ELM327.**

---

## Current Architecture (Timer-Driven)

```
┌─────────────────────────────────────────┐
│  Timer fires every 0.80 s               │
│    ↓                                    │
│  if !waitingForResponse → send command  │
│    ↓                                    │
│  BLE + CAN round-trip  (~100–200 ms)    │
│    ↓                                    │
│  Response received → parse → clear gate │
│    ↓                                    │
│  IDLE until next timer tick             │
└─────────────────────────────────────────┘
```

### Polling queue (6-slot rotation)

| Slot | Command        | PID    | Value              | Update rate* |
|------|----------------|--------|--------------------|-------------|
| 0    | `22 DD 83`     | DD83   | Pack Voltage       | ~4.8 s      |
| 1    | `22 DD 84`     | DD84   | Pack Current       | ~4.8 s      |
| 2a   | `01 1F`        | —      | MCU Run Time       | ~19 s       |
| 2b   | `22 DD 85`     | DD85   | State of Charge    | ~19 s       |
| 2c   | `22 DD 81`     | DD81   | Alerts/Status      | ~19 s       |
| 3    | `22 DD 86–89`  | DD86–9 | Cell V (min/max/mean/σ) | ~19 s  |
| 4    | `22 DD 8C`     | DD8C   | MCU Temp (Hi/Lo)   | ~4.8 s      |
| 5    | `22 DD 8E`     | DD8E   | Current kWh        | ~4.8 s      |

*Worst-case at 0.80 s/slot with 150 ms average round-trip. Actual is better on average
but can reach these numbers when the BLE link is congested.

### Problem

Pack current (DD84) — the most safety-critical real-time value — only updates every ~4.8 s
under the current scheme. In practice this feels sluggish on the display.

---

## Root Cause: Timer Is the Bottleneck

The 0.80 s interval was chosen conservatively to avoid STOPPED errors before the response gate
was introduced. Now that the gate exists, the timer serves no throttling purpose — it just
introduces up to 800 ms of dead idle time between commands.

**Proof of concept:** the burst test (DD84 rapid-fire mode) already demonstrates ~5–10
round-trips/sec using pure event-driven chaining with no timer at all.

---

## Proposed Architecture (Event-Driven / Response-Chained)

Replace the periodic `Timer` with a **send-on-response** chain:

```
┌─────────────────────────────────────────────┐
│  Response received (or watchdog timeout)    │
│    ↓                                        │
│  Immediately send next queued command       │
│    ↓                                        │
│  Arm watchdog (~1.5 s safety timeout)       │
│    ↓                                        │
│  BLE + CAN round-trip  (~100–200 ms)        │
│    ↓                                        │
│  Response received → parse → repeat         │
└─────────────────────────────────────────────┘
```

No idle time. Cycle time becomes purely a function of BLE + CAN latency.

### Expected improvement

| Metric               | Current (timer) | Event-driven |
|----------------------|-----------------|--------------|
| Commands/sec         | ~1.2            | ~5–8         |
| Pack current refresh | ~4.8 s          | ~1.0–1.5 s   |
| All 6 slots/cycle    | ~5–6 s          | ~0.9–1.5 s   |

---

## Enhancement: Priority Lanes

Not all values need the same refresh rate. A two-lane scheme gives fast data fast
without starving slower data:

```
Fast lane  (every cycle):  DD83 (voltage),  DD84 (current)
Slow lane  (every N fast cycles):
    01 1F  (runtime)       — every 10 cycles
    DD85   (SOC)           — every 10 cycles
    DD81   (alerts)        — every 5 cycles
    DD8C   (temp)          — every 5 cycles
    DD8E   (kWh)           — every 5 cycles
    DD86–89 (cell V)       — every 5 cycles, rotating one per cycle
```

At ~6 commands/sec this gives:
- Voltage & current: **~300 ms** refresh
- Alerts & temp: **~1 s** refresh
- SOC & runtime: **~2 s** refresh

---

## Implementation Notes

- The `waitingForResponse` gate and `responseTimeoutTask` watchdog already exist and can be reused.
- `pollingTimer` and `Timer.scheduledTimer` can be removed entirely.
- The new `sendNextPollingCommand()` method would be called from:
  - `peripheral(_:didUpdateValueFor:)` after parsing (replacing the current timer tick)
  - The watchdog timeout callback (to recover from dropped responses)
  - `startAutomaticPolling()` to kick off the first command
- The burst test already uses this exact pattern and can serve as a reference implementation.
- No changes to the BLE layer, handshake sequence, or parsing logic are needed.

---

## Files Affected

| File | Change |
|------|--------|
| `OBD2Kit/Sources/OBD2Kit/ODB2ConnectionManager.swift` | Replace timer loop with event-driven chain; add priority queue |
| `PanlongBlB04/PanlongBlB04/ContentView.swift` | No changes needed |
| `EvDisplay` app views | No changes needed |

---

*Document prepared for architectural review — no code changes have been made yet.*
