import Foundation

/// Errors surfaced by SwiftBLEKit.
public enum BLEError: Error, Sendable, Equatable {

    /// The central is not in `.poweredOn` and cannot perform the request.
    case bluetoothUnavailable(BLEManagerState)

    /// A connection attempt exceeded its timeout.
    case connectionTimeout

    /// The peripheral disconnected. `isExpected` distinguishes a user-requested
    /// teardown from an unexpected drop that reconnection should react to.
    case disconnected(isExpected: Bool, reason: String?)

    /// No peripheral with the requested identifier is known to the system.
    case peripheralNotFound

    /// A requested service was not present after discovery.
    case serviceNotFound(BLEUUID)

    /// A requested characteristic was not present after discovery.
    case characteristicNotFound(BLEUUID)

    /// Reconnection gave up after exhausting the configured attempt budget.
    case reconnectionExhausted(attempts: Int)

    /// The operation was cancelled (e.g. the owning task was cancelled).
    case cancelled

    /// An error from the underlying Core Bluetooth stack, preserved as text.
    case underlying(String)
}
