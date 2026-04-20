import Foundation

/// A configurable exponential-backoff schedule with optional jitter.
///
/// This is the retry policy behind ``ConnectionCoordinator``. It is a pure
/// value type with no side effects, so the delay curve can be unit-tested
/// exhaustively without waiting on real time or hardware.
public struct ExponentialBackoff: Sendable, Equatable {

    /// The delay before the first retry, in seconds.
    public var initialDelay: TimeInterval

    /// The factor applied to the delay after each attempt.
    public var multiplier: Double

    /// The ceiling for any single delay, in seconds.
    public var maxDelay: TimeInterval

    /// The maximum number of retry attempts, or `nil` for unlimited.
    public var maxAttempts: Int?

    /// The fraction of jitter to apply, in `0...1`. `0.2` means each delay is
    /// randomly scaled within ±20%, which spreads out reconnection storms when
    /// many peripherals drop at once.
    public var jitter: Double

    public init(
        initialDelay: TimeInterval = 0.5,
        multiplier: Double = 2.0,
        maxDelay: TimeInterval = 30.0,
        maxAttempts: Int? = 10,
        jitter: Double = 0.2
    ) {
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
        self.jitter = jitter
    }

    /// A schedule that never gives up, suitable for always-on accessories.
    public static let persistent = ExponentialBackoff(maxAttempts: nil)

    /// Whether another attempt is permitted after `completedAttempts` retries.
    public func allowsAttempt(after completedAttempts: Int) -> Bool {
        guard let maxAttempts else { return true }
        return completedAttempts < maxAttempts
    }

    /// The base (pre-jitter) delay for a 1-based `attempt` number.
    public func baseDelay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        let exponent = Double(attempt - 1)
        let raw = initialDelay * pow(multiplier, exponent)
        return min(raw, maxDelay)
    }

    /// The jittered delay for a 1-based `attempt` number.
    ///
    /// - Parameter randomUnit: A value in `0...1` used to place the jitter.
    ///   Defaults to a fresh random draw; inject a fixed value in tests.
    public func delay(
        forAttempt attempt: Int,
        randomUnit: Double = Double.random(in: 0...1)
    ) -> TimeInterval {
        let base = baseDelay(forAttempt: attempt)
        guard jitter > 0 else { return base }
        let spread = base * jitter
        // Map randomUnit 0...1 onto -spread...+spread.
        let offset = (randomUnit * 2 - 1) * spread
        return max(0, base + offset)
    }
}
