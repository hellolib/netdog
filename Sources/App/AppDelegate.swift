import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 58)
    private let speedView = SpeedStatusView(frame: NSRect(x: 0, y: 0, width: 58, height: 22))
    private let chart = NetworkChartView()
    private let menu = NSMenu()
    private var publicIPTimer: Timer?

    private lazy var popupView = PopupView(chart: self.chart)
    private lazy var popupWindow: PopupWindowController = {
        let controller = PopupWindowController(content: self.popupView)
        controller.onOpenSettings = { [weak self] in self?.showSettings() }
        controller.onOpenActivityMonitor = { [weak self] in self?.openActivityMonitor() }
        return controller
    }()
    private lazy var settingsWindow: SettingsWindowController = {
        let controller = SettingsWindowController()
        controller.onChange = { [weak self] in
            self?.applySettings()
        }
        return controller
    }()

    private var reader: UsageReader?
    private var processReader: ProcessReader?
    private var connectivityReader: ConnectivityReader?
    private var lastUsage: NetworkUsage?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LocationAuth.shared.onChange = { [weak self] in
            self?.reader?.refreshDetails()
        }
        self.configureStatusItem()
        self.configureMenu()
        self.configurePopup()
        self.configureReader()
        self.observeSleepWake()
    }

    func applicationWillTerminate(_ notification: Notification) {
        self.reader?.persistNow()
        self.reader?.stop()
        self.processReader?.stop()
        self.connectivityReader?.stop()
    }

    // MARK: - status item

    private func configureStatusItem() {
        guard let button = self.statusItem.button else { return }
        self.statusItem.length = self.speedView.preferredWidth
        self.speedView.frame = button.bounds
        self.speedView.autoresizingMask = [.width, .height]
        self.speedView.onWidthChange = { [weak self] width in
            guard let self else { return }
            self.statusItem.length = width
            if let button = self.statusItem.button {
                self.speedView.frame = button.bounds
            }
        }
        button.title = ""
        button.addSubview(self.speedView)
        button.toolTip = "NetDog"
        button.target = self
        button.action = #selector(self.statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenu() {
        let version = "NetDog \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")"
        let versionItem = NSMenuItem(title: version, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        self.menu.addItem(versionItem)
        self.menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(self.showSettings), keyEquivalent: ",")
        settingsItem.target = self
        self.menu.addItem(settingsItem)
        let refreshItem = NSMenuItem(title: "刷新公网 IP", action: #selector(self.refreshPublicIP), keyEquivalent: "")
        refreshItem.target = self
        self.menu.addItem(refreshItem)
        self.menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 NetDog", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        self.menu.addItem(quitItem)
    }

    @objc private func statusItemClicked() {
        guard let button = self.statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            self.menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        } else {
            self.togglePopup()
        }
    }

    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow.showWindow(nil)
        self.settingsWindow.window?.makeKeyAndOrderFront(nil)
    }

    private func applySettings() {
        self.speedView.configure()
        self.statusItem.length = self.speedView.preferredWidth
        if let button = self.statusItem.button {
            self.speedView.frame = button.bounds
        }
        self.chart.reconfigure()
        self.popupView.applySettings()

        self.reader?.setInterval(Settings.updateInterval)
        self.connectivityReader?.setInterval(TimeInterval(Settings.connectivityInterval))
        self.connectivityReader?.reconfigure(
            icmpHost: Settings.icmpHost,
            httpURL: Settings.httpURL,
            mode: Settings.connectivityMode
        )
        self.popupView.processLimit = Settings.processCount
        if Settings.processCount == 0 {
            self.popupView.clearProcesses()
        }
        if Settings.publicIPEnabled {
            self.refreshPublicIP()
        } else {
            self.popupView.clearPublicIP()
        }
        self.schedulePublicIPRefresh()
    }

    // MARK: - popup

    private func configurePopup() {
        self.popupView.onSizeChange = { [weak self] _ in
            self?.popupWindow.resizeToFit()
        }
        self.popupView.onRequestLocation = {
            LocationAuth.shared.request()
        }
        self.popupView.onRefreshPublicIP = { [weak self] in
            self?.refreshPublicIP()
        }
        self.popupView.onResetTotals = { [weak self] in
            self?.reader?.resetTotal()
        }
    }

    private func togglePopup() {
        guard let button = self.statusItem.button else { return }
        if let usage = self.lastUsage {
            self.popupView.update(usage)
        }
        self.popupWindow.toggle(at: button)
    }

    private func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
        UserDefaults(suiteName: "com.apple.ActivityMonitor")?.set(4, forKey: "SelectedTab")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - reader

    private func configureReader() {
        let reader = UsageReader(interval: Settings.updateInterval, authorization: { LocationAuth.shared.status }) { [weak self] usage in
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastUsage = usage
                self.chart.addValue(upload: Double(usage.bandwidth.upload), download: Double(usage.bandwidth.download))

                var menuDownload = usage.bandwidth.download
                var menuUpload = usage.bandwidth.upload
                if Settings.thresholdEnabled {
                    let threshold = Settings.thresholdBytes
                    if menuDownload < threshold, menuUpload < threshold {
                        menuDownload = 0
                        menuUpload = 0
                    }
                }
                self.speedView.update(download: menuDownload, upload: menuUpload)
                self.popupView.update(usage)
                self.statusItem.button?.toolTip = self.toolTip(for: usage)
            }
        }
        self.reader = reader
        reader.start()

        let processReader = ProcessReader { [weak self] processes in
            DispatchQueue.main.async {
                self?.popupView.updateProcesses(processes)
            }
        }
        self.processReader = processReader
        processReader.start()

        let connectivityReader = ConnectivityReader { [weak self] value in
            DispatchQueue.main.async {
                self?.popupView.updateConnectivity(value)
            }
        }
        self.connectivityReader = connectivityReader
        connectivityReader.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            if Settings.publicIPEnabled {
                self?.refreshPublicIP()
            }
        }
        self.schedulePublicIPRefresh()
    }

    private func schedulePublicIPRefresh() {
        self.publicIPTimer?.invalidate()
        self.publicIPTimer = nil
        guard Settings.publicIPEnabled, let interval = Settings.publicIPRefreshSeconds else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshPublicIP()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.publicIPTimer = timer
    }

    @objc private func refreshPublicIP() {
        guard Settings.publicIPEnabled else {
            self.popupView.clearPublicIP()
            return
        }
        PublicIP.fetch { [weak self] address in
            guard let self, let address, Settings.publicIPEnabled else { return }
            DispatchQueue.main.async {
                self.popupView.updatePublicIP(address)
            }
        }
    }

    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func willSleep() {
        self.popupWindow.hide()
        self.reader?.persistNow()
        self.reader?.stop()
        self.processReader?.stop()
        self.connectivityReader?.stop()
    }

    @objc private func didWake() {
        self.reader?.start()
        self.processReader?.start()
        self.connectivityReader?.start()
    }

    private func toolTip(for usage: NetworkUsage) -> String {
        guard usage.status else { return "无网络连接" }
        let name: String
        if let info = usage.interface {
            name = "\(info.displayName) (\(info.bsdName))"
        } else {
            name = "未知接口"
        }
        return """
        \(name)
        下载 \(Units.readableSpeed(usage.bandwidth.download)) · 上传 \(Units.readableSpeed(usage.bandwidth.upload))
        本次运行累计 ↓\(Units.readableMemory(usage.total.download)) ↑\(Units.readableMemory(usage.total.upload))
        """
    }
}
