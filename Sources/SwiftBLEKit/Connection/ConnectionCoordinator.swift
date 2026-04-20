import Foundation

/// Drives a single peripheral connection through its full lifecycle, applying
/// automatic reconnection with exponential backoff.
///
/// This is the answer to idea #1 ("reconnection hell"). Point it at a peripheral
/// and observe ``states`` — it handles connecting, detecting unexpected drops,
/// and retrying on a backoff schedule until either it reconnects or the attempt
/// budget is exhausted.
///
/// Because it is written entirely against ``BLECentralManaging`` and takes an
/// injectable `sleep` closure, its behaviour can be tested deterministically
/// with `MockCentralManager` and no real delays.
public actor ConnectionCoordinator {

    private let central: BLECentralManaging
    private let peripheral: BLEPeripheralProtocol
    private let backoff: ExponentialBackoff
    private let connectTimeout: TimeInterval?
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    private var runTask: Task<Void, Never>?
    private var continuation: AsyncStream<ConnectionState>.Continuation?

    public private(set) var state: ConnectionState = .disconnected {
        didSet { continuation?.yield(state) }
    }

    /// Creates a coordinator for one peripheral.
    ///
    /// - Parameters:
    ///   - sleep: The delay primitive, injectable for testing. Defaults to
    ///     `Task.sleep`.
    public init(
        central: BLECentralManaging,
        peripheral: BLEPeripheralProtocol,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        connectTimeout: TimeInterval? = 10,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.central = central
        self.peripheral = peripheral
        self.backoff = backoff
        self.connectTimeout = connectTimeout
        self.sleep = sleep
    }

    /// A stream of connection-state transitions, starting with the current state.
    public func states() -> AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(state)
        }
    }

    /// Begins connecting and keeps the peripheral connected, reconnecting on
    /// unexpected drops until the backoff budget is exhausted.
    public func start() {
        guard runTask == nil else { return }
        runTask = Task { await self.run() }
    }

    /// Stops managing the connection and disconnects. This is treated as an
    /// expected teardown and does not trigger reconnection.
    public func stop() async {
        runTask?.cancel()
        runTask = nil
        await central.disconnect(peripheral)
        state = .disconnected
    }

    // MARK: - Run loop

    private func run() async {
        var completedAttempts = 0

        while !Task.isCancelled {
            // Attempt (re)connection.
            state = completedAttempts == 0 ? .connecting : .reconnecting(attempt: completedAttempts)

            do {
                try await central.connect(peripheral, timeout: connectTimeout)
            } catch is CancellationError {
                return
            } catch {
                completedAttempts += 1
                if await !scheduleRetry(after: completedAttempts, lastError: error) { return }
                continue
            }

            // Connected. Reset the backoff budget and wait for a drop.
            completedAttempts = 0
            state = .connected

            let drop = await waitForUnexpectedDisconnect()
            if drop == nil { return } // expected teardown or cancellation

            completedAttempts += 1
            if await !scheduleRetry(after: completedAttempts, lastError: nil) { return }
        }
    }

    /// Waits for the peripheral to drop. Returns the disconnection if it was
    /// unexpected (reconnect), or `nil` if it was expected/cancelled (stop).
    private func waitForUnexpectedDisconnect() async -> BLEDisconnection? {
        for await event in central.disconnections() {
            guard event.identifier == peripheral.identifier else { continue }
            if case .disconnected(isExpected: true, _)? = event.error { return nil }
            return event
        }
        return nil
    }

    /// Applies the backoff delay before the next attempt. Returns `false` (and
    /// transitions to `.failed`) when the budget is exhausted or cancelled.
    private func scheduleRetry(after completedAttempts: Int, lastError: Error?) async -> Bool {
        guard backoff.allowsAttempt(after: completedAttempts - 1) else {
            state = .failed(.reconnectionExhausted(attempts: completedAttempts))
            return false
        }

        state = .reconnecting(attempt: completedAttempts)
        let delay = backoff.delay(forAttempt: completedAttempts)
        do {
            try await sleep(delay)
        } catch {
            state = .disconnected
            return false
        }
        return !Task.isCancelled
    }
}
