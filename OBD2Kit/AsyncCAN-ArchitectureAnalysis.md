# Asynchronous CAN Message Architecture Analysis
**Project:** EvDisplay / OBD2Kit  
**Date:** September 2026  
**Status:** Open — awaiting hardware decision

---

## Background

The EvDisplay system polls an MCU over a CAN bus via an ELM327-based BLE OBD2 adapter (Panlong BL-B04). A separate device — a Ground Fault Monitor (GFM) — will eventually send autonomous CAN frames using PID `DD 8F` (service 62, UDS DID `0xDD8F`) that the app must receive and process without requesting them.

Testing confirmed:

- The app-side autonomous message detection code is correct and working.
- SavvyCAN injection of a `7E8 04 62 DD 8F 00 00 00 00` frame was successfully received by the app once out of many manual attempts.
- The low hit rate is a hardware-layer timing problem, not a software problem.

---

## Root Cause: ELM327 Architectural Limitation

The ELM327 was designed exclusively for OBD2 request-response communication. It imposes two hard constraints that make reliable asynchronous message delivery impossible:

### 1. CAN Receive Filter

After `AT SP 6` (ISO 15765-4 CAN) and `AT SH 7DF`, the ELM327 sets a hardware receive filter for CAN IDs `0x7E8–0x7EF` (standard ECU response addresses). Any frame from a device using a **different CAN ID** is silently discarded before the app ever sees it.

### 2. Response Window Model

Even for frames arriving on `0x7E8`, the ELM327 only forwards CAN data during its **response window** — the brief interval (~150–500 ms) between sending a request and issuing the `>` prompt. A frame arriving outside that window is never forwarded. This is why only 1-in-many manual injects succeeded during testing.

### AT MA (Monitor All) Mode

`AT MA` was evaluated as an alternative. It puts the ELM327 in a continuous-receive mode and removes the response-window constraint. However:

- It cannot run concurrently with polling — the two modes are mutually exclusive.
- Testing showed the ELM327 did not forward injected frames during AT MA mode, likely due to clone firmware limitations.
- Switching between polling and monitoring would require a complex interleaved architecture.

---

## Options

### Option 1 — Firmware Coordination (Low Cost, Limited)

Have the GFM device send its CAN frames using:
- **CAN ID:** `0x7E8`  
- **Format:** UDS service `62`, DID `DD 8F`, followed by data bytes  
- **Timing:** send repeatedly at ~100 ms intervals

Frames formatted this way land within the ELM327's receive filter and will statistically hit open response windows. This requires no hardware changes and is the fastest path to a working solution. However, it is not deterministic — a GFM alert could be delayed by multiple poll cycles before the app receives it.

**Verdict:** Acceptable for low-urgency status updates. Not suitable for safety-critical alerts that require guaranteed delivery.

---

### Option 2 — Replace BLE-CAN Adapter (Recommended)

Replace the ELM327 BLE adapter with a **transparent BLE-CAN bridge** that forwards all CAN frames to the host without filtering or windowing. The app retains its existing polling architecture; autonomous frames simply arrive as additional notifications.

This is the correct long-term solution for a system that requires reliable async message delivery.

---

### Option 3 — Dual Adapter

Retain the ELM327 for polling. Add a second BLE-CAN adapter in AT MA / transparent mode dedicated to receiving autonomous frames. The app maintains two BLE connections. Complex and adds hardware cost, but avoids re-qualifying the polling path.

---

## Recommended BLE-CAN Bridge Hardware

### Tier 1 — Direct Drop-In Replacement

| Device | Notes |
|--------|-------|
| **MeatPi WiCAN** | ESP32-based (this is a chip), OBD2 connector, supports both ELM327-emulation mode AND transparent CAN mode. In transparent mode all CAN frames are forwarded over BLE or WiFi. Open-source firmware (GitHub: meatpiHQ/wican-fw). Actively maintained. Best fit for this use case. |
| **OBDLink MX+** | Higher-quality ELM327 firmware than clone adapters. Supports `AT MA` more reliably. Still fundamentally ELM327-based — does not solve the response-window constraint for truly async messages. Better for reliability improvement only. |

### Tier 2 — Development Board / Custom

| Device | Notes |
|--------|-------|
| **Nordic nRF52840 + SN65HVD230 CAN transceiver** | Maximum flexibility. nRF52840 (BLE 5.0, 1 Mbps throughput) combined with a 3.3V CAN transceiver. Can be programmed to forward all CAN frames over BLE notify. Adafruit Feather nRF52840 is a convenient dev board. Requires custom firmware. |
| **Seeed Studio XIAO nRF52840 + MCP2551** | Compact form factor. Same approach as above at lower cost. |
| **Espressif ESP32-S3 + MCP2515 SPI CAN** | WiFi + BLE, widely supported. MCP2515 is a mature SPI CAN controller. Slightly higher latency than nRF52840 but more community firmware available. |

### Tier 3 — Professional / Industrial

| Device | Notes |
|--------|-------|
| **PEAK-System PCAN-BT** | Professional-grade Bluetooth CAN interface. Transparent mode. High reliability. Significantly more expensive. |
| **Kvaser Leaf Light Bluetooth** | Kvaser quality. Full CAN 2.0B support. SDK available. Also significantly more expensive. |

---

## Recommended Path

1. **Short term:** Implement Option 1 (firmware coordination). Have the GFM device send `7E8 04 62 DD 8F XX` at 100 ms intervals. The app will catch frames stochastically during poll windows. Deploy for initial field testing.

2. **Medium term:** Evaluate **MeatPi WiCAN** in transparent mode. It uses the same OBD2 connector, is inexpensive (~$20–30), and its open-source firmware can be verified and modified if needed. If it passes validation, replace the Panlong adapter.

3. **App change required for Option 2:** The `OBD2ConnectionManager` would need a second `CBPeripheral` connection for the transparent adapter (or the WiCAN replaces the ELM327 entirely, in which case the polling path uses WiCAN's ELM327 emulation mode and async frames arrive through the same connection in transparent mode simultaneously).

---

## App-Side Code Status

The following changes are already implemented and validated:

| Change | File | Status |
|--------|------|--------|
| Pending response prefix tracking (`pendingResponsePrefix`) | `ODB2ConnectionManager.swift` | ✅ Complete |
| Autonomous message detection (`isSolicited` check) | `ODB2ConnectionManager.swift` | ✅ Complete |
| Autonomous message logging (`[autonomous]` print) | `ODB2ConnectionManager.swift` | ✅ Complete |
| GFM PID definition (`DD 8F`, `mcuGFMResp`) | `ODB2ConnectionManager.swift` | ✅ Complete |
| AT MA monitor mode for hardware testing | `ODB2ConnectionManager.swift` | ✅ Complete |
| Manual connect / autoConnect flag | `ODB2ConnectionManager.swift` | ✅ Complete |

The app will correctly handle autonomous GFM frames the moment the hardware delivers them reliably.

---

*To convert this file to .docx:* `pandoc AsyncCAN-ArchitectureAnalysis.md -o AsyncCAN-ArchitectureAnalysis.docx`
