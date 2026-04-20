import Foundation

/// An in-memory peripheral for tests, conforming to ``BLEPeripheralProtocol``.
///
/// Configure its services, characteristic values, and connection behaviour, then
/// hand it to a ``MockCentralManager``. Tests can push characteristic updates,
/// simulate read/write failures, and drive notification streams — all without
/// Core Bluetooth or hardware.
public actor SimulatedPeripheral: BLEPeripheralProtocol {

    public nonisolated let identifier: UUID

    private var _name: String?
    public var name: String? { _name }

    /// serviceUUID -> characteristic UUIDs
    private var services: [BLEUUID: [BLEUUID]]
    /// characteristic UUID -> current value
    private var values: [BLEUUID: Data]
    private var notifying: Set<BLEUUID> = []
    private var notificationContinuations: [BLEUUID: [AsyncStream<Data>.Continuation]] = [:]

    /// An error to throw on the next read, if set.
    public var readError: BLEError?
    /// An error to throw on the next write, if set.
    public var writeError: BLEError?

    public init(
        identifier: UUID = UUID(),
        name: String? = nil,
        services: [BLEUUID: [BLEUUID]] = [:],
        values: [BLEUUID: Data] = [:]
    ) {
        self.identifier = identifier
        self._name = name
        self.services = services
        self.values = values
    }

    // MARK: - Test controls

    /// Sets a characteristic value and pushes it to any active notification
    /// streams (if notifications are enabled), simulating a peripheral update.
    public func simulateValue(_ data: Data, for characteristic: BLEUUID) {
        values[characteristic] = data
        guard notifying.contains(characteristic) else { return }
        for continuation in notificationContinuations[characteristic] ?? [] {
            continuation.yield(data)
        }
    }

    public func setName(_ name: String?) { _name = name }

    // MARK: - BLEPeripheralProtocol

    @discardableResult
    public func discoverServices(_ requested: [BLEUUID]?) async throws -> [BLEUUID] {
        guard let requested else { return Array(services.keys) }
        return requested.filter { services[$0] != nil }
    }

    @discardableResult
    public func discoverCharacteristics(
        _ requested: [BLEUUID]?,
        for service: BLEUUID
    ) async throws -> [BLEUUID] {
        guard let available = services[service] else {
            throw BLEError.serviceNotFound(service)
        }
        guard let requested else { return available }
        return requested.filter { available.contains($0) }
    }

    public func readValue(for characteristic: BLEUUID) async throws -> Data {
        if let readError { self.readError = nil; throw readError }
        guard let value = values[characteristic] else {
            throw BLEError.characteristicNotFound(characteristic)
        }
        return value
    }

    public func writeValue(
        _ data: Data,
        for characteristic: BLEUUID,
        withResponse: Bool
    ) async throws {
        if let writeError { self.writeError = nil; throw writeError }
        values[characteristic] = data
    }

    public func setNotify(_ enabled: Bool, for characteristic: BLEUUID) async throws {
        if enabled { notifying.insert(characteristic) }
        else { notifying.remove(characteristic) }
    }

    public nonisolated func notifications(for characteristic: BLEUUID) -> AsyncStream<Data> {
        AsyncStream { continuation in
            Task { await self.register(continuation, for: characteristic) }
        }
    }

    private func register(_ continuation: AsyncStream<Data>.Continuation, for characteristic: BLEUUID) {
        notificationContinuations[characteristic, default: []].append(continuation)
    }
}
