# Changelog

All notable changes to SwiftBLEKit are documented here. This project adheres to
[Semantic Versioning](https://semver.org).

## [Unreleased]

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

[Unreleased]: https://github.com/DeepakPal25/SwiftBLEKit/compare/0.2.0...HEAD
[0.2.0]: https://github.com/DeepakPal25/SwiftBLEKit/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/DeepakPal25/SwiftBLEKit/releases/tag/0.1.0
