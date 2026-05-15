import Foundation

extension BLEPeripheralProtocol {

    /// Discovers the services and characteristics named in `profile`, performs
    /// each declared read, and subscribes to each declared notification.
    ///
    /// This collapses the usual discover → subscribe → parse pipeline into a
    /// single declarative call. Reads run inline and their handlers fire before
    /// this method returns; notification handlers fire on the returned session's
    /// tasks until it is cancelled or deallocated.
    ///
    /// - Returns: A ``GATTSession`` owning the notification subscriptions. Retain
    ///   it to keep receiving updates.
    /// - Throws: ``BLEError`` if a declared service or characteristic is absent,
    ///   or if a read fails.
    @discardableResult
    public func attach(_ profile: GATTProfile) async throws -> GATTSession {
        try await discoverServices(profile.services.map(\.uuid))

        var tasks: [Task<Void, Never>] = []

        for serviceSpec in profile.services {
            try await discoverCharacteristics(
                serviceSpec.characteristics.map(\.uuid),
                for: serviceSpec.uuid
            )

            for characteristicSpec in serviceSpec.characteristics {
                if let onRead = characteristicSpec.onRead {
                    let data = try await readValue(for: characteristicSpec.uuid)
                    await onRead(data)
                }

                if let onNotify = characteristicSpec.onNotify {
                    try await setNotify(true, for: characteristicSpec.uuid)
                    let stream = notifications(for: characteristicSpec.uuid)
                    let task = Task {
                        for await data in stream {
                            await onNotify(data)
                        }
                    }
                    tasks.append(task)
                }
            }
        }

        return GATTSession(tasks: tasks)
    }
}
