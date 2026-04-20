#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth

// Conversions between SwiftBLEKit's platform-independent types and Core Bluetooth.

extension BLEUUID {
    var cbUUID: CBUUID { CBUUID(string: rawValue) }
    init(_ cbUUID: CBUUID) { self.init(cbUUID.uuidString) }
}

extension Array where Element == BLEUUID {
    var cbUUIDs: [CBUUID] { map(\.cbUUID) }
}

extension BLEManagerState {
    init(_ cbState: CBManagerState) {
        switch cbState {
        case .unknown: self = .unknown
        case .resetting: self = .resetting
        case .unsupported: self = .unsupported
        case .unauthorized: self = .unauthorized
        case .poweredOff: self = .poweredOff
        case .poweredOn: self = .poweredOn
        @unknown default: self = .unknown
        }
    }
}

extension AdvertisementData {
    init(_ dictionary: [String: Any]) {
        let localName = dictionary[CBAdvertisementDataLocalNameKey] as? String
        let serviceUUIDs = (dictionary[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map(BLEUUID.init) ?? []
        let manufacturerData = dictionary[CBAdvertisementDataManufacturerDataKey] as? Data
        let isConnectable = (dictionary[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? true
        self.init(
            localName: localName,
            serviceUUIDs: serviceUUIDs,
            manufacturerData: manufacturerData,
            isConnectable: isConnectable
        )
    }
}
#endif
