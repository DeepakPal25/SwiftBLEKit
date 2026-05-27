import Foundation
import Testing
@testable import SwiftBLEKit

@Suite("State restoration")
struct StateRestorationTests {

    actor Sink {
        private(set) var restored: [UUID] = []
        func add(_ ids: [UUID]) { restored.append(contentsOf: ids) }
    }

    private func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    @Test("Restoration delivers peripherals to an observer")
    func deliversRestoredPeripherals() async {
        let central = MockCentralManager()
        let sink = Sink()

        let observer = Task {
            for await restoration in central.restorationEvents() {
                await sink.add(restoration.peripherals.map(\.identifier))
            }
        }

        // Let the observer subscribe before restoration fires.
        try? await Task.sleep(nanoseconds: 50_000_000)

        let p1 = SimulatedPeripheral(name: "A")
        let p2 = SimulatedPeripheral(name: "B")
        await central.simulateRestoration([p1, p2])

        #expect(await eventually { await sink.restored == [p1.identifier, p2.identifier] })
        observer.cancel()
    }

    @Test("Restored peripherals are registered and reconnectable")
    func restoredPeripheralsAreConnectable() async throws {
        let central = MockCentralManager()
        let peripheral = SimulatedPeripheral(name: "Remembered")

        await central.simulateRestoration([peripheral])

        // The mock now knows the peripheral without a scan.
        let retrieved = await central.retrievePeripheral(identifier: peripheral.identifier)
        #expect(retrieved != nil)

        // And a coordinator can resume management of it.
        let coordinator = ConnectionCoordinator(
            central: central,
            peripheral: peripheral,
            backoff: ExponentialBackoff(initialDelay: 0),
            connectTimeout: nil,
            sleep: { _ in }
        )
        await coordinator.start()
        #expect(await eventually { await coordinator.state == .connected })
        await coordinator.stop()
    }
}
