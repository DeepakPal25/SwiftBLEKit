import Foundation
import Testing
@testable import SwiftBLEKit

@Suite("Mock BLE layer")
struct MockCentralManagerTests {

    @Test("Discovery, connect, read, and notify round-trip in memory")
    func fullRoundTrip() async throws {
        let peripheral = SimulatedPeripheral(
            name: "HR Strap",
            services: [.heartRate: [.heartRateMeasurement]],
            values: [.heartRateMeasurement: Data([0x00, 0x50])]
        )
        let central = MockCentralManager()
        await central.add(peripheral)

        try await central.connect(peripheral, timeout: nil)
        #expect(await central.isConnected(peripheral.identifier))

        try await peripheral.discoverServices(nil)
        let chars = try await peripheral.discoverCharacteristics(nil, for: .heartRate)
        #expect(chars == [.heartRateMeasurement])

        let value = try await peripheral.readValue(for: .heartRateMeasurement)
        #expect(value == Data([0x00, 0x50]))
    }

    @Test("Notifications deliver simulated updates")
    func notificationsDeliver() async throws {
        let peripheral = SimulatedPeripheral(services: [.heartRate: [.heartRateMeasurement]])
        try await peripheral.setNotify(true, for: .heartRateMeasurement)

        let stream = peripheral.notifications(for: .heartRateMeasurement)
        var iterator = stream.makeAsyncIterator()

        // Give the stream's registration task a moment to attach.
        try await Task.sleep(nanoseconds: 50_000_000)
        await peripheral.simulateValue(Data([0x42]), for: .heartRateMeasurement)

        let received = await iterator.next()
        #expect(received == Data([0x42]))
    }

    @Test("Queued connect behaviours simulate a flaky link")
    func flakyConnect() async {
        let peripheral = SimulatedPeripheral()
        let central = MockCentralManager()
        await central.enqueueConnectBehaviors([.fail(.connectionTimeout), .succeed])

        await #expect(throws: BLEError.self) {
            try await central.connect(peripheral, timeout: nil)
        }
        // Second attempt is configured to succeed.
        try? await central.connect(peripheral, timeout: nil)
        #expect(await central.isConnected(peripheral.identifier))
    }
}
