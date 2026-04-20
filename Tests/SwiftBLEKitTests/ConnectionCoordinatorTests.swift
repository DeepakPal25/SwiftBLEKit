import Foundation
import Testing
@testable import SwiftBLEKit

@Suite("ConnectionCoordinator")
struct ConnectionCoordinatorTests {

    /// Polls an async condition, succeeding as soon as it holds.
    private func eventually(
        _ condition: @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    @Test("Connects, then reconnects after an unexpected drop")
    func reconnectsAfterDrop() async {
        let peripheral = SimulatedPeripheral()
        let central = MockCentralManager()
        await central.add(peripheral)

        let coordinator = ConnectionCoordinator(
            central: central,
            peripheral: peripheral,
            backoff: ExponentialBackoff(initialDelay: 0, maxAttempts: 5, jitter: 0),
            connectTimeout: nil,
            sleep: { _ in }          // no real delay in tests
        )

        await coordinator.start()
        #expect(await eventually { await coordinator.state == .connected })

        // Let the coordinator subscribe to disconnections before we drop it.
        try? await Task.sleep(nanoseconds: 50_000_000)
        await central.simulateDisconnect(peripheral)   // unexpected → should reconnect

        #expect(await eventually { await coordinator.state == .connected })
        await coordinator.stop()
    }

    @Test("Fails after exhausting the reconnection budget")
    func failsWhenBudgetExhausted() async {
        let peripheral = SimulatedPeripheral()
        let central = MockCentralManager()
        await central.add(peripheral)
        await central.enqueueConnectBehaviors(
            Array(repeating: .fail(.underlying("no route")), count: 6)
        )

        let coordinator = ConnectionCoordinator(
            central: central,
            peripheral: peripheral,
            backoff: ExponentialBackoff(initialDelay: 0, maxAttempts: 2, jitter: 0),
            connectTimeout: nil,
            sleep: { _ in }
        )

        await coordinator.start()

        let failed = await eventually {
            if case .failed = await coordinator.state { return true }
            return false
        }
        #expect(failed)
    }

    @Test("A user-requested stop does not trigger reconnection")
    func stopIsExpected() async {
        let peripheral = SimulatedPeripheral()
        let central = MockCentralManager()
        await central.add(peripheral)

        let coordinator = ConnectionCoordinator(
            central: central,
            peripheral: peripheral,
            backoff: ExponentialBackoff(initialDelay: 0, jitter: 0),
            connectTimeout: nil,
            sleep: { _ in }
        )

        await coordinator.start()
        #expect(await eventually { await coordinator.state == .connected })

        await coordinator.stop()
        #expect(await coordinator.state == .disconnected)
    }
}
