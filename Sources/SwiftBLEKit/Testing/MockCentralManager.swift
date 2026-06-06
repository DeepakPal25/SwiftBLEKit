import Foundation

/// An in-memory ``BLECentralManaging`` for tests.
///
/// Register ``SimulatedPeripheral`` instances, then simulate discovery,
/// connection failures, and disconnections to exercise the full stack — including
/// the connection coordinator — without any hardware. This is the missing
/// testable Core Bluetooth layer.
public actor MockCentralManager: BLECentralManaging {

    private var _state: BLEManagerState
    public var state: BLEManagerState { _state }

    private var peripherals: [UUID: BLEPeripheralProtocol] = [:]
    private var connected: Set<UUID> = []

    /// How the next connection attempt should behave.
    public enum ConnectBehavior: Sendable {
        case succeed
        case fail(BLEError)
        case timeout
    }

    /// A queue of behaviours applied to successive `connect` calls. When empty,
    /// connections succeed. Push failures to simulate a flaky link.
    private var connectBehaviors: [ConnectBehavior] = []

    private var stateContinuations: [AsyncStream<BLEManagerState>.Continuation] = []
    private var discoveryContinuations: [AsyncStream<BLEDiscovery>.Continuation] = []
    private var disconnectContinuations: [AsyncStream<BLEDisconnection>.Continuation] = []
    private var restorationContinuations: [AsyncStream<BLERestorationState>.Continuation] = []

    public init(state: BLEManagerState = .poweredOn) {
        self._state = state
    }

    // MARK: - Test controls

    /// Registers a peripheral so it can be retrieved and connected.
    public func add(_ peripheral: BLEPeripheralProtocol) {
        peripherals[peripheral.identifier] = peripheral
    }

    /// Changes the central state, notifying observers.
    public func simulateState(_ newState: BLEManagerState) {
        _state = newState
        for continuation in stateContinuations { continuation.yield(newState) }
    }

    /// Emits a discovery event to any active scans.
    public func simulateDiscovery(
        _ peripheral: BLEPeripheralProtocol,
        advertisement: AdvertisementData = AdvertisementData(),
        rssi: Int = -60
    ) {
        add(peripheral)
        let discovery = BLEDiscovery(peripheral: peripheral, advertisement: advertisement, rssi: rssi)
        for continuation in discoveryContinuations { continuation.yield(discovery) }
    }

    /// Forces a disconnection, defaulting to an *unexpected* drop so the
    /// coordinator will attempt to reconnect.
    public func simulateDisconnect(_ peripheral: BLEPeripheralProtocol, expected: Bool = false) {
        connected.remove(peripheral.identifier)
        let error: BLEError = .disconnected(isExpected: expected, reason: expected ? nil : "simulated drop")
        let event = BLEDisconnection(identifier: peripheral.identifier, error: error)
        for continuation in disconnectContinuations { continuation.yield(event) }
    }

    /// Queues behaviours for upcoming `connect` calls.
    public func enqueueConnectBehaviors(_ behaviors: [ConnectBehavior]) {
        connectBehaviors.append(contentsOf: behaviors)
    }

    /// Whether a peripheral is currently considered connected.
    public func isConnected(_ identifier: UUID) -> Bool { connected.contains(identifier) }

    /// Simulates iOS restoring the app with a set of peripherals, as if
    /// `willRestoreState` had fired. The peripherals are registered so they can
    /// be connected.
    public func simulateRestoration(_ peripherals: [BLEPeripheralProtocol], scanServices: [BLEUUID] = []) {
        for peripheral in peripherals { add(peripheral) }
        let restoration = BLERestorationState(peripherals: peripherals, scanServices: scanServices)
        for continuation in restorationContinuations { continuation.yield(restoration) }
    }

    // MARK: - BLECentralManaging

    public nonisolated func stateUpdates() -> AsyncStream<BLEManagerState> {
        AsyncStream { continuation in
            Task { await self.registerStateContinuation(continuation) }
        }
    }

    public nonisolated func scan(services: [BLEUUID]?) -> AsyncStream<BLEDiscovery> {
        AsyncStream { continuation in
            Task { await self.registerDiscoveryContinuation(continuation) }
        }
    }

    public func stopScan() async {
        for continuation in discoveryContinuations { continuation.finish() }
        discoveryContinuations.removeAll()
    }

    public func connect(_ peripheral: BLEPeripheralProtocol, timeout: TimeInterval?) async throws {
        let behavior = connectBehaviors.isEmpty ? .succeed : connectBehaviors.removeFirst()
        switch behavior {
        case .succeed:
            add(peripheral)
            connected.insert(peripheral.identifier)
        case .fail(let error):
            throw error
        case .timeout:
            throw BLEError.connectionTimeout
        }
    }

    public func disconnect(_ peripheral: BLEPeripheralProtocol) async {
        guard connected.remove(peripheral.identifier) != nil else { return }
        let event = BLEDisconnection(
            identifier: peripheral.identifier,
            error: .disconnected(isExpected: true, reason: nil)
        )
        for continuation in disconnectContinuations { continuation.yield(event) }
    }

    public nonisolated func disconnections() -> AsyncStream<BLEDisconnection> {
        AsyncStream { continuation in
            Task { await self.registerDisconnectContinuation(continuation) }
        }
    }

    public func retrievePeripheral(identifier: UUID) async -> BLEPeripheralProtocol? {
        peripherals[identifier]
    }

    public nonisolated func restorationEvents() -> AsyncStream<BLERestorationState> {
        AsyncStream { continuation in
            Task { await self.registerRestorationContinuation(continuation) }
        }
    }

    // MARK: - Continuation registration

    private func registerStateContinuation(_ c: AsyncStream<BLEManagerState>.Continuation) {
        stateContinuations.append(c)
        c.yield(_state)
    }

    private func registerDiscoveryContinuation(_ c: AsyncStream<BLEDiscovery>.Continuation) {
        discoveryContinuations.append(c)
    }

    private func registerDisconnectContinuation(_ c: AsyncStream<BLEDisconnection>.Continuation) {
        disconnectContinuations.append(c)
    }

    private func registerRestorationContinuation(_ c: AsyncStream<BLERestorationState>.Continuation) {
        restorationContinuations.append(c)
    }
}
