/// Keeps a profile's notification subscriptions alive.
///
/// ``BLEPeripheralProtocol/attach(_:)`` returns a session that owns one task per
/// subscribed characteristic. **Retain it** for as long as you want to receive
/// notifications — when the session is deallocated or ``cancel()`` is called,
/// every subscription's delivery task is torn down.
public final class GATTSession: Sendable {
    private let tasks: [Task<Void, Never>]

    init(tasks: [Task<Void, Never>]) {
        self.tasks = tasks
    }

    /// Cancels all notification-delivery tasks for this profile.
    public func cancel() {
        for task in tasks { task.cancel() }
    }

    deinit {
        cancel()
    }
}
