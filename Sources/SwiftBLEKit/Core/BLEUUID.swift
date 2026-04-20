import Foundation

/// A Bluetooth attribute identifier.
///
/// Wraps a 16-, 32-, or 128-bit UUID as a normalized, uppercased string so the
/// core of SwiftBLEKit never has to import Core Bluetooth. The Core Bluetooth
/// adapter converts this to `CBUUID` at the boundary.
public struct BLEUUID: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {

    /// The normalized (uppercased) string representation.
    public let rawValue: String

    /// Creates an identifier from a UUID string.
    ///
    /// Accepts the 16-bit shorthand (`"180D"`), 32-bit shorthand, or the full
    /// 128-bit form (`"0000180D-0000-1000-8000-00805F9B34FB"`).
    public init(_ string: String) {
        self.rawValue = string.uppercased()
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    /// Creates an identifier from a Foundation `UUID`.
    public init(_ uuid: UUID) {
        self.rawValue = uuid.uuidString.uppercased()
    }

    public var description: String { rawValue }
}

// MARK: - Common assigned numbers

extension BLEUUID {
    // Services
    public static let genericAccess: BLEUUID = "1800"
    public static let deviceInformation: BLEUUID = "180A"
    public static let batteryService: BLEUUID = "180F"
    public static let heartRate: BLEUUID = "180D"
    public static let cyclingPower: BLEUUID = "1818"
    public static let humanInterfaceDevice: BLEUUID = "1812"

    // Characteristics
    public static let batteryLevel: BLEUUID = "2A19"
    public static let heartRateMeasurement: BLEUUID = "2A37"
    public static let bodySensorLocation: BLEUUID = "2A38"
    public static let manufacturerName: BLEUUID = "2A29"
    public static let modelNumber: BLEUUID = "2A24"
    public static let firmwareRevision: BLEUUID = "2A26"
}
