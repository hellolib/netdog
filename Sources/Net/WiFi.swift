import AppKit
import CoreLocation
import CoreWLAN

extension CWPHYMode: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .mode11a: return "802.11a"
        case .mode11ac: return "802.11ac"
        case .mode11b: return "802.11b"
        case .mode11g: return "802.11g"
        case .mode11n: return "802.11n"
        case .mode11ax: return "802.11ax"
        case .mode11be: return "802.11be"
        case .modeNone: return "none"
        @unknown default: return "unknown"
        }
    }
}

extension CWInterfaceMode: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .hostAP: return "AP"
        case .IBSS: return "Adhoc"
        case .station: return "Station"
        case .none: return "none"
        @unknown default: return "unknown"
        }
    }
}

extension CWSecurity: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .none: return "none"
        case .WEP: return "WEP"
        case .wpaPersonal: return "WPA Personal"
        case .wpaPersonalMixed: return "WPA Personal Mixed"
        case .wpa2Personal: return "WPA2 Personal"
        case .personal: return "Personal"
        case .dynamicWEP: return "Dynamic WEP"
        case .wpaEnterprise: return "WPA Enterprise"
        case .wpaEnterpriseMixed: return "WPA Enterprise Mixed"
        case .wpa2Enterprise: return "WPA2 Enterprise"
        case .enterprise: return "Enterprise"
        case .wpa3Personal: return "WPA3 Personal"
        case .wpa3Enterprise: return "WPA3 Enterprise"
        case .wpa3Transition: return "WPA3 Transition"
        case .OWE: return "OWE"
        case .oweTransition: return "OWE Transition"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }
}

extension CWChannelBand: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .band2GHz: return "2 GHz"
        case .band5GHz: return "5 GHz"
        case .band6GHz: return "6 GHz"
        case .bandUnknown: return "unknown"
        @unknown default: return "unknown"
        }
    }
}

extension CWChannelWidth: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .width20MHz: return "20 MHz"
        case .width40MHz: return "40 MHz"
        case .width80MHz: return "80 MHz"
        case .width160MHz: return "160 MHz"
        case .widthUnknown: return "unknown"
        @unknown default: return "unknown"
        }
    }
}

func channelDescription(_ channel: CWChannel) -> String {
    return "\(channel.channelNumber) (\(channel.channelBand), \(channel.channelWidth))"
}

/// SSID/BSSID are gated behind location authorization on macOS 10.15+.
final class LocationAuth: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAuth()

    var onChange: (() -> Void)?

    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var cached: WiFiAuthorization = .notDetermined

    override init() {
        super.init()
        self.manager.delegate = self
        self.cacheStatus()
    }

    var status: WiFiAuthorization {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.cached
    }

    func request() {
        switch self.manager.authorizationStatus {
        case .notDetermined:
            self.manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.cacheStatus()
        self.onChange?()
    }

    private func cacheStatus() {
        let value: WiFiAuthorization
        switch self.manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            value = .authorized
        case .notDetermined:
            value = .notDetermined
        default:
            value = .denied
        }
        self.lock.lock()
        self.cached = value
        self.lock.unlock()
    }
}
