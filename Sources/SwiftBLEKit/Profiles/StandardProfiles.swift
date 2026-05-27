import Foundation

/// Pre-built ``ServiceSpec`` definitions for common standard GATT services.
///
/// These are just the 0.2 DSL applied to the 0.3 typed models — drop them into a
/// ``GATTProfile`` and the raw-byte parsing is handled for you:
///
/// ```swift
/// let profile = GATTProfile {
///     StandardProfile.heartRate { measurement in
///         print(measurement.beatsPerMinute)
///     }
///     StandardProfile.battery { level in
///         print(level.percent)
///     }
/// }
/// ```
public enum StandardProfile {

    /// Battery Service — subscribes to Battery Level updates.
    public static func battery(
        _ handler: @escaping @Sendable (BatteryLevel) async -> Void
    ) -> ServiceSpec {
        service(.batteryService) {
            characteristic(.batteryLevel).notify(as: BatteryLevel.self, handler)
        }
    }

    /// Heart Rate Service — subscribes to Heart Rate Measurement notifications.
    public static func heartRate(
        _ handler: @escaping @Sendable (HeartRateMeasurement) async -> Void
    ) -> ServiceSpec {
        service(.heartRate) {
            characteristic(.heartRateMeasurement).notify(as: HeartRateMeasurement.self, handler)
        }
    }

    /// Cycling Power Service — subscribes to Cycling Power Measurement.
    public static func cyclingPower(
        _ handler: @escaping @Sendable (CyclingPowerMeasurement) async -> Void
    ) -> ServiceSpec {
        service(.cyclingPower) {
            characteristic(.cyclingPowerMeasurement).notify(as: CyclingPowerMeasurement.self, handler)
        }
    }

    /// Device Information Service — reads the identity strings once on attach.
    /// Each handler is only invoked if the corresponding characteristic exists
    /// and decodes; absent fields are skipped.
    public static func deviceInformation(
        manufacturer: (@Sendable (String) async -> Void)? = nil,
        model: (@Sendable (String) async -> Void)? = nil,
        firmware: (@Sendable (String) async -> Void)? = nil
    ) -> ServiceSpec {
        service(.deviceInformation) {
            if let manufacturer {
                characteristic(.manufacturerName).read(as: GATTString.self) { await manufacturer($0.value) }
            }
            if let model {
                characteristic(.modelNumber).read(as: GATTString.self) { await model($0.value) }
            }
            if let firmware {
                characteristic(.firmwareRevision).read(as: GATTString.self) { await firmware($0.value) }
            }
        }
    }
}
