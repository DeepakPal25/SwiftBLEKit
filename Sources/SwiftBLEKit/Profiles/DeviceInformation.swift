import Foundation

/// A UTF-8 string characteristic, used by the Device Information service for
/// Manufacturer Name (`0x2A29`), Model Number (`0x2A24`), Serial Number
/// (`0x2A25`), Firmware/Hardware/Software Revision, and similar fields.
///
/// ```swift
/// characteristic(.manufacturerName).read(as: GATTString.self) { name in
///     print(name.value)
/// }
/// ```
public struct GATTString: CharacteristicValue, Equatable, Sendable {
    public let value: String

    public init(data: Data) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw BLEError.underlying("characteristic value is not valid UTF-8")
        }
        value = string
    }
}
