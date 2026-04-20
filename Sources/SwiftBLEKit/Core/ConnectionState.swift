/// The lifecycle of a single peripheral connection, as driven by
/// ``ConnectionCoordinator``.
///
/// This is the state machine that idea #1 (reconnection reliability) is built
/// around. Consumers observe these transitions instead of re-implementing
/// retry/backoff bookkeeping in every app.
public enum ConnectionState: Sendable, Equatable {
    /// Not connected and not attempting to connect.
    case disconnected

    /// Scanning for the target peripheral (identifier not yet resolved).
    case scanning

    /// A connection attempt is in flight.
    case connecting

    /// Connected and ready for GATT interaction.
    case connected

    /// A previous connection dropped; a retry is scheduled or in flight.
    /// `attempt` is 1-based.
    case reconnecting(attempt: Int)

    /// Terminal failure — reconnection budget exhausted or a fatal error.
    case failed(BLEError)

    /// Whether this is a terminal state that will not transition on its own.
    public var isTerminal: Bool {
        switch self {
        case .failed: return true
        default: return false
        }
    }
}
