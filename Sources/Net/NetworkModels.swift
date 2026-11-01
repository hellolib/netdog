import Foundation

enum ConnectionType: String {
    case wifi
    case ethernet
    case bluetooth
    case other

    var label: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "以太网"
        case .bluetooth: return "蓝牙"
        case .other: return "其他"
        }
    }
}

struct InterfaceInfo {
    var bsdName = ""
    var displayName = ""
    var mac = ""
    var status = false
    var transmitRate: Double = 0
}

struct LocalAddresses {
    var v4: String?
    var v6: String?
}

struct WiFiDetails {
    var ssid: String?
    var bssid: String?
    var countryCode: String?
    var rssi: Int?
    var noise: Int?
    var standard: String?
    var mode: String?
    var security: String?
    var channel: String?
    var channelBand: String?
    var channelWidth: String?
    var channelNumber: String?
}

enum WiFiAuthorization {
    case notDetermined
    case denied
    case authorized
}

struct NetworkUsage {
    var bandwidth = Bandwidth()
    var total = Bandwidth()
    var interface: InterfaceInfo?
    var connectionType: ConnectionType?
    var laddr = LocalAddresses()
    var wifi = WiFiDetails()
    var wifiAuthorization: WiFiAuthorization = .notDetermined
    var status = false
}
