# Changelog

All notable changes to SwiftBLEKit are documented here. This project adheres to
[Semantic Versioning](https://semver.org).

## [Unreleased]

## [0.4.0]

Core Bluetooth state restoration — a reference implementation of the notoriously
fiddly `willRestoreState` flow, exposed through the same testable abstraction.

### Added
- **`BLERestorationState`** — the peripherals (and scan services) iOS hands back
  when it relaunches the app for a Bluetooth event.
- **`BLECentralManaging.restorationEvents()`** — an `AsyncStream` of restoration
  events; `LiveCentralManager` buffers a restoration that arrives before any
  observer subscribes (as it does very early in a background relaunch).
- **`MockCentralManager.simulateRestoration(_:)`** — drive restoration in tests
  and confirm restored peripherals are registered and reconnectable.
- Tests covering restoration delivery and coordinator resumption.

## [0.3.0]

Standard GATT profiles: typed Swift models for the common assigned
characteristics, shipped as `CharacteristicValue` conformances that drop
straight into the DSL.

### Added
- **Typed characteristic models** — `BatteryLevel`, `HeartRateMeasurement`
  (8/16-bit value, energy expended, RR intervals, sensor contact),
  `BodySensorLocation`, `GATTString` (Device Information strings),
  `CyclingPowerMeasurement` (instantaneous power + pedal balance), and
  `HIDReport`.
- **`StandardProfile`** — pre-built `ServiceSpec` factories
  (`.battery`, `.heartRate`, `.cyclingPower`, `.deviceInformation`) that combine
  the DSL with the typed models.
- **`ByteReader`** — an internal bounds-checked little-endian payload cursor.
- Assigned-number UUIDs for cycling power, HID report, and additional Device
  Information fields.
- Tests with spec byte-vectors for every model, plus a DSL integration test.

## [0.2.0]

A declarative DSL for describing and consuming a peripheral's GATT services,
built on the same abstraction so it stays testable with the in-memory doubles.

### Added
- **`GATTProfile`** — a result-builder DSL (`service { … }` /
  `characteristic(_:)`) for declaring the services and characteristics an app
  cares about.
- **Fluent operations** — `read`/`notify` (raw `Data`) and their typed
  `read(as:)`/`notify(as:)` variants.
- **`CharacteristicValue`** — a protocol for decoding characteristic bytes into
  typed values (`Data` conforms out of the box).
- **`BLEPeripheralProtocol.attach(_:)`** — discovers everything in a profile,
  runs declared reads, and wires up notifications, returning a **`GATTSession`**
  that owns the subscription lifetimes.
- Tests covering DSL tree building, `attach` read/notify behaviour, and the
  missing-service error path — all against `SimulatedPeripheral`.

## [0.1.0]

The foundation: a testable Core Bluetooth abstraction with automatic
reconnection.

### Added
- **Abstraction layer** — `BLECentralManaging` and `BLEPeripheralProtocol`, a
  platform-independent seam over Core Bluetooth using `async`/`await` and
  `AsyncStream`.
- **Core value types** — `BLEUUID` (with common assigned numbers), `BLEError`,
  `BLEManagerState`, `ConnectionState`, `BLEDiscovery`, and `AdvertisementData`.
- **`ConnectionCoordinator`** — a connection state machine that applies
  automatic reconnection with exponential backoff on unexpected drops, with an
  injectable `sleep` for deterministic testing.
- **`ExponentialBackoff`** — a pure, unit-tested retry schedule with a delay
  ceiling, attempt budget, and jitter.
- **Core Bluetooth adapter** — `LiveCentralManager` and `LivePeripheral`, the
  production implementation of the abstraction (opt-in state-restoration hook).
- **Testing doubles** — `MockCentralManager` and `SimulatedPeripheral` for
  simulating discovery, connection failures, disconnects, RSSI, reads/writes,
  and notifications entirely in memory.
- Unit tests covering the backoff curve, the mock layer, and coordinator
  reconnection/failure paths.

[Unreleased]: https://github.com/DeepakPal25/SwiftBLEKit/compare/0.4.0...HEAD
[0.4.0]: https://github.com/DeepakPal25/SwiftBLEKit/compare/0.3.0...0.4.0
[0.3.0]: https://github.com/DeepakPal25/SwiftBLEKit/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/DeepakPal25/SwiftBLEKit/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/DeepakPal25/SwiftBLEKit/releases/tag/0.1.0
