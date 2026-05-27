import Foundation

/// The Cycling Power Measurement characteristic (`0x2A63`).
///
/// Parses the mandatory instantaneous power and, when the flags advertise it,
/// the pedal power balance. The remaining optional fields are left unparsed for
/// now — only the offsets actually read are advanced, so this stays correct.
public struct CyclingPowerMeasurement: CharacteristicValue, Equatable, Sendable {
    /// Instantaneous power in watts (may be negative during coasting/braking).
    public let instantaneousPower: Int

    /// Pedal power balance as a percentage (0–100), if present.
    public let pedalPowerBalance: Double?

    public init(data: Data) throws {
        var reader = ByteReader(data)
        let flags = try reader.uint16LE()
        instantaneousPower = Int(try reader.int16LE())

        let hasPedalBalance = flags & 0x01 != 0
        pedalPowerBalance = hasPedalBalance ? Double(try reader.uint8()) / 2.0 : nil
    }
}
