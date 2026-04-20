#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth
import Foundation

/// The production ``BLEPeripheralProtocol`` backed by a real `CBPeripheral`.
///
/// Bridges Core Bluetooth's delegate callbacks into `async`/`await` and
/// `AsyncStream`. Internal mutable state is guarded by a lock and the class is
/// `@unchecked Sendable`; Core Bluetooth callbacks arrive on the central's
/// dispatch queue.
final class LivePeripheral: NSObject, BLEPeripheralProtocol, @unchecked Sendable {

    let identifier: UUID
    private let peripheral: CBPeripheral

    private let lock = NSLock()
    private var serviceContinuation: CheckedContinuation<[BLEUUID], Error>?
    private var characteristicContinuations: [BLEUUID: CheckedContinuation<[BLEUUID], Error>] = [:]
    private var readContinuations: [BLEUUID: [CheckedContinuation<Data, Error>]] = [:]
    private var writeContinuations: [BLEUUID: [CheckedContinuation<Void, Error>]] = [:]
    private var notifyContinuations: [BLEUUID: CheckedContinuation<Void, Error>] = [:]
    private var notificationSinks: [BLEUUID: [AsyncStream<Data>.Continuation]] = [:]

    init(_ peripheral: CBPeripheral) {
        self.identifier = peripheral.identifier
        self.peripheral = peripheral
        super.init()
        peripheral.delegate = self
    }

    var name: String? {
        get async { lock.guarded { peripheral.name } }
    }

    // MARK: - Lookup helpers

    private func characteristic(_ uuid: BLEUUID) -> CBCharacteristic? {
        for service in peripheral.services ?? [] {
            if let match = service.characteristics?.first(where: { BLEUUID($0.uuid) == uuid }) {
                return match
            }
        }
        return nil
    }

    private func service(_ uuid: BLEUUID) -> CBService? {
        peripheral.services?.first { BLEUUID($0.uuid) == uuid }
    }

    // MARK: - BLEPeripheralProtocol

    @discardableResult
    func discoverServices(_ services: [BLEUUID]?) async throws -> [BLEUUID] {
        try await withCheckedThrowingContinuation { continuation in
            lock.guarded { serviceContinuation = continuation }
            peripheral.discoverServices(services?.cbUUIDs)
        }
    }

    @discardableResult
    func discoverCharacteristics(_ characteristics: [BLEUUID]?, for service: BLEUUID) async throws -> [BLEUUID] {
        guard let cbService = self.service(service) else { throw BLEError.serviceNotFound(service) }
        return try await withCheckedThrowingContinuation { continuation in
            lock.guarded { characteristicContinuations[service] = continuation }
            peripheral.discoverCharacteristics(characteristics?.cbUUIDs, for: cbService)
        }
    }

    func readValue(for characteristic: BLEUUID) async throws -> Data {
        guard let cbChar = self.characteristic(characteristic) else {
            throw BLEError.characteristicNotFound(characteristic)
        }
        return try await withCheckedThrowingContinuation { continuation in
            lock.guarded { readContinuations[characteristic, default: []].append(continuation) }
            peripheral.readValue(for: cbChar)
        }
    }

    func writeValue(_ data: Data, for characteristic: BLEUUID, withResponse: Bool) async throws {
        guard let cbChar = self.characteristic(characteristic) else {
            throw BLEError.characteristicNotFound(characteristic)
        }
        if withResponse {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.guarded { writeContinuations[characteristic, default: []].append(continuation) }
                peripheral.writeValue(data, for: cbChar, type: .withResponse)
            }
        } else {
            peripheral.writeValue(data, for: cbChar, type: .withoutResponse)
        }
    }

    func setNotify(_ enabled: Bool, for characteristic: BLEUUID) async throws {
        guard let cbChar = self.characteristic(characteristic) else {
            throw BLEError.characteristicNotFound(characteristic)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.guarded { notifyContinuations[characteristic] = continuation }
            peripheral.setNotifyValue(enabled, for: cbChar)
        }
    }

    func notifications(for characteristic: BLEUUID) -> AsyncStream<Data> {
        AsyncStream { continuation in
            lock.guarded { notificationSinks[characteristic, default: []].append(continuation) }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension LivePeripheral: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let continuation = lock.guarded { serviceContinuation.take() }
        if let error { continuation?.resume(throwing: BLEError.underlying(error.localizedDescription)) }
        else { continuation?.resume(returning: (peripheral.services ?? []).map { BLEUUID($0.uuid) }) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let key = BLEUUID(service.uuid)
        let continuation = lock.guarded { characteristicContinuations.removeValue(forKey: key) }
        if let error { continuation?.resume(throwing: BLEError.underlying(error.localizedDescription)) }
        else { continuation?.resume(returning: (service.characteristics ?? []).map { BLEUUID($0.uuid) }) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let key = BLEUUID(characteristic.uuid)
        let value = characteristic.value ?? Data()

        let (reads, sinks) = lock.guarded {
            (readContinuations.removeValue(forKey: key) ?? [], notificationSinks[key] ?? [])
        }

        if let error {
            let bleError = BLEError.underlying(error.localizedDescription)
            for read in reads { read.resume(throwing: bleError) }
        } else {
            for read in reads { read.resume(returning: value) }
            for sink in sinks { sink.yield(value) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let key = BLEUUID(characteristic.uuid)
        let writes = lock.guarded { writeContinuations.removeValue(forKey: key) ?? [] }
        if let error {
            let bleError = BLEError.underlying(error.localizedDescription)
            for write in writes { write.resume(throwing: bleError) }
        } else {
            for write in writes { write.resume() }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let key = BLEUUID(characteristic.uuid)
        let continuation = lock.guarded { notifyContinuations.removeValue(forKey: key) }
        if let error { continuation?.resume(throwing: BLEError.underlying(error.localizedDescription)) }
        else { continuation?.resume() }
    }
}

// MARK: - Small conveniences

private extension Optional {
    /// Atomically reads and clears an optional held under a lock.
    mutating func take() -> Wrapped? {
        defer { self = nil }
        return self
    }
}

private extension NSLock {
    func guarded<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}
#endif
