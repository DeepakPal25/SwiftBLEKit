import Foundation

/// A declarative description of the services and characteristics an app cares
/// about on a peripheral, plus what to do with their values.
///
/// Build one with the result-builder DSL and hand it to
/// ``BLEPeripheralProtocol/attach(_:)``, which discovers everything and wires up
/// the reads and notifications for you — replacing the discover → subscribe →
/// parse boilerplate every BLE app otherwise rewrites.
///
/// ```swift
/// let profile = GATTProfile {
///     service(.heartRate) {
///         characteristic(.heartRateMeasurement).notify { data in
///             // handle raw bytes, or decode with `.notify(as:)`
///         }
///     }
///     service(.batteryService) {
///         characteristic(.batteryLevel).read { data in
///             // read once on attach
///         }
///     }
/// }
/// ```
public struct GATTProfile: Sendable {
    public let services: [ServiceSpec]

    public init(@ServiceBuilder _ services: () -> [ServiceSpec]) {
        self.services = services()
    }
}

// MARK: - Specs

/// A service and the characteristics to operate on within it.
public struct ServiceSpec: Sendable {
    public let uuid: BLEUUID
    public let characteristics: [CharacteristicSpec]
}

/// A single characteristic together with the operation to perform on it.
///
/// Created via the free function ``characteristic(_:)`` and refined with the
/// fluent `read`/`notify` modifiers. A spec with no operation is discovered but
/// otherwise left alone.
public struct CharacteristicSpec: Sendable {
    public let uuid: BLEUUID

    /// Invoked once during ``BLEPeripheralProtocol/attach(_:)`` with the read value.
    let onRead: (@Sendable (Data) async -> Void)?

    /// Invoked for every notification/indication after attach.
    let onNotify: (@Sendable (Data) async -> Void)?

    init(
        uuid: BLEUUID,
        onRead: (@Sendable (Data) async -> Void)? = nil,
        onNotify: (@Sendable (Data) async -> Void)? = nil
    ) {
        self.uuid = uuid
        self.onRead = onRead
        self.onNotify = onNotify
    }

    // MARK: Fluent operations

    /// Reads the characteristic once when the profile is attached, delivering
    /// the raw bytes.
    public func read(_ handler: @escaping @Sendable (Data) async -> Void) -> CharacteristicSpec {
        CharacteristicSpec(uuid: uuid, onRead: handler, onNotify: onNotify)
    }

    /// Reads the characteristic once when the profile is attached, decoding the
    /// bytes into `V`. Decode failures are silently skipped.
    public func read<V: CharacteristicValue>(
        as type: V.Type,
        _ handler: @escaping @Sendable (V) async -> Void
    ) -> CharacteristicSpec {
        read { data in
            if let value = try? V(data: data) { await handler(value) }
        }
    }

    /// Subscribes to notifications, delivering the raw bytes of each update.
    public func notify(_ handler: @escaping @Sendable (Data) async -> Void) -> CharacteristicSpec {
        CharacteristicSpec(uuid: uuid, onRead: onRead, onNotify: handler)
    }

    /// Subscribes to notifications, decoding each update into `V`. Decode
    /// failures are silently skipped.
    public func notify<V: CharacteristicValue>(
        as type: V.Type,
        _ handler: @escaping @Sendable (V) async -> Void
    ) -> CharacteristicSpec {
        notify { data in
            if let value = try? V(data: data) { await handler(value) }
        }
    }
}

// MARK: - DSL entry points

/// Declares a service within a ``GATTProfile``.
public func service(
    _ uuid: BLEUUID,
    @CharacteristicBuilder _ characteristics: () -> [CharacteristicSpec]
) -> ServiceSpec {
    ServiceSpec(uuid: uuid, characteristics: characteristics())
}

/// Declares a characteristic within a `service { … }` block.
public func characteristic(_ uuid: BLEUUID) -> CharacteristicSpec {
    CharacteristicSpec(uuid: uuid)
}

// MARK: - Result builders

@resultBuilder
public enum ServiceBuilder {
    public static func buildExpression(_ expression: ServiceSpec) -> [ServiceSpec] { [expression] }
    public static func buildExpression(_ expression: [ServiceSpec]) -> [ServiceSpec] { expression }
    public static func buildBlock(_ components: [ServiceSpec]...) -> [ServiceSpec] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [ServiceSpec]?) -> [ServiceSpec] { component ?? [] }
    public static func buildEither(first component: [ServiceSpec]) -> [ServiceSpec] { component }
    public static func buildEither(second component: [ServiceSpec]) -> [ServiceSpec] { component }
    public static func buildArray(_ components: [[ServiceSpec]]) -> [ServiceSpec] { components.flatMap { $0 } }
}

@resultBuilder
public enum CharacteristicBuilder {
    public static func buildExpression(_ expression: CharacteristicSpec) -> [CharacteristicSpec] { [expression] }
    public static func buildExpression(_ expression: [CharacteristicSpec]) -> [CharacteristicSpec] { expression }
    public static func buildBlock(_ components: [CharacteristicSpec]...) -> [CharacteristicSpec] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [CharacteristicSpec]?) -> [CharacteristicSpec] { component ?? [] }
    public static func buildEither(first component: [CharacteristicSpec]) -> [CharacteristicSpec] { component }
    public static func buildEither(second component: [CharacteristicSpec]) -> [CharacteristicSpec] { component }
    public static func buildArray(_ components: [[CharacteristicSpec]]) -> [CharacteristicSpec] { components.flatMap { $0 } }
}
