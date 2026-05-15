import Foundation

/// A value that can be decoded from a characteristic's raw bytes.
///
/// Adopt this to plug typed parsing into the DSL's `read`/`notify` operations,
/// e.g. `characteristic(.heartRateMeasurement).notify(as: HeartRate.self) { … }`.
/// Ready-made conformances for the standard GATT profiles arrive in a later
/// release; for now you can conform your own payload types.
public protocol CharacteristicValue: Sendable {
    /// Decodes the value from a characteristic payload.
    /// - Throws: ``BLEError`` (or any error) when the bytes are malformed.
    init(data: Data) throws
}

/// Raw bytes pass through unchanged, so `Data` is itself a valid
/// ``CharacteristicValue``.
extension Data: CharacteristicValue {
    public init(data: Data) throws { self = data }
}
