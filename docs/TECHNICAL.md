# SwiftBLEKit — Technical Documentation

This document explains **how Bluetooth Low Energy (BLE) connectivity works on
Apple platforms**, **why SwiftBLEKit is built the way it is**, and **how each
layer of the library operates** end to end.

It is written to be read top-to-bottom: it starts with the wireless fundamentals,
then the problems those fundamentals create for app developers, then the
architecture SwiftBLEKit uses to solve them, and finally a module-by-module
walkthrough of the code with the concurrency model that ties it together.

---

## Table of contents

1. [How Bluetooth Low Energy works](#1-how-bluetooth-low-energy-works)
2. [Core Bluetooth on Apple platforms](#2-core-bluetooth-on-apple-platforms)
3. [The problems SwiftBLEKit solves](#3-the-problems-swiftblekit-solves)
4. [Architecture: one seam, many layers](#4-architecture-one-seam-many-layers)
5. [The abstraction boundary](#5-the-abstraction-boundary)
6. [Layer walkthrough](#6-layer-walkthrough)
7. [Concurrency model](#7-concurrency-model)
8. [End-to-end data flows](#8-end-to-end-data-flows)
9. [Testing strategy](#9-testing-strategy)
10. [Build & packaging](#10-build--packaging)

---

## 1. How Bluetooth Low Energy works

Bluetooth Low Energy (BLE, introduced in Bluetooth 4.0) is a wireless protocol
optimized for **low power** and **small, infrequent data transfers** — sensors,
wearables, beacons, smart-home devices. It is a different protocol stack from
"Bluetooth Classic" (used for audio streaming, etc.); iOS accessories that are
not MFi/audio use BLE.

### Roles: Central and Peripheral

Every BLE connection has two roles:

| Role | Who plays it | Responsibility |
| --- | --- | --- |
| **Peripheral** | The accessory (heart-rate strap, thermostat) | Advertises its presence; hosts data |
| **Central** | Usually the phone/app | Scans for peripherals, initiates connections, reads/writes data |

An iPhone app is almost always the **central**. SwiftBLEKit is a **central-role**
library: it scans, connects, and consumes data from peripherals.

### Advertising and scanning

A peripheral that wants to be found broadcasts small **advertisement packets** on
three dedicated channels. Each packet can carry a short local name, a list of
service UUIDs it offers, manufacturer-specific data, and a "connectable" flag.

The central **scans** — it listens for these advertisements. When it hears one,
it learns the peripheral's identity and signal strength (**RSSI**, in dBm; closer
to 0 = stronger). The central can filter scans to only report peripherals
advertising a particular service (e.g. only heart-rate monitors).

> In SwiftBLEKit this maps to `AdvertisementData`, `BLEDiscovery` (peripheral +
> advertisement + RSSI), and `scan(services:)`.

### Connecting

Once the central decides to connect, a **connection** is established: the two
devices agree on timing parameters (connection interval, latency, supervision
timeout) and begin exchanging packets on a schedule. From this point the
peripheral typically stops advertising to that central.

Connections are **not guaranteed to be stable** — the link can drop from range,
interference, the peripheral sleeping, or the OS reclaiming resources. Detecting
and recovering from those drops is a core concern (see §3).

### GATT: the data model

Once connected, data is organized by the **Generic Attribute Profile (GATT)**, a
hierarchy:

```
Peripheral
└── Service (e.g. Heart Rate, UUID 0x180D)
    ├── Characteristic (e.g. Heart Rate Measurement, 0x2A37)
    │   └── value: raw bytes (+ properties: read/write/notify)
    └── Characteristic (e.g. Body Sensor Location, 0x2A38)
```

- A **Service** is a named group of related data (Heart Rate, Battery, Device
  Information).
- A **Characteristic** is a single data point within a service. It has a value
  (raw bytes), and **properties** that say what you can do with it:
  - **Read** — the central pulls the current value on demand.
  - **Write** — the central pushes a value (optionally with acknowledgement).
  - **Notify / Indicate** — the peripheral *pushes* new values to the central
    whenever they change (notify = unacknowledged, indicate = acknowledged).
    This is how a heart-rate strap streams live readings.

UUIDs identify services and characteristics. The Bluetooth SIG assigns short
16-bit UUIDs to standard ones (`0x180D` = Heart Rate); vendors use full 128-bit
UUIDs for custom data.

> In SwiftBLEKit: `BLEUUID` (with the standard assigned numbers as constants),
> `discoverServices`, `discoverCharacteristics`, `readValue`, `writeValue`,
> `setNotify`, and `notifications(for:)`.

### The discovery → subscribe → parse pipeline

Every BLE interaction follows the same shape:

1. **Discover services** — ask the peripheral which services it has.
2. **Discover characteristics** — for each service you care about, ask which
   characteristics it has.
3. **Subscribe / read** — enable notifications, or read the value.
4. **Parse** — the value arrives as raw `Data` (little-endian byte layouts
   defined by the spec); you decode it into a usable number/string.

Steps 1–4 are identical in structure for nearly every app. SwiftBLEKit's DSL
(§6) and Profiles (§6) exist to remove this boilerplate.

### Byte encoding

Characteristic values are compact binary. Multi-byte integers are
**little-endian**. Many characteristics begin with a **flags byte** whose bits
describe which optional fields follow. For example, Heart Rate Measurement:

```
byte 0: flags   (bit0 = value is 16-bit; bit3 = energy present; bit4 = RR present)
byte 1..: heart rate (8- or 16-bit per flags)
       ...optional energy expended (uint16)
       ...optional RR intervals (uint16 each, units of 1/1024 s)
```

Getting this parsing right — respecting flags, advancing offsets only for the
fields actually present — is exactly what the `Profiles/` typed models do.

---

## 2. Core Bluetooth on Apple platforms

Apple exposes BLE through the **Core Bluetooth** framework. The central-role API
centers on two classes:

- **`CBCentralManager`** — scans, connects, and reports Bluetooth power state.
- **`CBPeripheral`** — represents a remote device; discovers services and
  characteristics and performs reads/writes.

Core Bluetooth is **delegate-based and callback-driven**: you call a method
(`connect`, `discoverServices`, `readValue`) and the result arrives later on a
**delegate** method (`didConnect`, `didDiscoverServices`,
`didUpdateValueFor…`), on a dispatch queue you choose. There is no `async`/`await`
in the native API.

### iOS-specific behaviors that make BLE hard

1. **Bluetooth power/authorization state is asynchronous.** You cannot scan until
   `CBCentralManager` reports `.poweredOn`. It starts `.unknown` and transitions
   after init. State can also change at runtime (user toggles Bluetooth, revokes
   permission).

2. **Background execution is restricted.** In the foreground you scan freely; in
   the background iOS throttles scanning, coalesces advertisements, and forbids
   certain operations. Apps must declare the `bluetooth-central` background mode.

3. **The OS can terminate your app** and later **relaunch it in the background**
   to deliver a BLE event. To survive this, you opt into **state restoration**
   with a restore identifier; on relaunch Core Bluetooth calls
   `willRestoreState` and hands back the peripherals your previous process was
   using. This is fiddly and under-documented.

4. **Simultaneous connection limits.** iOS supports only a modest number of
   concurrent BLE connections in practice; apps managing many devices must queue.

5. **No reconnection strategy.** When a peripheral drops, Core Bluetooth simply
   tells you it disconnected. Any retry/backoff logic is yours to build — every
   app reinvents it.

6. **Untestable without hardware.** `CBCentralManager`/`CBPeripheral` cannot be
   subclassed or mocked meaningfully; there is no built-in simulator, so BLE
   logic historically could not be unit-tested.

Points 1–6 are the precise pain points SwiftBLEKit addresses.

---

## 3. The problems SwiftBLEKit solves

| # | Problem | SwiftBLEKit's answer |
| --- | --- | --- |
| 1 | Reconnection is roll-your-own | `ConnectionCoordinator` — a state machine with exponential backoff |
| 2 | State restoration is fiddly | `restorationEvents()` on the abstraction + a reference `LiveCentralManager` implementation |
| 3 | Discovery/subscribe/parse boilerplate | `GATTProfile` declarative DSL |
| 4 | Re-parsing standard characteristics | `Profiles/` typed models (Battery, Heart Rate, …) |
| 5 | **No way to test BLE without hardware** | `MockCentralManager` + `SimulatedPeripheral` behind a protocol seam |
| 6 | Multi-device connection limits | `ConnectionPool` — capped, priority-queued coordination |

The **keystone** is #5. Because everything is written against a protocol instead
of Core Bluetooth directly, the *same* connection/DSL/profile code runs against
real hardware in production and against in-memory fakes in tests.

---

## 4. Architecture: one seam, many layers

The whole design hangs off a single decision: **put a protocol boundary in front
of Core Bluetooth, and build everything on top of that protocol — never on
Core Bluetooth directly.**

```
┌─────────────────────────────────────────────────────────────┐
│  Your app                                                     │
├─────────────────────────────────────────────────────────────┤
│  Pool/         ConnectionPool          (multi-device, v0.5)   │
│  DSL/          GATTProfile, attach()   (declarative, v0.2)    │
│  Profiles/     BatteryLevel, …         (typed models, v0.3)   │
│  Connection/   ConnectionCoordinator   (reconnection, v0.1)   │
│  Restoration/  BLERestorationState     (v0.4)                 │
├─────────────────────────────────────────────────────────────┤
│  Abstraction/  BLECentralManaging, BLEPeripheralProtocol      │ ← the seam
├───────────────────────────────┬───────────────────────────────┤
│  CoreBluetooth/ (production)   │  Testing/ (unit tests)        │
│  LiveCentralManager           │  MockCentralManager           │
│  LivePeripheral               │  SimulatedPeripheral          │
│      │                        │      │                        │
│      ▼                        │      ▼                        │
│  Apple Core Bluetooth         │  in-memory simulation         │
│  (real radio / hardware)      │  (no hardware)                │
└───────────────────────────────┴───────────────────────────────┘
```

Everything **above** the seam depends only on the two protocols. Everything
**below** is a swappable implementation. Production wires in `LiveCentralManager`;
tests wire in `MockCentralManager`. Neither the coordinator, the DSL, the
profiles, nor the pool know or care which one they're talking to.

The layering also mirrors the release history — each version added one layer
without disturbing the ones beneath it:

- **v0.1** — Core connection layer + testable mock abstraction
- **v0.2** — declarative DSL
- **v0.3** — standard GATT profiles (built *on* the DSL)
- **v0.4** — state restoration
- **v0.5** — connection pooling (built *on* the coordinator)

---

## 5. The abstraction boundary

Two protocols define the seam. Both are `Sendable` and use `async`/`await` +
`AsyncStream` — no delegates, no Combine.

### `BLECentralManaging`

The scan/connect/state surface, mirroring `CBCentralManager`:

```swift
public protocol BLECentralManaging: AnyObject, Sendable {
    var state: BLEManagerState { get async }
    func stateUpdates() -> AsyncStream<BLEManagerState>
    func scan(services: [BLEUUID]?) -> AsyncStream<BLEDiscovery>
    func stopScan() async
    func connect(_ peripheral: BLEPeripheralProtocol, timeout: TimeInterval?) async throws
    func disconnect(_ peripheral: BLEPeripheralProtocol) async
    func disconnections() -> AsyncStream<BLEDisconnection>
    func retrievePeripheral(identifier: UUID) async -> BLEPeripheralProtocol?
    func restorationEvents() -> AsyncStream<BLERestorationState>
}
```

### `BLEPeripheralProtocol`

The per-device GATT surface, mirroring `CBPeripheral`:

```swift
public protocol BLEPeripheralProtocol: AnyObject, Sendable {
    var identifier: UUID { get }
    var name: String? { get async }
    func discoverServices(_ services: [BLEUUID]?) async throws -> [BLEUUID]
    func discoverCharacteristics(_ characteristics: [BLEUUID]?, for service: BLEUUID) async throws -> [BLEUUID]
    func readValue(for characteristic: BLEUUID) async throws -> Data
    func writeValue(_ data: Data, for characteristic: BLEUUID, withResponse: Bool) async throws
    func setNotify(_ enabled: Bool, for characteristic: BLEUUID) async throws
    func notifications(for characteristic: BLEUUID) -> AsyncStream<Data>
}
```

**Why this exact shape?**

- **Callbacks → `async`/`await`.** A request that gets one answer (connect, read,
  discover) becomes an `async throws` function. This linearizes the delegate
  dance into readable sequential code.
- **Streams of events → `AsyncStream`.** Things that happen repeatedly
  (discoveries, disconnections, notifications, state changes, restorations) are
  `AsyncStream`s you can `for await` over.
- **Platform-independent value types.** The core deliberately avoids importing
  Core Bluetooth. `BLEUUID` stores a normalized string; `BLEManagerState`
  mirrors `CBManagerState`; `BLEError` captures failures as a plain enum. Only
  the `CoreBluetooth/` adapter imports the framework — so the abstraction (and
  the mock) compile even where Core Bluetooth doesn't.

---

## 6. Layer walkthrough

### Core/ — shared value types

- **`BLEUUID`** — a 16/32/128-bit identifier stored as an uppercased string, with
  the standard assigned numbers (`.heartRate`, `.batteryLevel`, …) as constants.
- **`BLEManagerState`** — `.poweredOn`, `.poweredOff`, `.unauthorized`, …
- **`ConnectionState`** — `.disconnected`, `.scanning`, `.connecting`,
  `.connected`, `.reconnecting(attempt:)`, `.failed(BLEError)`. The state machine
  the coordinator drives.
- **`BLEError`** — typed failures; note `disconnected(isExpected:reason:)`, whose
  `isExpected` flag lets the coordinator tell a user-requested teardown from an
  unexpected drop.
- **`BLEDiscovery` / `AdvertisementData` / `BLEDisconnection`** — event payloads.
- **`ExponentialBackoff`** — a pure value type computing retry delays.

#### `ExponentialBackoff` in detail

The retry schedule is a pure, side-effect-free struct so it can be tested
exhaustively without waiting on real time:

```swift
baseDelay(forAttempt n) = min(initialDelay * multiplier^(n-1), maxDelay)
delay(forAttempt n)     = baseDelay ± (jitter * baseDelay)   // spread out reconnect storms
allowsAttempt(after k)  = (maxAttempts == nil) || k < maxAttempts
```

Jitter randomness is **injectable** (`randomUnit:` defaults to `Double.random`),
so tests pin it to exact values.

### Connection/ — `ConnectionCoordinator`

An **actor** that drives one peripheral through its whole lifecycle and reconnects
automatically. It is written entirely against `BLECentralManaging`, so it's fully
testable.

Its run loop:

```
start()
 └─► state = .connecting
     try central.connect(peripheral, timeout:)
       success → state = .connected → wait for disconnect
                   │
                   ├─ expected disconnect (stop())        → done
                   └─ unexpected drop                      → schedule retry
       failure  → schedule retry
     schedule retry:
       if backoff budget exhausted → state = .failed(.reconnectionExhausted)
       else state = .reconnecting(attempt) → sleep(backoff delay) → loop
```

Two design choices make it deterministically testable:

- **Injectable `sleep`.** The delay primitive is a closure defaulting to
  `Task.sleep`; tests pass `{ _ in }` to collapse backoff to zero.
- **Observes `disconnections()`.** It distinguishes expected vs. unexpected drops
  via `BLEError.disconnected(isExpected:)`, so `stop()` doesn't trigger a reconnect
  but a real drop does.

State transitions are published through `states() -> AsyncStream<ConnectionState>`.

### DSL/ — declarative GATT profiles (v0.2)

A `@resultBuilder` DSL that removes the discover→subscribe→parse boilerplate:

```swift
let profile = GATTProfile {
    service(.heartRate) {
        characteristic(.heartRateMeasurement).notify { data in … }
    }
    service(.batteryService) {
        characteristic(.batteryLevel).read { data in … }
    }
}
let session = try await peripheral.attach(profile)
```

- **`GATTProfile`** holds `[ServiceSpec]`, each holding `[CharacteristicSpec]`,
  built by `ServiceBuilder` / `CharacteristicBuilder`.
- **Fluent operations** — `.read`/`.notify` (raw `Data`) and typed
  `.read(as:)`/`.notify(as:)` which decode via `CharacteristicValue`.
- **`attach(_:)`** (an extension on `BLEPeripheralProtocol`) discovers the named
  services and characteristics, runs each declared read inline, subscribes to each
  declared notification, and returns a **`GATTSession`**.
- **`GATTSession`** owns one `Task` per subscription; cancelling it (or letting it
  deallocate) tears the subscriptions down — RAII for notifications.

Because `attach` only talks to `BLEPeripheralProtocol`, it runs identically
against a real device and against `SimulatedPeripheral`.

### Profiles/ — typed models (v0.3)

Concrete `CharacteristicValue` conformances that decode the standard binary
layouts, plus `StandardProfile` factories that combine them with the DSL:

- `BatteryLevel`, `HeartRateMeasurement`, `BodySensorLocation`,
  `CyclingPowerMeasurement`, `GATTString` (Device Information), `HIDReport`.
- **`ByteReader`** — an internal, bounds-checked, little-endian cursor. It copies
  the payload into `[UInt8]` so `Data`'s non-zero `startIndex` never causes an
  off-by-one, and every read throws on underflow.
- **`StandardProfile.heartRate { … }`** etc. return ready-made `ServiceSpec`s —
  literally "the DSL applied to the models," which is how v0.3 proves v0.2 works.

### Restoration/ — state restoration (v0.4)

- **`BLERestorationState`** — the peripherals (and scan services) iOS hands back
  on a background relaunch.
- **`restorationEvents()`** on the abstraction yields these. `LiveCentralManager`
  translates `willRestoreState` into a `BLERestorationState`, and **buffers** it
  if it arrives before any observer subscribes (it fires very early in relaunch).
- Your app re-creates a `ConnectionCoordinator` per restored peripheral and calls
  `start()` — resuming exactly where the killed process left off.

### Pool/ — connection pool (v0.5)

**`ConnectionPool`** is an actor that manages many peripherals under a concurrency
cap (iOS's practical simultaneous-connection limit):

- Keeps at most `maxConcurrent` `ConnectionCoordinator`s running.
- Extra peripherals wait in a queue; when a slot frees (a managed connection is
  dropped, or its reconnection budget is exhausted → terminal `.failed`), the
  highest-priority waiter is **promoted** and started.
- Publishes `PoolEvent(identifier, state)` across all managed peripherals, plus
  `activeConnections` / `queuedCount` / `state(for:)`.

It observes each coordinator's `states()` stream; on a terminal state it frees the
slot and calls `promoteNext()`.

### CoreBluetooth/ — the production adapter

- **`LiveCentralManager`** — an `NSObject` + `CBCentralManagerDelegate` that
  forwards protocol calls to a real `CBCentralManager` and turns delegate
  callbacks back into continuations and `AsyncStream`s. Supports an optional
  `restoreIdentifier` to enable state restoration.
- **`LivePeripheral`** — the same bridge for `CBPeripheral`/`CBPeripheralDelegate`
  (discover/read/write/notify).
- **`CoreBluetoothBridging`** — conversions between the platform-independent types
  (`BLEUUID`, `BLEManagerState`, `AdvertisementData`) and their `CB…` equivalents.

All of this is wrapped in `#if canImport(CoreBluetooth)` so the rest of the
package builds on platforms without the framework.

### Testing/ — the in-memory doubles

- **`MockCentralManager`** (actor) — register `SimulatedPeripheral`s, then
  `simulateDiscovery`, `simulateDisconnect`, `enqueueConnectBehaviors`
  (`.succeed`/`.fail`/`.timeout`), `simulateState`, and `simulateRestoration`.
- **`SimulatedPeripheral`** (actor) — configurable services/characteristics/values;
  `simulateValue(_:for:)` pushes a notification; `readError`/`writeError` inject
  failures.

These let a test drive the *entire* stack — coordinator reconnection, DSL parsing,
pool scheduling, restoration — with zero hardware and deterministic timing.

---

## 7. Concurrency model

SwiftBLEKit is built on **Swift structured concurrency**, not Combine:

- **Requests → `async`/`await`.** Delegate callbacks are bridged with
  `withCheckedThrowingContinuation`: the request stores a continuation keyed by
  the characteristic/operation, then the delegate method looks it up and
  `resume`s it. (See `LivePeripheral`.)
- **Event streams → `AsyncStream`.** Discoveries, disconnections, notifications,
  state and restoration updates are `AsyncStream`s; observers `for await` them and
  registration is bookkept as an array of continuations.
- **State ownership → actors.** `ConnectionCoordinator`, `ConnectionPool`,
  `MockCentralManager`, and `SimulatedPeripheral` are actors, so their mutable
  state is race-free by construction.
- **The Core Bluetooth bridge is `@unchecked Sendable`.** `CBCentralManager`/
  `CBPeripheral` aren't `Sendable` and their delegates fire on a private dispatch
  queue. `LiveCentralManager`/`LivePeripheral` therefore guard all mutable
  bookkeeping (continuation maps, sink arrays) with an `NSLock` and declare
  `@unchecked Sendable` — a deliberate, contained escape hatch at the one place
  that must interoperate with a non-`Sendable`, callback-based framework.

Why not Combine? The project standard is async/await; `AsyncStream` covers the
publisher use-cases without a dependency, and actors give safer shared-state
semantics than lock-plus-`@Published`.

---

## 8. End-to-end data flows

### Connecting with automatic reconnection (production)

```
app → ConnectionCoordinator.start()
        → BLECentralManaging.connect()            [LiveCentralManager]
            → CBCentralManager.connect()
            ← centralManager(didConnect:)         → resume continuation
        state = .connected
        ← centralManager(didDisconnectPeripheral:, error:)
            → yields BLEDisconnection (isExpected: false)
        coordinator sees unexpected drop
        → state = .reconnecting(1) → sleep(backoff) → connect() again …
```

### Reading a typed characteristic through the DSL

```
peripheral.attach(profile)
  → discoverServices([.heartRate, .batteryService])
  → discoverCharacteristics(...) per service
  → for a .read spec:  readValue(for:) → Data → V(data:) → your handler(value)
  → for a .notify spec: setNotify(true) then Task { for await data in notifications(for:) {
                          → V(data:) → your handler(value) } }
  → returns GATTSession owning those Tasks
```

### The same flow under test (no hardware)

```
SimulatedPeripheral(services:, values:)  ← configured in the test
peripheral.attach(profile)               ← identical call site
peripheral.simulateValue(bytes, for: .heartRateMeasurement)
  → yields into the notification AsyncStream
  → DSL decodes → handler fires → test asserts the parsed value
```

The production and test flows are byte-for-byte the same call sequence; only the
object behind `BLEPeripheralProtocol` differs.

---

## 9. Testing strategy

- **Everything above the seam is unit-tested with the doubles** — no device
  required. The 28-test suite covers the backoff curve, coordinator
  reconnection/failure/stop paths, the mock round-trip, DSL build + attach,
  every profile's byte-parsing (including edge cases like 16-bit HR, RR intervals,
  negative cycling power), restoration delivery, and pool scheduling.
- **Determinism over timing.** Backoff jitter and coordinator `sleep` are
  injectable so tests never wait on real delays. Where an `AsyncStream`
  subscription registers asynchronously, tests wait briefly for registration
  before pushing a value (a property of `AsyncStream`, called out in the tests).
- **The `CoreBluetooth/` adapter is the only part that requires a device** — it is
  intentionally thin, so almost all logic lives in the testable layers.

Framework: **Swift Testing** (`import Testing`, `@Test`, `#expect`).

---

## 10. Build & packaging

- **Swift Package Manager** library, `swift-tools-version: 6.2`.
- Platforms: iOS 13+, macOS 11+, watchOS 6+, tvOS 13+.
- Single product/target `SwiftBLEKit`; the Core Bluetooth adapter is guarded by
  `#if canImport(CoreBluetooth)`.

```swift
.package(url: "https://github.com/DeepakPal25/SwiftBLEKit.git", from: "0.5.0")
```

Then `import SwiftBLEKit`.

---

## Summary

BLE gives you an asynchronous, drop-prone, delegate-driven, hardware-bound world.
SwiftBLEKit tames it by inserting **one protocol seam** over Core Bluetooth and
building a layered, `async`/`await`-native stack on top: automatic reconnection, a
declarative GATT DSL, typed standard-profile models, state restoration, and a
multi-device pool. Because every layer talks to the seam rather than the
framework, the whole thing is unit-testable with in-memory doubles — which is the
single feature that most sets it apart.
