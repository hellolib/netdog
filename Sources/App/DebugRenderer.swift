import AppKit

/// Renders UI into PNGs offscreen so the popup can be inspected without
/// screen-recording permission: `NetDog --render <dir>`.
enum DebugRenderer {
    static func render(to directory: String) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared

        let chart = NetworkChartView(num: 180)
        for index in 0..<180 {
            let t = Double(index)
            chart.addValue(
                upload: max(0, 40_000 + 30_000 * sin(t / 9)),
                download: max(0, 1_400_000 + 1_000_000 * sin(t / 6))
            )
        }

        let popup = PopupView(chart: chart)
        var usage = NetworkUsage()
        usage.bandwidth = Bandwidth(upload: 320_000, download: 1_240_000)
        usage.total = Bandwidth(upload: 8_400_000_000, download: 42_300_000_000)
        usage.interface = InterfaceInfo(bsdName: "en0", displayName: "Wi-Fi", mac: "{{MAC_bmb9luf0}}", status: true, transmitRate: 1201)
        usage.connectionType = .wifi
        usage.laddr = LocalAddresses(v4: "192.168.1.7", v6: "2409:8a00:6030:d9f0:419:2139:6fc3:720")
        usage.wifi = WiFiDetails(
            ssid: "HomeWiFi",
            bssid: "AA:BB:CC:DD:EE:FF",
            countryCode: "CN",
            rssi: -55,
            noise: -92,
            standard: "802.11ax",
            mode: "Station",
            security: "WPA2 Personal",
            channel: "11 (2 GHz, 20 MHz)",
            channelBand: "2 GHz",
            channelWidth: "20 MHz",
            channelNumber: "11"
        )
        usage.wifiAuthorization = .authorized
        usage.status = true
        popup.update(usage)
        popup.updateConnectivity(Connectivity(status: true, latency: 23, jitter: 4))
        popup.updatePublicIP(PublicAddress(v4: "43.207.234.85", v6: "2409:8a00:6030:d9f0:85a:eb5f:8c9f:f71d", country: "JP"))
        popup.updateProcesses([
            ProcessUsage(pid: 501, name: "Safari", download: 2_400_000, upload: 120_000, lastActive: Date()),
            ProcessUsage(pid: 733, name: "Qoder", download: 860_000, upload: 45_000, lastActive: Date()),
            ProcessUsage(pid: 412, name: "mDNSResponder", download: 45_000, upload: 8_000, lastActive: Date()),
            ProcessUsage(pid: 233, name: "com.apple.WebKit.Networking", download: 12_000, upload: 1_200, lastActive: Date()),
            ProcessUsage(pid: 88, name: "apsd", download: 3_000, upload: 900, lastActive: Date())
        ])
        popup.appearance = NSAppearance(named: .aqua)
        render(view: popup, to: directory + "/popup.png", background: .windowBackgroundColor)

        let bar = SpeedStatusView(frame: NSRect(x: 0, y: 0, width: 58, height: 22))
        bar.appearance = NSAppearance(named: .aqua)
        bar.update(download: 1_240_000, upload: 320_000)
        render(view: bar, to: directory + "/menubar.png", background: NSColor(calibratedWhite: 0.95, alpha: 1))

        let settings = SettingsWindowController()
        if let content = settings.window?.contentView {
            content.appearance = NSAppearance(named: .aqua)
            render(view: content, to: directory + "/settings.png", background: .windowBackgroundColor)
        }
    }

    private static func render(view: NSView, to path: String, background: NSColor) {
        layoutTree(view)
        view.layoutSubtreeIfNeeded()

        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else {
            print("skip \(path): zero size")
            return
        }
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            print("skip \(path): bitmap allocation failed")
            return
        }
        rep.size = size

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            print("skip \(path): context creation failed")
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        background.setFill()
        NSRect(origin: .zero, size: size).fill()
        view.displayIgnoringOpacity(view.bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("skip \(path): png encoding failed")
            return
        }
        try? data.write(to: URL(fileURLWithPath: path))
        print("rendered \(path) \(Int(size.width))x\(Int(size.height))pt")
    }

    private static func layoutTree(_ view: NSView) {
        view.needsLayout = true
        for subview in view.subviews {
            layoutTree(subview)
        }
    }
}
