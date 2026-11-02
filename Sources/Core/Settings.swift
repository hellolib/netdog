import AppKit

enum DataSizeBase: String {
    case bit
    case byte
}

enum UsageResetPolicy: String {
    case never
    case atStart
    case daily
    case weekly
    case monthly
}

enum PopupSection: String, CaseIterable {
    case usageHistory
    case connectivityHistory
    case traffic
    case interfaceInfo
    case address
    case processes

    var title: String {
        switch self {
        case .usageHistory: return "负载历史"
        case .connectivityHistory: return "连接历史"
        case .traffic: return "流量统计"
        case .interfaceInfo: return "接口信息"
        case .address: return "地址"
        case .processes: return "进程排行"
        }
    }

    var key: String {
        return "Network_popupShow_\(self.rawValue)"
    }
}

enum Settings {
    static let maxProcessCount = 15
    static let defaultUpdateInterval: Double = 1
    static let defaultProcessCount = 5
    static let defaultConnectivityMode = "auto"
    static let defaultICMPHost = "223.5.5.5"
    static let defaultHTTPHost = "https://captive.apple.com/hotspot-detect.html"
    static let defaultDownloadColor = "#007AFF"
    static let defaultUploadColor = "#FF3B30"

    enum Keys {
        static let updateInterval = "Network_updateInterval"
        static let processCount = "Network_processes"
        static let connectivityMode = "Network_connectivityMode"
        static let icmpHost = "Network_ICMPHost"
        static let httpHost = "Network_HTTPHost"
        static let publicIP = "Network_publicIP"
        static let interfaceDetails = "Network_interfaceDetails"

        static let readerType = "Network_reader"
        static let interfaceName = "Network_interface"
        static let base = "Network_base"
        static let speedUnit = "Network_speedUnit"
        static let usageReset = "Network_usageReset"
        static let publicIPRefresh = "Network_publicIPRefreshInterval"
        static let vpnMode = "Network_VPNMode"
        static let connectivityInterval = "Network_updateICMPInterval"

        static let chartHistory = "Network_chartHistory"
        static let chartScale = "Network_chartScale"
        static let chartFixedScale = "Network_chartFixedScale"
        static let chartFixedScaleSize = "Network_chartFixedScaleSize"
        static let uploadOnTop = "Network_uploadOnTop"
        static let downloadColor = "Network_downloadColor"
        static let uploadColor = "Network_uploadColor"

        static let emojiCC = "Network_emojiCC"
        static let menuBarMode = "Network_widgetMode"
        static let menuBarIcon = "Network_widgetIcon"
        static let menuBarUnits = "Network_widgetUnits"
        static let menuBarMono = "Network_widgetMono"
        static let thresholdState = "Network_widgetActivationThresholdState"
        static let threshold = "Network_widgetActivationThreshold"
        static let thresholdSize = "Network_widgetActivationThresholdSize"

        static let totalUpload = "Network_totalUpload"
        static let totalDownload = "Network_totalDownload"
        static let usageResetNext = "Network_usageReset_next"
        static let usageResetTS = "Network_usageReset_ts"
    }

    static func registerDefaults() {
        var defaults: [String: Any] = [
            Keys.updateInterval: defaultUpdateInterval,
            Keys.processCount: defaultProcessCount,
            Keys.connectivityMode: defaultConnectivityMode,
            Keys.icmpHost: defaultICMPHost,
            Keys.httpHost: defaultHTTPHost,
            Keys.publicIP: true,
            Keys.interfaceDetails: false,
            Keys.readerType: "interface",
            Keys.interfaceName: "",
            Keys.base: DataSizeBase.byte.rawValue,
            Keys.speedUnit: "auto",
            Keys.usageReset: UsageResetPolicy.never.rawValue,
            Keys.publicIPRefresh: "never",
            Keys.vpnMode: false,
            Keys.connectivityInterval: 1,
            Keys.chartHistory: 180,
            Keys.chartScale: "none",
            Keys.chartFixedScale: 12,
            Keys.chartFixedScaleSize: "MB",
            Keys.uploadOnTop: true,
            Keys.downloadColor: defaultDownloadColor,
            Keys.uploadColor: defaultUploadColor,
            Keys.emojiCC: true,
            Keys.menuBarMode: "twoRows",
            Keys.menuBarIcon: "dots",
            Keys.menuBarUnits: true,
            Keys.menuBarMono: false,
            Keys.thresholdState: false,
            Keys.threshold: 0,
            Keys.thresholdSize: "KB",
            Keys.totalUpload: 0,
            Keys.totalDownload: 0,
            Keys.usageResetNext: 0,
            Keys.usageResetTS: 0
        ]
        PopupSection.allCases.forEach { defaults[$0.key] = true }
        UserDefaults.standard.register(defaults: defaults)
    }

    static var popupSections: [PopupSection] {
        return PopupSection.allCases.filter { self.popupSectionEnabled($0) }
    }

