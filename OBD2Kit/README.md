# OBD2Kit

A Swift package for communicating with custom CAN bus devices via an ELM327-based Bluetooth Low Energy OBD2 adapter.

OBD2Kit manages the full lifecycle of a BLE OBD2 connection: adapter discovery, ELM327 handshake, UDS/OBD2 polling, CAN response parsing, and detection of autonomous (unsolicited) CAN messages.

---

## Requirements

- iOS 18.4+
- Swift 5.9+
- ELM327-compatible BLE OBD2 adapter (FFF0/FFF1/FFF2 service/characteristic UUIDs)

---

## Installation

Add OBD2Kit as a local Swift Package dependency in Xcode:

1. File → Add Package Dependencies
2. Choose "Add Local…" and select the `OBD2Kit` directory

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(path: "../OBD2Kit")
]
```

---

## Overview

`OBD2ConnectionManager` is an `@Observable` class that subclasses `NSObject` and implements `CBCentralManagerDelegate` and `CBPeripheralDelegate`. It is designed to be used as an environment object in a SwiftUI application.

### Connection Lifecycle

By default the manager auto-connects on initialization. For apps that need to configure settings before connecting (e.g. enabling monitor mode), pass `autoConnect: false` and call `connect()` manually:

```swift
// Auto-connect on launch (default)
let manager = OBD2ConnectionManager()

// Manual connect — set options first, then connect
let manager = OBD2ConnectionManager(autoConnect: false)
manager.isMonitorModeActive = true
manager.connect()
```

### ELM327 Handshake

On connection, the manager automatically runs the ELM327 initialization sequence:

| Step | Command | Purpose |
|------|---------|---------|
| 1 | `AT Z` | Reset adapter |
| 2 | `AT E0` | Echo off |
| 3 | `AT H1` | Headers on |
| 4 | `AT ST FF` | Maximum bus timeout |
| 5 | `AT SP 6` | ISO 15765-4 CAN protocol |
| 6 | `AT SH 7DF` | Broadcast request header |
| 7–10 | UDS queries | Read version, voltage cutoffs, pack capacity |
| 11 | — | Begin automatic polling (or AT MA in monitor mode) |

### Automatic Polling

After the handshake the manager begins a 3-slot polling cycle:

- **Slot 0:** Pack current (DD 84) — fast lane
- **Slot 1:** Pack voltage (DD 83) — fast lane  
- **Slot 2:** One item from a 9-item slow queue, rotating each cycle

At ~150 ms per round-trip, current and voltage refresh every ~450 ms; slow items (SOC, temperature, cell voltages, etc.) rotate fully every ~4 seconds.

---

## Supported PIDs

All PIDs use UDS service `22` (ReadDataByIdentifier) with custom DIDs in the `DD xx` range, plus one standard OBD2 PID.

| DID | Description | Update Rate |
|-----|-------------|-------------|
| `01 1F` | MCU Run Time | Slow |
| `DD 80` | MCU Firmware Version | Handshake only |
| `DD 81` | MCU Status / Alert Flags | Slow |
| `DD 83` | Pack Voltage | Fast |
| `DD 84` | Pack Current | Fast |
| `DD 85` | State of Charge | Slow |
| `DD 86` | Cell Minimum Voltage | Slow |
| `DD 87` | Cell Maximum Voltage | Slow |
| `DD 88` | Cell Mean Voltage | Slow |
| `DD 89` | Cell Voltage Std Deviation | Slow |
| `DD 8A` | High Voltage Cutoff | Handshake only |
| `DD 8B` | Low Voltage Cutoff | Handshake only |
| `DD 8C` | MCU Temperature (Hi/Lo) | Slow |
| `DD 8D` | Pack Max Capacity (kWh) | Handshake only |
| `DD 8E` | Pack Current Energy (kWh) | Slow |
| `DD 8F` | Ground Fault Monitor | Autonomous receive only |

---

## Autonomous Message Handling

The manager distinguishes between solicited responses (answers to poll requests) and autonomous messages (unsolicited frames from other devices on the bus).

When a response arrives, the manager checks whether its PID prefix matches the pending request (`pendingResponsePrefix`). If it does not match, the frame is parsed for data but the response gate is left open and the poll chain is not advanced.

Autonomous messages are logged to the console with an `[autonomous]` prefix and appear in `receivedLogs`.

```
[autonomous] 7E8 04 62 DD 8F 01 00 00 00
```

> **Hardware note:** The ELM327 only forwards CAN frames during its response window. Reliable delivery of autonomous messages from a separate CAN device requires a transparent BLE-CAN bridge. See `AsyncCAN-ArchitectureAnalysis.md` for options.

---

## Published Properties

All properties are `@Observable` and update on the main actor.

### Connection
| Property | Type | Description |
|----------|------|-------------|
| `connectionStatus` | `String` | Human-readable connection state |
| `isConnected` | `Bool` | BLE peripheral connected and ready |
| `isScanning` | `Bool` | Currently scanning for peripherals |
| `receivedLogs` | `[String]` | Rolling log of the last 25 bus messages |

### MCU Telemetry (Raw)
| Property | Type | Description |
|----------|------|-------------|
| `rawPackVoltage` | `Double` | Volts |
| `rawPackCurrent` | `Double` | Amps (negative = discharge) |
| `rawSOCPercentage` | `Int` | 0–100 % |
| `rawCellMin/Max/Mean/StdDev` | `Double` | Cell voltages in volts |
| `rawMcuHighTemp / rawMcuLowTemp` | `Double` | °C |
| `rawPackCapacityKwh` | `Double` | Nominal capacity |
| `rawCurrentKwh` | `Double` | Present energy |
| `rawAvailableEnergyKwh` | `Double` | Computed: SOC × capacity |

### Alert Flags
`alertHardware`, `alertCCensus`, `alertTCensus`, `alertHVC`, `alertLVC`, `alertHiTemp`, `alertLoTemp` — each `Int`, `1` = active.

---

## Subclassing

`OBD2ConnectionManager` is declared `open` to support subclassing. Override `sendCommand(_:)` to intercept outgoing commands, or add additional parsing in a subclass that calls `super`.

---

## Developer Tools

The manager includes built-in test utilities accessible from a debug UI:

- **Burst test** (`startBurstTest()`) — measures raw round-trip throughput (requests/sec, success rate, timeouts) over a 60-second run.
- **Polling cadence metrics** (`startPollingMetricsTest(duration:)`) — measures actual fast/slow lane dispatch rates over a configurable window.
- **CAN Monitor mode** (`isMonitorModeActive`) — replaces polling with `AT MA` after handshake, streaming all raw CAN frames to the console. Must be set before calling `connect()`. Useful for verifying bus traffic and injected frames during hardware bringup.

---

## License

Private / proprietary. All rights reserved.
