/// The power/authorization state of the Bluetooth central, mirroring
/// `CBManagerState` without depending on Core Bluetooth.
public enum BLEManagerState: Sendable, Equatable {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn

    /// Whether the central can currently scan and connect.
    public var isReady: Bool { self == .poweredOn }
}