    static func popupSectionEnabled(_ section: PopupSection) -> Bool {
        return UserDefaults.standard.bool(forKey: section.key)
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

    static var interfaceDetails: Bool {
        return UserDefaults.standard.bool(forKey: Keys.interfaceDetails)
    }

    // MARK: - data source

    static var readerType: String {
        return UserDefaults.standard.string(forKey: Keys.readerType) ?? "interface"
    }

    static var interfaceName: String {
        return UserDefaults.standard.string(forKey: Keys.interfaceName) ?? ""
    }

    static var base: DataSizeBase {
        return DataSizeBase(rawValue: UserDefaults.standard.string(forKey: Keys.base) ?? "") ?? .byte
    }

    static var speedUnit: String {
        return UserDefaults.standard.string(forKey: Keys.speedUnit) ?? "auto"
    }

    static var usageReset: UsageResetPolicy {
        return UsageResetPolicy(rawValue: UserDefaults.standard.string(forKey: Keys.usageReset) ?? "") ?? .never
    }

    static var vpnMode: Bool {
        return UserDefaults.standard.bool(forKey: Keys.vpnMode)
    }

    // MARK: - connectivity / public ip

    static var connectivityInterval: Int {
        return max(UserDefaults.standard.integer(forKey: Keys.connectivityInterval), 1)
    }

    static var publicIPRefresh: String {
        return UserDefaults.standard.string(forKey: Keys.publicIPRefresh) ?? "never"
    }

    static var publicIPRefreshSeconds: TimeInterval? {
        switch self.publicIPRefresh {
        case "hour": return 60 * 60
        case "12": return 60 * 60 * 12
        case "24": return 60 * 60 * 24
        default: return nil
        }
    }

    // MARK: - chart

    static var chartHistory: Int {
        return max(UserDefaults.standard.integer(forKey: Keys.chartHistory), 30)
    }

    static var chartScale: ChartScale {
        return ChartScale(rawValue: UserDefaults.standard.string(forKey: Keys.chartScale) ?? "") ?? .none
    }

    static var chartFixedScale: Int {
        return max(UserDefaults.standard.integer(forKey: Keys.chartFixedScale), 1)
    }

    static var chartFixedScaleSize: String {
        return UserDefaults.standard.string(forKey: Keys.chartFixedScaleSize) ?? "MB"
    }

    static var chartFixedScaleBytes: Int64 {
        return Units.bytes(self.chartFixedScale, unit: self.chartFixedScaleSize)
    }

    static var uploadOnTop: Bool {
        return UserDefaults.standard.bool(forKey: Keys.uploadOnTop)
    }

    static var reverseOrder: Bool {
        return !self.uploadOnTop
    }

    static var downloadColor: NSColor {
        return self.color(from: self.colorString(for: Keys.downloadColor), fallback: .systemBlue)
    }

    static var uploadColor: NSColor {
        return self.color(from: self.colorString(for: Keys.uploadColor), fallback: .systemRed)
    }

    static func setColor(_ color: NSColor, for key: String) {
        self.set(self.hex(from: color), for: key)
    }

    private static func colorString(for key: String) -> String {
        let fallback = key == Keys.downloadColor ? defaultDownloadColor : defaultUploadColor
        return UserDefaults.standard.string(forKey: key) ?? fallback
    }

    // MARK: - menu bar

    static var emojiCC: Bool {
        return UserDefaults.standard.bool(forKey: Keys.emojiCC)
    }

    static var menuBarMode: String {
        return UserDefaults.standard.string(forKey: Keys.menuBarMode) ?? "twoRows"
    }

    static var menuBarIcon: String {
        return UserDefaults.standard.string(forKey: Keys.menuBarIcon) ?? "dots"
    }

    static var menuBarUnits: Bool {
        return UserDefaults.standard.bool(forKey: Keys.menuBarUnits)
    }

    static var menuBarMono: Bool {
        return UserDefaults.standard.bool(forKey: Keys.menuBarMono)
    }

    static var thresholdEnabled: Bool {
        return UserDefaults.standard.bool(forKey: Keys.thresholdState)
    }

    static var threshold: Int {
        return UserDefaults.standard.integer(forKey: Keys.threshold)
    }

    static var thresholdSize: String {
        return UserDefaults.standard.string(forKey: Keys.thresholdSize) ?? "KB"
    }

    static var thresholdBytes: Int64 {
        return Units.bytes(self.threshold, unit: self.thresholdSize)
    }

    // MARK: - helpers

    static func set(_ value: Any?, for key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    static func remove(_ key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func int(_ key: String) -> Int {
        return UserDefaults.standard.integer(forKey: key)
    }

    static func double(_ key: String) -> Double {
        return UserDefaults.standard.double(forKey: key)
    }

    static func reset() {
        let defaults = UserDefaults.standard
        [
            Keys.updateInterval, Keys.processCount, Keys.connectivityMode, Keys.icmpHost, Keys.httpHost,
            Keys.publicIP, Keys.interfaceDetails, Keys.readerType, Keys.interfaceName, Keys.base,
            Keys.speedUnit, Keys.usageReset, Keys.publicIPRefresh, Keys.vpnMode, Keys.connectivityInterval,
            Keys.chartHistory, Keys.chartScale, Keys.chartFixedScale, Keys.chartFixedScaleSize,
            Keys.uploadOnTop, Keys.downloadColor, Keys.uploadColor, Keys.emojiCC, Keys.menuBarMode,
            Keys.menuBarIcon, Keys.menuBarUnits, Keys.menuBarMono, Keys.thresholdState, Keys.threshold,
            Keys.thresholdSize
        ].forEach { defaults.removeObject(forKey: $0) }
        PopupSection.allCases.forEach { defaults.removeObject(forKey: $0.key) }
    }

    private static func color(from hex: String, fallback: NSColor) -> NSColor {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6, let int = UInt32(value, radix: 16) else { return fallback }
        return NSColor(
            srgbRed: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func hex(from color: NSColor) -> String {
        guard let value = color.usingColorSpace(.sRGB) else { return "#000000" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(value.redComponent * 255)),
            Int(round(value.greenComponent * 255)),
            Int(round(value.blueComponent * 255))
        )
    }
}
