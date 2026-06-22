import Foundation
import SwiftBLEKit

// A self-contained demo of the whole SwiftBLEKit stack running with **no
// hardware**: it wires a simulated heart-rate strap into the connection
// coordinator and the declarative GATT profile DSL, then streams fake readings.
//
// Run it with:  swift run HeartRateDemo
//
// This is the same code you would write against a real device — only the object
// behind `BLEPeripheralProtocol` differs (here `SimulatedPeripheral`, in an app
// `LiveCentralManager`'s `LivePeripheral`).
@main
struct HeartRateDemo {
    static func main() async {
        print("SwiftBLEKit demo — simulated heart-rate monitor (no hardware)\n")

        // 1. Build an in-memory peripheral advertising Heart Rate + Battery.
        let strap = SimulatedPeripheral(
            name: "Demo HR Strap",
            services: [
                .heartRate: [.heartRateMeasurement],
                .batteryService: [.batteryLevel],
            ]
        )
        let central = MockCentralManager()
        await central.add(strap)

        // 2. Manage the connection with automatic reconnection.
        let coordinator = ConnectionCoordinator(central: central, peripheral: strap)
        await coordinator.start()
        print("• connecting…")

        // 3. Declaratively describe what we care about; parsing is automatic.
        let profile = GATTProfile {
            StandardProfile.heartRate { measurement in
                print("  ♥︎ \(measurement.beatsPerMinute) bpm")
            }
            StandardProfile.battery { battery in
                print("  🔋 \(battery.percent)%")
            }
        }
        let session = try? await strap.attach(profile)

        // Let the notification subscriptions register.
        try? await Task.sleep(nanoseconds: 200_000_000)
        print("• connected, streaming readings:\n")

        // 4. Simulate the peripheral pushing values over the air.
        await strap.simulateValue(Data([0x5A]), for: .batteryLevel) // 90%
        for bpm in [72, 74, 78, 81, 76, 73] {
            await strap.simulateValue(Data([0x00, UInt8(bpm)]), for: .heartRateMeasurement)
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        session?.cancel()
        await coordinator.stop()
        print("\nDone — that entire flow ran without a Bluetooth radio.")
    }
}
