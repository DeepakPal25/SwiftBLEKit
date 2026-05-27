import Foundation
import Testing
@testable import SwiftBLEKit

@Suite("ConnectionPool")
struct ConnectionPoolTests {

    private func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    private func makePool(central: MockCentralManager, max: Int) -> ConnectionPool {
        ConnectionPool(
            central: central,
            maxConcurrent: max,
            backoff: ExponentialBackoff(initialDelay: 0, maxAttempts: 2, jitter: 0),
            connectTimeout: nil,
            sleep: { _ in }
        )
    }

    @Test("Respects the concurrency cap and queues the excess")
    func respectsCap() async {
        let central = MockCentralManager()
        let pool = makePool(central: central, max: 2)

        let peripherals = (0..<3).map { _ in SimulatedPeripheral() }
        for p in peripherals { await central.add(p) }

        await pool.manage(peripherals[0])
        await pool.manage(peripherals[1])
        await pool.manage(peripherals[2])

        // Two connect, one waits.
        #expect(await eventually { await pool.activeConnections == 2 })
        #expect(await pool.queuedCount == 1)

        let connectedCount = await withCheckedContinuation { c in
            Task {
                var n = 0
                for p in peripherals where await pool.state(for: p.identifier) == .connected { n += 1 }
                c.resume(returning: n)
            }
        }
        #expect(connectedCount == 2)
    }

    @Test("Promotes a queued peripheral when a slot frees")
    func promotesOnDrop() async {
        let central = MockCentralManager()
        let pool = makePool(central: central, max: 2)

        let p0 = SimulatedPeripheral()
        let p1 = SimulatedPeripheral()
        let queued = SimulatedPeripheral()
        for p in [p0, p1, queued] { await central.add(p) }

        await pool.manage(p0)
        await pool.manage(p1)
        await pool.manage(queued, priority: 10)   // waits despite high priority (cap full)

        #expect(await eventually { await pool.activeConnections == 2 })
        #expect(await eventually { await pool.state(for: queued.identifier) == .disconnected })

        // Free a slot; the queued peripheral should be promoted and connect.
        await pool.drop(p0.identifier)

        #expect(await eventually { await pool.state(for: queued.identifier) == .connected })
        #expect(await pool.activeConnections == 2)
    }

    @Test("A terminal failure frees the slot for the next peripheral")
    func terminalFailurePromotes() async {
        let central = MockCentralManager()
        let pool = makePool(central: central, max: 1)

        let failing = SimulatedPeripheral()
        let next = SimulatedPeripheral()
        await central.add(failing)
        await central.add(next)

        // First peripheral's connects all fail → coordinator reaches .failed.
        await central.enqueueConnectBehaviors(
            Array(repeating: .fail(.underlying("no route")), count: 6)
        )

        await pool.manage(failing)
        await pool.manage(next)

        // `failing` exhausts its budget and frees the single slot; `next` connects.
        #expect(await eventually { await pool.state(for: next.identifier) == .connected })
    }
}
