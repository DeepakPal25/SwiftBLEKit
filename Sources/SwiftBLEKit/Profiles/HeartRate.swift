import Foundation

/// The Heart Rate Measurement characteristic (`0x2A37`).
///
/// Parses the flags byte to handle 8- vs 16-bit heart-rate values, optional
/// energy-expended, sensor-contact status, and the trailing RR-interval array.
public struct HeartRateMeasurement: CharacteristicValue, Equatable, Sendable {
    /// Instantaneous heart rate in beats per minute.
    public let beatsPerMinute: Int

    /// Energy expended in kilojoules, if the sensor reports it.
    public let energyExpended: Int?

    /// RR intervals in seconds (converted from the 1/1024 s spec units).
    public let rrIntervals: [Double]

    /// Whether the sensor reports contact-detection support.
    public let sensorContactSupported: Bool

    /// Whether skin contact is currently detected, when supported.
    public let sensorContactDetected: Bool?

    public init(data: Data) throws {
        var reader = ByteReader(data)
        let flags = try reader.uint8()

        let is16Bit = flags & 0x01 != 0
        let contactStatus = (flags >> 1) & 0x03
        let hasEnergy = flags & 0x08 != 0
        let hasRR = flags & 0x10 != 0

        beatsPerMinute = is16Bit ? Int(try reader.uint16LE()) : Int(try reader.uint8())

        switch contactStatus {
        case 0b10:
            sensorContactSupported = true
            sensorContactDetected = false
        case 0b11:
            sensorContactSupported = true
            sensorContactDetected = true
        default:
            sensorContactSupported = false
            sensorContactDetected = nil
        }

        energyExpended = hasEnergy ? Int(try reader.uint16LE()) : nil

        if hasRR {
            var intervals: [Double] = []
            while reader.remaining >= 2 {
                intervals.append(Double(try reader.uint16LE()) / 1024.0)
            }
            rrIntervals = intervals
        } else {
            rrIntervals = []
        }
    }
}

/// The Body Sensor Location characteristic (`0x2A38`).
public enum BodySensorLocation: Int, CharacteristicValue, Sendable {
    case other = 0
    case chest = 1
    case wrist = 2
    case finger = 3
    case hand = 4
    case earLobe = 5
    case foot = 6
    case unknown = 255

    public init(data: Data) throws {
        var reader = ByteReader(data)
        self = BodySensorLocation(rawValue: Int(try reader.uint8())) ?? .unknown
    }
}
