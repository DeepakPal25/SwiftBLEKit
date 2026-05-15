import Foundation
import Testing
@testable import SwiftBLEKit

@Suite("GATT profile DSL")
struct GATTProfileDSLTests {

    /// A tiny typed value to exercise `.notify(as:)` / `.read(as:)`.
    struct BatteryLevel: CharacteristicValue, Equatable {
        let percent: Int
        init(data: Data) throws {
            guard let byte = data.first else { throw BLEError.underlying("empty") }
            percent = Int(byte)
        }
    }

    /// Thread-safe sink for values captured by DSL handlers.
    actor Collector {
        private(set) var notified: [Data] = []
        private(set) var read: [Int] = []
        func addNotified(_ data: Data) { notified.append(data) }
        func addRead(_ value: Int) { read.append(value) }
    }

    private func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    @Test("Builds the declared service/characteristic tree")
    func buildsTree() {
        let profile = GATTProfile {
            service(.heartRate) {
                characteristic(.heartRateMeasurement).notify { _ in }
                characteristic(.bodySensorLocation)
            }
            service(.batteryService) {
                characteristic(.batteryLevel).read { _ in }
            }
        }

        #expect(profile.services.map(\.uuid) == [.heartRate, .batteryService])
        #expect(profile.services[0].characteristics.map(\.uuid) == [.heartRateMeasurement, .bodySensorLocation])
        #expect(profile.services[1].characteristics.map(\.uuid) == [.batteryLevel])
    }

    @Test("attach performs reads and wires notifications")
    func attachReadsAndNotifies() async throws {
        let collector = Collector()
        let peripheral = SimulatedPeripheral(
            services: [
                .heartRate: [.heartRateMeasurement],
                .batteryService: [.batteryLevel],
            ],
            values: [.batteryLevel: Data([0x5A])]   // 90%
        )

        let profile = GATTProfile {
            service(.batteryService) {
                characteristic(.batteryLevel).read(as: BatteryLevel.self) { level in
                    await collector.addRead(level.percent)
                }
            }
            service(.heartRate) {
                characteristic(.heartRateMeasurement).notify { data in
                    await collector.addNotified(data)
                }
            }
        }

        let session = try await peripheral.attach(profile)

        // Read handler fired during attach.
        #expect(await collector.read == [90])

        // Let the notification subscription task register before pushing a value.
        try await Task.sleep(nanoseconds: 100_000_000)
        await peripheral.simulateValue(Data([0x01, 0x48]), for: .heartRateMeasurement)
        #expect(await eventually { await collector.notified == [Data([0x01, 0x48])] })

        session.cancel()
    }

    @Test("attach throws when a declared service is missing")
    func attachThrowsForMissingService() async {
        let peripheral = SimulatedPeripheral(services: [.batteryService: [.batteryLevel]])
        let profile = GATTProfile {
            service(.heartRate) {
                characteristic(.heartRateMeasurement).notify { _ in }
            }
        }

        await #expect(throws: BLEError.self) {
            try await peripheral.attach(profile)
        }
    }
}
