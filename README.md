# SwiftBLEKit

**The missing testable Core Bluetooth layer for Apple platforms.**

Core Bluetooth is powerful but low-level: every BLE app re-implements the same
reconnection logic, the same discovery boilerplate, and — worst of all — has no
good way to unit-test any of it without physical hardware. SwiftBLEKit fixes
that, starting from a single insight: **put a clean protocol boundary in front
of `CBCentralManager`/`CBPeripheral`, then build everything else on top of it.**

Because the whole stack talks to that boundary instead of Core Bluetooth
directly, your BLE code becomes ordinary, deterministically testable Swift.

```
SwiftBLEKit/
├── Abstraction/    → BLECentralManaging, BLEPeripheralProtocol   (the seam)
├── Connection/     → ConnectionCoordinator, ExponentialBackoff   (reconnection)
├── CoreBluetooth/  → LiveCentralManager, LivePeripheral          (production adapter)
└── Testing/        → MockCentralManager, SimulatedPeripheral     (in-memory doubles)
```

- **Swift concurrency native** — `async`/`await` and `AsyncStream`, no Combine.
- **Automatic reconnection** — a connection state machine with exponential
  backoff and jitter, driven entirely against the abstraction.
- **Testable end to end** — simulate discovery, connection drops, RSSI changes,
  reads/writes, and notifications in unit tests with zero hardware.

## Requirements

| Platform | Minimum |
| -------- | ------- |
| iOS      | 13.0    |
| macOS    | 11.0    |
| watchOS  | 6.0     |
| tvOS     | 13.0    |
| Swift    | 6.2     |

## Installation

Swift Package Manager. Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/DeepakPal25/SwiftBLEKit.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SwiftBLEKit", package: "SwiftBLEKit"),
        ]
    ),
]
```

Or in Xcode: **File ▸ Add Package Dependencies…** and enter
`https://github.com/DeepakPal25/SwiftBLEKit.git`.

> **Private repository.** Until this package is made public, consumers need
> access to the repo. If Xcode/SPM prompts for credentials over HTTPS, either
> sign in with a GitHub account that has access, or use the SSH URL
> `git@github.com:DeepakPal25/SwiftBLEKit.git` with an SSH key configured for
> GitHub.

Then `import SwiftBLEKit` where you need it.

## Usage

### Reliable connections in production

```swift
import SwiftBLEKit

let central = LiveCentralManager()

// Discover a heart-rate monitor.
for await discovery in central.scan(services: [.heartRate]) {
    let coordinator = ConnectionCoordinator(
        central: central,
        peripheral: discovery.peripheral,
        backoff: ExponentialBackoff(maxAttempts: nil)   // never give up
    )

    // Observe the full lifecycle: .connecting → .connected → .reconnecting → …
    Task {
        for await state in await coordinator.states() {
            print("connection:", state)
        }
    }

    await coordinator.start()
    break
}
```

### Testing without hardware

The same code paths run against in-memory doubles:

```swift
import Testing
@testable import SwiftBLEKit

@Test func reconnectsAfterDrop() async {
    let peripheral = SimulatedPeripheral(
        services: [.heartRate: [.heartRateMeasurement]]
    )
    let central = MockCentralManager()
    await central.add(peripheral)

    let coordinator = ConnectionCoordinator(
        central: central,
        peripheral: peripheral,
        backoff: ExponentialBackoff(initialDelay: 0),
        sleep: { _ in }               // collapse backoff delays in tests
    )
    await coordinator.start()
    // …assert it reaches .connected, simulate a drop, assert it recovers.
    await central.simulateDisconnect(peripheral)
}
```

`ConnectionCoordinator` takes an injectable `sleep` closure, so reconnection
timing is fully deterministic under test — no waiting on real backoff delays.

See [CHANGELOG.md](CHANGELOG.md) for release notes and
[CONTRIBUTING.md](CONTRIBUTING.md) to get involved.

## License

MIT — see [LICENSE](LICENSE).
