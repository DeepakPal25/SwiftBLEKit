#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth
import Foundation

/// The production ``BLECentralManaging`` backed by a real `CBCentralManager`.
///
/// Bridges Core Bluetooth's delegate model into `async`/`await` and
/// `AsyncStream`. All Core Bluetooth work happens on a dedicated serial queue;
/// internal bookkeeping is guarded by a lock, so the class is safely
/// `@unchecked Sendable`.
public final class LiveCentralManager: NSObject, BLECentralManaging, @unchecked Sendable {

    private let manager: CBCentralManager
    private let queue = DispatchQueue(label: "com.swiftblekit.central")
    private let lock = NSLock()

    private var peripherals: [UUID: LivePeripheral] = [:]
    private var connectContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var timeoutTasks: [UUID: Task<Void, Never>] = [:]

    private var stateSinks: [AsyncStream<BLEManagerState>.Continuation] = []
    private var discoverySinks: [AsyncStream<BLEDiscovery>.Continuation] = []
    private var disconnectSinks: [AsyncStream<BLEDisconnection>.Continuation] = []
    private var restorationSinks: [AsyncStream<BLERestorationState>.Continuation] = []
    /// Buffers a restoration that arrived before any observer subscribed, since
    /// `willRestoreState` fires very early in the relaunch.
    private var pendingRestoration: BLERestorationState?

    /// Creates a live central.
    /// - Parameter restoreIdentifier: Pass a stable identifier to opt into
    ///   Core Bluetooth state restoration.
    public init(restoreIdentifier: String? = nil) {
        var options: [String: Any] = [:]
        if let restoreIdentifier {
            options[CBCentralManagerOptionRestoreIdentifierKey] = restoreIdentifier
        }
        // Delegate is assigned after super.init; CBCentralManager tolerates a
        // nil delegate until the first run-loop turn.
        self.manager = CBCentralManager(delegate: nil, queue: queue, options: options)
        super.init()
        self.manager.delegate = self
    }

    public var state: BLEManagerState {
        get async { lock.guarded { BLEManagerState(manager.state) } }
    }

    private func livePeripheral(for cbPeripheral: CBPeripheral) -> LivePeripheral {
        lock.guarded {
            if let existing = peripherals[cbPeripheral.identifier] { return existing }
            let live = LivePeripheral(cbPeripheral)
            peripherals[cbPeripheral.identifier] = live
            return live
        }
    }

    // MARK: - BLECentralManaging

    public func stateUpdates() -> AsyncStream<BLEManagerState> {
        AsyncStream { continuation in
            let current = lock.guarded { () -> BLEManagerState in
                stateSinks.append(continuation)
                return BLEManagerState(manager.state)
            }
            continuation.yield(current)
        }
    }

    public func scan(services: [BLEUUID]?) -> AsyncStream<BLEDiscovery> {
        AsyncStream { continuation in
            lock.guarded { discoverySinks.append(continuation) }
            manager.scanForPeripherals(withServices: services?.cbUUIDs)
        }
    }

    public func stopScan() async {
        manager.stopScan()
        let sinks = lock.guarded { () -> [AsyncStream<BLEDiscovery>.Continuation] in
            let s = discoverySinks
            discoverySinks.removeAll()
            return s
        }
        for sink in sinks { sink.finish() }
    }

    public func connect(_ peripheral: BLEPeripheralProtocol, timeout: TimeInterval?) async throws {
        guard let live = peripheral as? LivePeripheral,
              let cbPeripheral = lock.guarded({ resolveCBPeripheral(live.identifier) }) else {
            throw BLEError.peripheralNotFound
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.guarded { connectContinuations[live.identifier] = continuation }

            if let timeout {
                let id = live.identifier
                let task = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    self?.failConnect(id, with: .connectionTimeout)
                }
                lock.guarded { timeoutTasks[live.identifier] = task }
            }

            manager.connect(cbPeripheral, options: nil)
        }
    }

    public func disconnect(_ peripheral: BLEPeripheralProtocol) async {
        guard let cbPeripheral = lock.guarded({ resolveCBPeripheral(peripheral.identifier) }) else { return }
        manager.cancelPeripheralConnection(cbPeripheral)
    }

    public func disconnections() -> AsyncStream<BLEDisconnection> {
        AsyncStream { continuation in
            lock.guarded { disconnectSinks.append(continuation) }
        }
    }

    public func retrievePeripheral(identifier: UUID) async -> BLEPeripheralProtocol? {
        guard let cbPeripheral = manager.retrievePeripherals(withIdentifiers: [identifier]).first else {
            return nil
        }
        return livePeripheral(for: cbPeripheral)
    }

    public func restorationEvents() -> AsyncStream<BLERestorationState> {
        AsyncStream { continuation in
            let pending = lock.guarded { () -> BLERestorationState? in
                restorationSinks.append(continuation)
                return pendingRestoration
            }
            // Deliver a restoration that arrived before this subscriber existed.
            if let pending { continuation.yield(pending) }
        }
    }

    // MARK: - Private

    /// Resolves a `CBPeripheral` for a known identifier. Caller holds `lock`.
    private func resolveCBPeripheral(_ identifier: UUID) -> CBPeripheral? {
        manager.retrievePeripherals(withIdentifiers: [identifier]).first
    }

    private func failConnect(_ identifier: UUID, with error: BLEError) {
        let continuation = lock.guarded { () -> CheckedContinuation<Void, Error>? in
            timeoutTasks.removeValue(forKey: identifier)?.cancel()
            return connectContinuations.removeValue(forKey: identifier)
        }
        continuation?.resume(throwing: error)
    }
}

// MARK: - CBCentralManagerDelegate

extension LiveCentralManager: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let (sinks, state) = lock.guarded { (stateSinks, BLEManagerState(central.state)) }
        for sink in sinks { sink.yield(state) }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let live = livePeripheral(for: peripheral)
        let discovery = BLEDiscovery(
            peripheral: live,
            advertisement: AdvertisementData(advertisementData),
            rssi: RSSI.intValue
        )
        let sinks = lock.guarded { discoverySinks }
        for sink in sinks { sink.yield(discovery) }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let continuation = lock.guarded { () -> CheckedContinuation<Void, Error>? in
            timeoutTasks.removeValue(forKey: peripheral.identifier)?.cancel()
            return connectContinuations.removeValue(forKey: peripheral.identifier)
        }
        continuation?.resume()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        failConnect(peripheral.identifier, with: .underlying(error?.localizedDescription ?? "failed to connect"))
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        // A `cancelPeripheralConnection` call yields a nil error → expected drop.
        let bleError: BLEError = .disconnected(
            isExpected: error == nil,
            reason: error?.localizedDescription
        )
        let sinks = lock.guarded { disconnectSinks }
        let event = BLEDisconnection(identifier: peripheral.identifier, error: bleError)
        for sink in sinks { sink.yield(event) }
    }

    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // Re-register restored peripherals so reconnection can target them.
        let restoredCB = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        let peripherals = restoredCB.map { livePeripheral(for: $0) }
        let scanServices = (dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID])?
            .map(BLEUUID.init) ?? []
        let restoration = BLERestorationState(peripherals: peripherals, scanServices: scanServices)

        let sinks = lock.guarded { () -> [AsyncStream<BLERestorationState>.Continuation] in
            pendingRestoration = restoration
            return restorationSinks
        }
        for sink in sinks { sink.yield(restoration) }
    }
}

private extension NSLock {
    func guarded<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}
#endif
