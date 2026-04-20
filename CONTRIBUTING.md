# Contributing to SwiftBLEKit

Thanks for your interest in improving SwiftBLEKit! This project's whole premise
is testability, so contributions are held to that standard.

## Ground rules

1. **Everything above the abstraction is tested without hardware.** New logic
   must be exercised against `MockCentralManager` / `SimulatedPeripheral`. If a
   change can only be verified on a physical device, it belongs in
   `CoreBluetooth/` (the thin adapter).
2. **Keep the seam honest.** `BLECentralManaging` and `BLEPeripheralProtocol` are
   the contract both the live and mock implementations satisfy. Add capability to
   the protocol first, then to *both* conformers.
3. **Concurrency, not Combine.** Use `async`/`await` and `AsyncStream`.

## Development

```sh
swift build
swift test
```

Tests use the [Swift Testing](https://developer.apple.com/documentation/testing)
framework (`import Testing`, `@Test`, `#expect`). Prefer deterministic tests —
inject timing (e.g. `ConnectionCoordinator`'s `sleep` closure) rather than
sleeping on real backoff delays.

## Pull requests

- One focused change per PR.
- Add or update tests and `CHANGELOG.md` under **[Unreleased]**.
- Document public API with `///` doc comments.
- Run `swift build` and `swift test` before pushing.

## Style

- PascalCase types, camelCase members, 4-space indentation.
- Avoid force-unwrapping; surface failures as `BLEError`.
- Public API gets doc comments explaining *why*, not just *what*.
