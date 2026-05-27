import Foundation

/// A small cursor for decoding little-endian GATT payloads.
///
/// Copies the payload into a `[UInt8]` so slice index math never trips up on
/// `Data`'s non-zero `startIndex`. Every read is bounds-checked and throws
/// ``BLEError/underlying(_:)`` on underflow.
struct ByteReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    /// Bytes not yet consumed.
    var remaining: Int { bytes.count - offset }

    mutating func uint8() throws -> UInt8 {
        guard offset < bytes.count else {
            throw BLEError.underlying("unexpected end of characteristic data")
        }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func uint16LE() throws -> UInt16 {
        let low = try uint8()
        let high = try uint8()
        return UInt16(low) | (UInt16(high) << 8)
    }

    mutating func int16LE() throws -> Int16 {
        Int16(bitPattern: try uint16LE())
    }

    /// Consumes and returns whatever bytes are left.
    mutating func rest() -> Data {
        defer { offset = bytes.count }
        return Data(bytes[offset...])
    }
}
