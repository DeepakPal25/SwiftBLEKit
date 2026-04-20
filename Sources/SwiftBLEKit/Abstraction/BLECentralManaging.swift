import Foundation

/// The abstraction boundary over `CBCentralManager`.
///
/// This is the seam SwiftBLEKit is built around. The production implementation
/// (`LiveCentralManager`) forwards to Core Bluetooth; the test implementation
/// (`MockCentralManager`) simulates peripherals, drops, and RSSI changes in
/// memory. Anything written against this protocol can be exercised in unit tests
/// with zero hardware.
public protocol BLECentralManaging: AnyObject, Sendable {

    /// The current power/authorization state.
    var state: BLEManagerState { get async }

    /// A stream of state changes, beginning with the current state.
    func stateUpdates() -> AsyncStream<BLEManagerState>

    /// Scans for peripherals advertising any of `services` (or all, if `nil`).
    /// The scan runs until the stream is cancelled or ``stopScan()`` is called.
    func scan(services: [BLEUUID]?) -> AsyncStream<BLEDiscovery>

    /// Stops any in-flight scan.
    func stopScan() async

    /// Attempts to connect to a peripheral.
    /// - Parameter timeout: Fails with ``BLEError/connectionTimeout`` if the
    ///   connection is not established in time. `nil` waits indefinitely.
    func connect(_ peripheral: BLEPeripheralProtocol, timeout: TimeInterval?) async throws

    /// Cancels a connection or a pending connection attempt.
    func disconnect(_ peripheral: BLEPeripheralProtocol) async

    /// A stream of disconnection events for all peripherals.
    func disconnections() -> AsyncStream<BLEDisconnection>

    /// Retrieves a known peripheral by identifier without scanning — the basis
    /// for reconnecting to a remembered accessory.
    func retrievePeripheral(identifier: UUID) async -> BLEPeripheralProtocol?
}
