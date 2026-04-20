import Foundation

/// A peripheral discovered during a scan, with its advertisement snapshot.
public struct BLEDiscovery: Sendable {

    /// The discovered peripheral, ready to be connected.
    public let peripheral: BLEPeripheralProtocol

    /// Parsed advertisement data.
    public let advertisement: AdvertisementData

    /// Signal strength in dBm at the moment of discovery.
    public let rssi: Int

    public init(peripheral: BLEPeripheralProtocol, advertisement: AdvertisementData, rssi: Int) {
        self.peripheral = peripheral
        self.advertisement = advertisement
        self.rssi = rssi
    }
}

/// A normalized view of the advertisement payload, mirroring the common keys of
/// Core Bluetooth's advertisement dictionary.
public struct AdvertisementData: Sendable, Equatable {
    public var localName: String?
    public var serviceUUIDs: [BLEUUID]
    public var manufacturerData: Data?
    public var isConnectable: Bool

    public init(
        localName: String? = nil,
        serviceUUIDs: [BLEUUID] = [],
        manufacturerData: Data? = nil,
        isConnectable: Bool = true
    ) {
        self.localName = localName
        self.serviceUUIDs = serviceUUIDs
        self.manufacturerData = manufacturerData
        self.isConnectable = isConnectable
    }
}

/// Emitted when a connected peripheral disconnects.
public struct BLEDisconnection: Sendable, Equatable {
    public let identifier: UUID
    /// The reason for the drop, or `nil` for a clean user-requested disconnect.
    public let error: BLEError?

    public init(identifier: UUID, error: BLEError?) {
        self.identifier = identifier
        self.error = error
    }
}
