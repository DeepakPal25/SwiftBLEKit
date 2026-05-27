import Foundation
import Testing
@testable import SwiftBLEKit

@Suite("Standard GATT profiles")
struct ProfilesTests {

    @Test("Battery level parses a single percent byte")
    func batteryLevel() throws {
        #expect(try BatteryLevel(data: Data([0x5A])).percent == 90)
        #expect(try BatteryLevel(data: Data([0x00])).percent == 0)
        #expect(throws: BLEError.self) { try BatteryLevel(data: Data()) }
    }

    @Test("Heart rate: 8-bit value, no optional fields")
    func heartRate8Bit() throws {
        let m = try HeartRateMeasurement(data: Data([0x00, 0x50]))
        #expect(m.beatsPerMinute == 80)
        #expect(m.energyExpended == nil)
        #expect(m.rrIntervals.isEmpty)
        #expect(m.sensorContactSupported == false)
    }

    @Test("Heart rate: 16-bit value")
    func heartRate16Bit() throws {
        // flags 0x01 → uint16; value 0x0140 LE = 320
        let m = try HeartRateMeasurement(data: Data([0x01, 0x40, 0x01]))
        #expect(m.beatsPerMinute == 320)
    }

    @Test("Heart rate: energy expended and RR intervals")
    func heartRateEnergyAndRR() throws {
        // flags 0x18 → energy(0x08) + RR(0x10); HR 0x50=80;
        // energy 0x0064=100; RR 0x0400=1024 → 1.0s
        let m = try HeartRateMeasurement(data: Data([0x18, 0x50, 0x64, 0x00, 0x00, 0x04]))
        #expect(m.beatsPerMinute == 80)
        #expect(m.energyExpended == 100)
        #expect(m.rrIntervals == [1.0])
    }

    @Test("Heart rate: sensor contact detected")
    func heartRateContact() throws {
        // flags 0x06 → contact bits 0b11 (supported + detected)
        let m = try HeartRateMeasurement(data: Data([0x06, 0x4B]))
        #expect(m.sensorContactSupported)
        #expect(m.sensorContactDetected == true)
        #expect(m.beatsPerMinute == 75)
    }

    @Test("Body sensor location maps known and unknown codes")
    func bodySensorLocation() throws {
        #expect(try BodySensorLocation(data: Data([0x01])) == .chest)
        #expect(try BodySensorLocation(data: Data([0x02])) == .wrist)
        #expect(try BodySensorLocation(data: Data([0x99])) == .unknown)
    }

    @Test("Device information strings decode UTF-8")
    func deviceInfoStrings() throws {
        let data = Data("Acme Inc.".utf8)
        #expect(try GATTString(data: data).value == "Acme Inc.")
    }

    @Test("Cycling power: mandatory power, optional balance")
    func cyclingPower() throws {
        // flags 0x0000, power 0x00C8 = 200 W
        let p1 = try CyclingPowerMeasurement(data: Data([0x00, 0x00, 0xC8, 0x00]))
        #expect(p1.instantaneousPower == 200)
        #expect(p1.pedalPowerBalance == nil)

        // flags 0x0001 → balance present; balance 0x64 = 100 → 50%
        let p2 = try CyclingPowerMeasurement(data: Data([0x01, 0x00, 0xC8, 0x00, 0x64]))
        #expect(p2.instantaneousPower == 200)
        #expect(p2.pedalPowerBalance == 50.0)
    }

    @Test("Cycling power: negative instantaneous power")
    func cyclingPowerNegative() throws {
        // power 0xFFFF = -1 W (sint16)
        let p = try CyclingPowerMeasurement(data: Data([0x00, 0x00, 0xFF, 0xFF]))
        #expect(p.instantaneousPower == -1)
    }

    @Test("HID report surfaces raw bytes")
    func hidReport() throws {
        let bytes = Data([0x01, 0x02, 0x03])
        #expect(try HIDReport(data: bytes).bytes == bytes)
    }

    // MARK: - DSL integration

    actor Sink {
        private(set) var bpms: [Int] = []
        func add(_ bpm: Int) { bpms.append(bpm) }
    }

    private func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    @Test("StandardProfile.heartRate parses notifications through the DSL")
    func standardProfileIntegration() async throws {
        let sink = Sink()
        let peripheral = SimulatedPeripheral(
            services: [.heartRate: [.heartRateMeasurement]]
        )

        let profile = GATTProfile {
            StandardProfile.heartRate { measurement in
                await sink.add(measurement.beatsPerMinute)
            }
        }

        let session = try await peripheral.attach(profile)
        try await Task.sleep(nanoseconds: 100_000_000)   // let subscription register

        await peripheral.simulateValue(Data([0x00, 0x4B]), for: .heartRateMeasurement) // 75 bpm
        #expect(await eventually { await sink.bpms == [75] })

        session.cancel()
    }
}
