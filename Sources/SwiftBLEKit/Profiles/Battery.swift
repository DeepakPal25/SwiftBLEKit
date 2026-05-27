import Foundation

/// The Battery Level characteristic (`0x2A19`) of the Battery Service.
public struct BatteryLevel: CharacteristicValue, Equatable, Sendable {
    /// Remaining charge, 0–100%.
    public let percent: Int

    public init(data: Data) throws {
        var reader = ByteReader(data)
        percent = Int(try reader.uint8())
    }
}
