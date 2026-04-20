import Testing
@testable import SwiftBLEKit

@Suite("ExponentialBackoff")
struct ExponentialBackoffTests {

    @Test("Base delay grows geometrically and clamps at maxDelay")
    func baseDelayCurve() {
        let backoff = ExponentialBackoff(
            initialDelay: 1,
            multiplier: 2,
            maxDelay: 10,
            maxAttempts: nil,
            jitter: 0
        )
        #expect(backoff.baseDelay(forAttempt: 1) == 1)
        #expect(backoff.baseDelay(forAttempt: 2) == 2)
        #expect(backoff.baseDelay(forAttempt: 3) == 4)
        #expect(backoff.baseDelay(forAttempt: 4) == 8)
        // 16 would exceed the ceiling.
        #expect(backoff.baseDelay(forAttempt: 5) == 10)
    }

    @Test("Jitter stays within the configured band")
    func jitterBand() {
        let backoff = ExponentialBackoff(initialDelay: 10, multiplier: 1, maxDelay: 100, jitter: 0.2)
        // randomUnit 0 → lower bound, 1 → upper bound.
        #expect(backoff.delay(forAttempt: 1, randomUnit: 0) == 8)
        #expect(backoff.delay(forAttempt: 1, randomUnit: 1) == 12)
        #expect(backoff.delay(forAttempt: 1, randomUnit: 0.5) == 10)
    }

    @Test("Attempt budget is enforced")
    func attemptBudget() {
        let limited = ExponentialBackoff(maxAttempts: 3)
        #expect(limited.allowsAttempt(after: 0))
        #expect(limited.allowsAttempt(after: 2))
        #expect(!limited.allowsAttempt(after: 3))

        #expect(ExponentialBackoff.persistent.allowsAttempt(after: 10_000))
    }
}
