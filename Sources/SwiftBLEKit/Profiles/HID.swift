import Foundation

/// A HID-over-GATT Report characteristic (`0x2A4D`).
///
/// Report payloads are device-defined (their layout comes from the Report Map),
/// so SwiftBLEKit surfaces the raw bytes and leaves interpretation to the caller.
public struct HIDReport: CharacteristicValue, Equatable, Sendable {
    /// The raw report bytes.
    public let bytes: Data

    public init(data: Data) throws {
        bytes = data
    }
}
