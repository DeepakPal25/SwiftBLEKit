// SwiftBLEKit — the missing testable Core Bluetooth layer.
//
// A layered BLE toolkit for Apple platforms:
//
//   • Abstraction — protocol boundary over Core Bluetooth
//     (`BLECentralManaging`, `BLEPeripheralProtocol`)
//   • Connection  — reconnection state machine with exponential backoff
//     (`ConnectionCoordinator`, `ExponentialBackoff`)
//   • CoreBluetooth — the production adapter (`LiveCentralManager`)
//   • Testing     — in-memory doubles (`MockCentralManager`, `SimulatedPeripheral`)
//
// Everything above the abstraction is written against the protocols, so any
// consumer can be unit-tested with the in-memory doubles and no hardware.

/// The library version, matching the current release tag.
public enum SwiftBLEKit {
    public static let version = "0.1.0"
}
