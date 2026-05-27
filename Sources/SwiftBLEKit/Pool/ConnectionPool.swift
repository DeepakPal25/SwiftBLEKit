import Foundation

/// A state change for one peripheral managed by a ``ConnectionPool``.
public struct PoolEvent: Sendable, Equatable {
    public let identifier: UUID
    public let state: ConnectionState
}

/// Coordinates many simultaneous peripheral connections under a practical
/// concurrency cap.
///
/// iOS tolerates only a limited number of simultaneous BLE connections, so apps
/// managing many devices (IoT, fitness, smart home) need to queue the excess.
/// `ConnectionPool` keeps at most `maxConcurrent` ``ConnectionCoordinator``s
/// running; additional peripherals wait in a priority queue and are promoted as
/// slots free up (when a managed connection is dropped or its reconnection
/// budget is exhausted).
///
/// It is written entirely against ``BLECentralManaging``, so its scheduling can
/// be tested deterministically with `MockCentralManager`.
public actor ConnectionPool {

    private let central: BLECentralManaging
    private let maxConcurrent: Int
    private let backoff: ExponentialBackoff
    private let connectTimeout: TimeInterval?
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    private struct Entry {
        let peripheral: BLEPeripheralProtocol
        let priority: Int
        var coordinator: ConnectionCoordinator?
        var observer: Task<Void, Never>?
        var state: ConnectionState
    }

    private var entries: [UUID: Entry] = [:]
    private var waiting: [UUID] = []
    private var activeCount = 0
    private var continuation: AsyncStream<PoolEvent>.Continuation?

    public init(
        central: BLECentralManaging,
        maxConcurrent: Int = 4,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        connectTimeout: TimeInterval? = 10,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.central = central
        self.maxConcurrent = max(1, maxConcurrent)
        self.backoff = backoff
        self.connectTimeout = connectTimeout
        self.sleep = sleep
    }

    // MARK: - Observation

    /// A stream of connection-state changes across all managed peripherals.
    public func events() -> AsyncStream<PoolEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    /// The number of peripherals with an active connection slot.
    public var activeConnections: Int { activeCount }

    /// The number of peripherals waiting for a free slot.
    public var queuedCount: Int { waiting.count }

    /// The current connection state of a managed peripheral, if any.
    public func state(for identifier: UUID) -> ConnectionState? {
        entries[identifier]?.state
    }

    // MARK: - Management

    /// Begins managing `peripheral`. If a slot is free it connects immediately;
    /// otherwise it waits, and higher `priority` values are promoted first.
    public func manage(_ peripheral: BLEPeripheralProtocol, priority: Int = 0) {
        let id = peripheral.identifier
        guard entries[id] == nil else { return }

        entries[id] = Entry(peripheral: peripheral, priority: priority, state: .disconnected)

        if activeCount < maxConcurrent {
            activate(id)
        } else {
            waiting.append(id)
        }
    }

    /// Stops managing a peripheral, disconnecting it and freeing its slot for a
    /// queued peripheral.
    public func drop(_ identifier: UUID) async {
        guard let entry = entries[identifier] else { return }
        entry.observer?.cancel()
        if let coordinator = entry.coordinator {
            await coordinator.stop()
            activeCount -= 1
        }
        waiting.removeAll { $0 == identifier }
        entries[identifier] = nil
        promoteNext()
    }

    /// Stops managing every peripheral.
    public func stopAll() async {
        for id in entries.keys {
            await drop(id)
        }
    }

    // MARK: - Scheduling

    private func activate(_ id: UUID) {
        guard var entry = entries[id] else { return }

        let coordinator = ConnectionCoordinator(
            central: central,
            peripheral: entry.peripheral,
            backoff: backoff,
            connectTimeout: connectTimeout,
            sleep: sleep
        )
        entry.coordinator = coordinator
        activeCount += 1

        let observer = Task { [weak self] in
            for await state in await coordinator.states() {
                await self?.handleStateChange(id: id, state: state)
            }
        }
        entry.observer = observer
        entries[id] = entry

        Task { await coordinator.start() }
    }

    private func handleStateChange(id: UUID, state: ConnectionState) {
        guard entries[id] != nil else { return }
        entries[id]?.state = state
        continuation?.yield(PoolEvent(identifier: id, state: state))

        if state.isTerminal {
            finishActive(id)
        }
    }

    /// A coordinator reached a terminal state; retire it and free its slot.
    private func finishActive(_ id: UUID) {
        guard var entry = entries[id], entry.coordinator != nil else { return }
        entry.observer?.cancel()
        entry.observer = nil
        entry.coordinator = nil
        entries[id] = entry
        activeCount -= 1
        promoteNext()
    }

    private func promoteNext() {
        guard activeCount < maxConcurrent, !waiting.isEmpty else { return }
        // Highest priority first; ties break by insertion order.
        guard let nextIndex = waiting.indices.max(by: {
            (entries[waiting[$0]]?.priority ?? 0) < (entries[waiting[$1]]?.priority ?? 0)
        }) else { return }
        let nextId = waiting.remove(at: nextIndex)
        activate(nextId)
    }
}
