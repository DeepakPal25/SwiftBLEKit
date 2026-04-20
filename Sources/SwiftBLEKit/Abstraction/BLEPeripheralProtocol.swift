import Foundation

/// The abstraction boundary over `CBPeripheral`.
///
/// Every layer above — including the connection coordinator — talks to this
/// protocol, never to Core Bluetooth directly. That single indirection is what
/// makes the whole stack testable: the live adapter wraps `CBPeripheral`, and
/// the test double (`SimulatedPeripheral`) implements the same surface with no
/// hardware involved.
public protocol BLEPeripheralProtocol: AnyObject, Sendable {

    /// The stable system identifier for this peripheral.
    var identifier: UUID { get }

    /// The most recently known advertised or GATT name, if any.
    var name: String? { get async }

    /// Discovers services, optionally filtered to `services`.
    /// - Returns: The UUIDs of the services now available.
    @discardableResult
    func discoverServices(_ services: [BLEUUID]?) async throws -> [BLEUUID]

    /// Discovers characteristics for a previously discovered service.
    /// - Returns: The UUIDs of the characteristics now available.
    @discardableResult
    func discoverCharacteristics(
        _ characteristics: [BLEUUID]?,
        for service: BLEUUID
    ) async throws -> [BLEUUID]

    /// Reads the current value of a characteristic.
    func readValue(for characteristic: BLEUUID) async throws -> Data

    /// Writes to a characteristic, optionally awaiting the peripheral's response.
    func writeValue(
        _ data: Data,
        for characteristic: BLEUUID,
        withResponse: Bool
    ) async throws

    /// Enables or disables notifications for a characteristic.
    func setNotify(_ enabled: Bool, for characteristic: BLEUUID) async throws

    /// A stream of notification/indication values for a characteristic.
    ///
    /// The caller is responsible for having enabled notifications via
    /// ``setNotify(_:for:)``.
    func notifications(for characteristic: BLEUUID) -> AsyncStream<Data>
}
