import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration

final class UsageReader: Reader<NetworkUsage> {
    private static let detailsInterval: TimeInterval = 15

    private var lastCounters: Bandwidth?
    private var lastSample: DispatchTime?
    private var lastInterface = ""
    private var total = Bandwidth()
    private var lastDetailsTS = Date.distantPast
    private var cachedInfo: InterfaceInfo?
    private var cachedType: ConnectionType?
    private var cachedAddresses = LocalAddresses()
    private var cachedWiFi = WiFiDetails()

    private let authorization: () -> WiFiAuthorization

    init(
        interval: TimeInterval = 1,
        authorization: @escaping () -> WiFiAuthorization,
        handler: @escaping (NetworkUsage) -> Void
    ) {
        self.authorization = authorization
        super.init(label: "netdog.usage", interval: interval, handler: handler)
    }

    /// Forces the next tick to re-read interface/Wi-Fi details (e.g. after
    /// the location permission changed).
    func refreshDetails() {
        self.onQueue { [weak self] in
            self?.lastDetailsTS = .distantPast
        }
    }

    override func read() {
        let name = InterfaceResolver.primary()
        if name != self.lastInterface {
            self.lastInterface = name
            self.reset()
            self.lastDetailsTS = .distantPast
        }

        let now = DispatchTime.now()
        guard let counters = InterfaceCounters.bytes(for: name) else {
            self.reset()
            var value = NetworkUsage()
            value.interface = self.cachedInfo
            value.connectionType = self.cachedType
            value.total = self.total
            value.wifiAuthorization = self.authorization()
            self.emit(value)
            return
        }

        var value = NetworkUsage()
        value.status = true

        if let previous = self.lastCounters, let previousTS = self.lastSample {
            let elapsed = max(Double(now.uptimeNanoseconds &- previousTS.uptimeNanoseconds) / 1_000_000_000, 0.001)
            var download = Int64(Double(max(counters.download - previous.download, 0)) / elapsed)
            var upload = Int64(Double(max(counters.upload - previous.upload, 0)) / elapsed)

            // Drop one-shot counter jumps (VPN reconnect, interface flap) that exceed
            // what a 100 Gbps link could physically deliver in this window.
            let maxDelta = Int64(12_500_000_000 * elapsed)
            if download > maxDelta { download = 0 }
            if upload > maxDelta { upload = 0 }

            value.bandwidth = Bandwidth(upload: upload, download: download)
        }

        self.total.upload += value.bandwidth.upload
        self.total.download += value.bandwidth.download
        value.total = self.total

        self.lastCounters = counters
        self.lastSample = now

        self.refreshDetailsIfNeeded(interface: name)

        value.interface = self.cachedInfo
        value.connectionType = self.cachedType
        value.laddr = self.cachedAddresses
        value.wifi = self.cachedWiFi
        value.wifiAuthorization = self.authorization()

        self.emit(value)
    }

    override func reset() {
        self.lastCounters = nil
        self.lastSample = nil
    }

    private func refreshDetailsIfNeeded(interface: String) {
        guard !interface.isEmpty, Date().timeIntervalSince(self.lastDetailsTS) >= Self.detailsInterval else { return }
        self.lastDetailsTS = Date()

        let authorized = self.authorization() == .authorized
        let details = Self.snapshot(interface: interface, authorized: authorized)
        self.cachedInfo = details.info
        self.cachedType = details.type
        self.cachedAddresses = details.addresses
        self.cachedWiFi = details.wifi
    }

    static func snapshot(
        interface: String,
        authorized: Bool
    ) -> (info: InterfaceInfo?, type: ConnectionType?, addresses: LocalAddresses, wifi: WiFiDetails) {
        var info: InterfaceInfo?
        var type: ConnectionType?

        for item in SCNetworkInterfaceCopyAll() as NSArray {
            let sc = item as! SCNetworkInterface
            guard let bsdName = SCNetworkInterfaceGetBSDName(sc),
                  bsdName as String == interface else {
                continue
            }
            let bsd = bsdName as String

            var value = InterfaceInfo(bsdName: bsd)
            if let name = SCNetworkInterfaceGetLocalizedDisplayName(sc) {
                value.displayName = name as String
            }
            if let mac = SCNetworkInterfaceGetHardwareAddressString(sc) {
                value.mac = mac as String
            }
            if let rawType = SCNetworkInterfaceGetInterfaceType(sc) {
                let typeString = rawType as String
                if typeString == kSCNetworkInterfaceTypeEthernet as String {
                    type = .ethernet
                } else if typeString == kSCNetworkInterfaceTypeIEEE80211 as String
                    || typeString == kSCNetworkInterfaceTypeWWAN as String {
                    type = .wifi
                } else if typeString == kSCNetworkInterfaceTypeBluetooth as String {
                    type = .bluetooth
                } else {
                    type = .other
                }
            }
            info = value
        }

        var addresses = LocalAddresses()
        var linkRate: Double = 0
        var interfaceUp = false

        var list: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&list) == 0 {
            defer { freeifaddrs(list) }
            var pointer = list
            while let current = pointer {
                defer { pointer = current.pointee.ifa_next }
                guard String(cString: current.pointee.ifa_name) == interface else { continue }

                interfaceUp = Int32(current.pointee.ifa_flags) & IFF_UP != 0
                guard let address = current.pointee.ifa_addr else { continue }

                switch Int32(address.pointee.sa_family) {
                case AF_INET:
                    if addresses.v4 == nil, let ip = numericHost(address), !ip.isEmpty {
                        addresses.v4 = ip
                    }
                case AF_INET6:
                    if addresses.v6 == nil, let ip = numericHost(address), !ip.isEmpty, !ip.hasPrefix("fe80") {
                        addresses.v6 = ip
                    }
                case AF_LINK:
                    if let raw = current.pointee.ifa_data {
                        let data = raw.assumingMemoryBound(to: if_data.self).pointee
                        if data.ifi_baudrate > 0 {
                            linkRate = Double(data.ifi_baudrate) / 1_000_000
                        }
                    }
                default:
                    break
                }
            }
        }

        info?.status = interfaceUp

        var wifi = WiFiDetails()
        if type == .wifi, let wifiInterface = CWWiFiClient.shared().interface(withName: interface) {
            if authorized {
                if let ssid = wifiInterface.ssid(), isUsableSSID(ssid) {
                    wifi.ssid = ssid
                }
                wifi.bssid = wifiInterface.bssid()
            }
            wifi.countryCode = wifiInterface.countryCode()
            wifi.rssi = wifiInterface.rssiValue()
            wifi.noise = wifiInterface.noiseMeasurement()
            wifi.standard = wifiInterface.activePHYMode().description
            wifi.mode = wifiInterface.interfaceMode().description
            wifi.security = wifiInterface.security().description
            if let channel = wifiInterface.wlanChannel() {
                wifi.channel = channelDescription(channel)
                wifi.channelBand = channel.channelBand.description
                wifi.channelWidth = channel.channelWidth.description
                wifi.channelNumber = "\(channel.channelNumber)"
            }
            info?.transmitRate = wifiInterface.transmitRate()
        } else {
            info?.transmitRate = linkRate
        }

        return (info, type, addresses, wifi)
    }

    private static func numericHost(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        return String(cString: host)
    }

    private static func isUsableSSID(_ ssid: String) -> Bool {
        return !ssid.isEmpty && !ssid.hasPrefix("<")
    }
}
