import Foundation

enum Settings {
    static let maxProcessCount = 8
    static let defaultUpdateInterval: Double = 1
    static let defaultProcessCount = 5
    static let defaultConnectivityMode = "auto"
    static let defaultICMPHost = "223.5.5.5"
    static let defaultHTTPHost = "https://captive.apple.com/hotspot-detect.html"

    enum Keys {
        static let updateInterval = "Network_updateInterval"
        static let processCount = "Network_processes"
        static let connectivityMode = "Network_connectivityMode"
        static let icmpHost = "Network_ICMPHost"
        static let httpHost = "Network_HTTPHost"
        static let publicIP = "Network_publicIP"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.updateInterval: defaultUpdateInterval,
            Keys.processCount: defaultProcessCount,
            Keys.connectivityMode: defaultConnectivityMode,
            Keys.icmpHost: defaultICMPHost,
            Keys.httpHost: defaultHTTPHost,
            Keys.publicIP: true
        ])
    }

    static var updateInterval: Double {
        let value = UserDefaults.standard.double(forKey: Keys.updateInterval)
        return value > 0 ? value : defaultUpdateInterval
    }

    static var processCount: Int {
        return min(max(UserDefaults.standard.integer(forKey: Keys.processCount), 0), maxProcessCount)
    }

    static var connectivityMode: ConnectivityMode {
        return ConnectivityMode(rawValue: UserDefaults.standard.string(forKey: Keys.connectivityMode) ?? "") ?? .auto
    }

    static var icmpHost: String {
        let value = UserDefaults.standard.string(forKey: Keys.icmpHost) ?? ""
        return value.isEmpty ? defaultICMPHost : value
    }

    static var httpHost: String {
        let value = UserDefaults.standard.string(forKey: Keys.httpHost) ?? ""
        return value.isEmpty ? defaultHTTPHost : value
    }

    static var httpURL: URL {
        let raw = httpHost
        let normalized = raw.hasPrefix("http://") || raw.hasPrefix("https://") ? raw : "https://\(raw)"
        return URL(string: normalized) ?? URL(string: defaultHTTPHost)!
    }

    static var publicIPEnabled: Bool {
        return UserDefaults.standard.bool(forKey: Keys.publicIP)
    }

    static func set(_ value: Any?, for key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    static func reset() {
        let defaults = UserDefaults.standard
        [
            Keys.updateInterval,
            Keys.processCount,
            Keys.connectivityMode,
            Keys.icmpHost,
            Keys.httpHost,
            Keys.publicIP
        ].forEach { defaults.removeObject(forKey: $0) }
    }
}
