import Foundation

/// Headless modes used by scripts:
/// `--sample <seconds>` prints one averaged measurement and exits.
/// `--details` prints one interface/Wi-Fi snapshot and exits.
enum CLISampler {
    static func details() {
        let interface = InterfaceResolver.primary()
        guard !interface.isEmpty else {
            write("no primary interface")
            exit(1)
        }
        let authorized = LocationAuth.shared.status == .authorized
        let snapshot = UsageReader.snapshot(interface: interface, authorized: authorized)

        let info = snapshot.info
        let wifi = snapshot.wifi
        let addresses = snapshot.addresses
        print([
            "iface=\(interface)",
            "type=\(snapshot.type?.rawValue ?? "-")",
            "display=\(info?.displayName ?? "-")",
            "mac=\(info?.mac ?? "-")",
            "rate=\(info.map { String(format: "%.0f", $0.transmitRate) } ?? "-")",
            "up=\(info?.status == true)",
            "ipv4=\(addresses.v4 ?? "-")",
            "ipv6=\(addresses.v6 ?? "-")",
            "ssid=\(wifi.ssid ?? "-")",
            "rssi=\(wifi.rssi.map(String.init) ?? "-")",
            "standard=\(wifi.standard ?? "-")",
            "channel=\(wifi.channel ?? "-")",
            "security=\(wifi.security ?? "-")"
        ].joined(separator: " "))
    }

    static func processes() {
        let list = ProcessReader.snapshot()
        guard !list.isEmpty else {
            write("nettop returned no processes")
            exit(1)
        }
        for process in list {
            print("pid=\(process.pid) name=\(process.name) bytes_in=\(process.download) bytes_out=\(process.upload)")
        }
    }

    /// Verifies the delta/ranking path: prints the top list after two samples.
    static func processDeltas() {
        let lock = NSLock()
        var samples = 0
        let reader = ProcessReader(interval: 2) { list in
            lock.lock()
            samples += 1
            let ready = samples >= 2
            lock.unlock()
            guard ready else { return }

            print("samples=\(samples)")
            for process in list {
                print("pid=\(process.pid) name=\(process.name) download=\(process.download) upload=\(process.upload)")
            }
            exit(0)
        }
        reader.start()
        Thread.sleep(forTimeInterval: 12)
        write("no sample")
        exit(1)
    }

    static func connectivity(icmpHost: String? = nil) {
        let lock = NSLock()
        var samples = 0
        let reader = ConnectivityReader(icmpHost: icmpHost ?? "223.5.5.5") { value in
            lock.lock()
            samples += 1
            let count = samples
            lock.unlock()

            print("sample=\(count) status=\(value.status) latency=\(String(format: "%.1f", value.latency)) jitter=\(String(format: "%.1f", value.jitter))")
            if count >= 6 {
                exit(0)
            }
        }
        reader.start()
        Thread.sleep(forTimeInterval: 20)
        write("no sample")
        exit(1)
    }

    static func publicIP() {
        let semaphore = DispatchSemaphore(value: 0)
        var result: PublicAddress?
        PublicIP.fetch { address in
            result = address
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 12)
        guard let result else {
            write("public ip fetch failed")
            exit(1)
        }
        print("ipv4=\(result.v4 ?? "-") ipv6=\(result.v6 ?? "-") country=\(result.country ?? "-")")
    }

    static func run(seconds: Double) {
        let interface = InterfaceResolver.primary()
        guard !interface.isEmpty else {
            write("no primary interface")
            exit(1)
        }
        guard let start = InterfaceCounters.bytes(for: interface) else {
            write("cannot read counters for \(interface)")
            exit(1)
        }

        let startTS = DispatchTime.now()
        Thread.sleep(forTimeInterval: seconds)
        let endTS = DispatchTime.now()

        guard let end = InterfaceCounters.bytes(for: interface) else {
            write("counters disappeared for \(interface)")
            exit(1)
        }

        let elapsed = max(Double(endTS.uptimeNanoseconds &- startTS.uptimeNanoseconds) / 1_000_000_000, 0.001)
        let download = Int64(Double(max(end.download - start.download, 0)) / elapsed)
        let upload = Int64(Double(max(end.upload - start.upload, 0)) / elapsed)

        print("iface=\(interface) download=\(download) upload=\(upload) interval=\(String(format: "%.2f", elapsed))")
    }

    private static func write(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
