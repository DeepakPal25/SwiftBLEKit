import Foundation

/// The peripherals Core Bluetooth handed back when it relaunched the app for a
/// Bluetooth event, delivered via ``BLECentralManaging/restorationEvents()``.
///
/// State restoration is notoriously fiddly: iOS can terminate your app and later
/// wake it in the background, expecting you to pick up the peripherals you were
/// using. Observe this and re-establish management for each peripheral — the
/// coordinator will resume its connection lifecycle from wherever it left off.
///
/// ```swift
/// let central = LiveCentralManager(restoreIdentifier: "com.example.central")
///
/// for await restoration in central.restorationEvents() {
///     for peripheral in restoration.peripherals {
///         let coordinator = ConnectionCoordinator(central: central, peripheral: peripheral)
///         await coordinator.start()
///     }
/// }
/// ```
public struct BLERestorationState: Sendable {
    /// Peripherals the previous process had connected or was connecting to.
    public let peripherals: [BLEPeripheralProtocol]

    /// Service UUIDs the previous process was scanning for, if any.
    public let scanServices: [BLEUUID]

    public init(peripherals: [BLEPeripheralProtocol], scanServices: [BLEUUID] = []) {
        self.peripherals = peripherals
        self.scanServices = scanServices
    }
}
