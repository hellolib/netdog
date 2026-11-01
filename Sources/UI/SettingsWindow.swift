import AppKit

final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    var onChange: (() -> Void)?

    private let intervalPopup = NSPopUpButton()
    private let processPopup = NSPopUpButton()
    private let modePopup = NSPopUpButton()
    private let icmpField = NSTextField()
    private let httpField = NSTextField()
    private let publicIPCheck = NSButton()
    private let loginCheck = NSButton()
    private let loginStatus = NSTextField(labelWithString: "")
    private let resetButton = NSButton()

    private let intervals: [Double] = [1, 2, 3, 5]
    private let processOptions = [0, 3, 5, 8]
    private let modes: [ConnectivityMode] = [.auto, .icmp, .http]
    private let modesTitles = ["自动（ICMP 优先，失败回退 HTTP）", "仅 ICMP", "仅 HTTP"]

    private var isLoading = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 370),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "NetDog 设置"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        self.build()
        self.reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func build() {
        let content = NSView()
        self.window?.contentView = content

        self.intervalPopup.addItems(withTitles: self.intervals.map { "\(Int($0)) 秒" })
        self.intervalPopup.target = self
        self.intervalPopup.action = #selector(self.intervalChanged)

        self.processPopup.addItems(withTitles: self.processOptions.map { $0 == 0 ? "关闭" : "\($0)" })
        self.processPopup.target = self
        self.processPopup.action = #selector(self.processChanged)

        self.modePopup.addItems(withTitles: self.modesTitles)
        self.modePopup.target = self
        self.modePopup.action = #selector(self.modeChanged)

        [self.icmpField, self.httpField].forEach { field in
            field.font = .systemFont(ofSize: 12)
            field.delegate = self
            field.target = self
            field.action = #selector(self.hostsChanged)
            field.widthAnchor.constraint(equalToConstant: 280).isActive = true
        }
        self.icmpField.placeholderString = Settings.defaultICMPHost
        self.httpField.placeholderString = Settings.defaultHTTPHost
        [self.intervalPopup, self.processPopup, self.modePopup].forEach {
            $0.widthAnchor.constraint(equalToConstant: 280).isActive = true
        }

        self.publicIPCheck.setButtonType(.switch)
        self.publicIPCheck.title = "在弹窗中显示公网 IP（启动时获取一次）"
        self.publicIPCheck.target = self
        self.publicIPCheck.action = #selector(self.publicIPToggled)

        self.loginCheck.setButtonType(.switch)
        self.loginCheck.title = "登录时自动启动"
        self.loginCheck.target = self
        self.loginCheck.action = #selector(self.loginToggled)

        self.loginStatus.font = .systemFont(ofSize: 10)
        self.loginStatus.textColor = .secondaryLabelColor
        self.loginStatus.lineBreakMode = .byTruncatingTail

        self.resetButton.title = "恢复默认设置"
        self.resetButton.bezelStyle = .rounded
        self.resetButton.target = self
        self.resetButton.action = #selector(self.resetTapped)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let footer = NSTextField(labelWithString: "NetDog \(version) · 数据口径：全接口（含 VPN），进程排行来自 nettop")
        footer.font = .systemFont(ofSize: 10)
        footer.textColor = .tertiaryLabelColor

        let grid = NSGridView(views: [
            [self.label("刷新间隔"), self.intervalPopup],
            [self.label("进程排行数量"), self.processPopup],
            [self.label("连通性检测"), self.modePopup],
            [self.label("ICMP 主机"), self.icmpField],
            [self.label("HTTP 地址"), self.httpField],
            [NSView(), self.publicIPCheck],
            [NSView(), self.loginCheck],
            [NSView(), self.loginStatus],
            [NSView(), self.resetButton]
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        footer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)
        content.addSubview(footer)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            footer.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20)
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 12)
        field.textColor = .secondaryLabelColor
        return field
    }

    private func reload() {
        self.isLoading = true

        if let index = self.intervals.firstIndex(of: Settings.updateInterval) {
            self.intervalPopup.selectItem(at: index)
        } else {
            self.intervalPopup.selectItem(at: 0)
        }

        if let index = self.processOptions.firstIndex(of: Settings.processCount) {
            self.processPopup.selectItem(at: index)
        } else {
            self.processPopup.selectItem(at: self.processOptions.firstIndex(of: Settings.defaultProcessCount) ?? 0)
        }

        if let index = self.modes.firstIndex(of: Settings.connectivityMode) {
            self.modePopup.selectItem(at: index)
        }

        self.icmpField.stringValue = Settings.icmpHost
        self.httpField.stringValue = Settings.httpHost
        self.publicIPCheck.state = Settings.publicIPEnabled ? .on : .off
        self.loginCheck.state = LoginItem.isEnabled ? .on : .off
        self.loginStatus.stringValue = LoginItem.statusText

        self.isLoading = false
    }

    private func notify() {
        guard !self.isLoading else { return }
        self.onChange?()
    }

    // MARK: - actions

    @objc private func intervalChanged() {
        let index = max(self.intervalPopup.indexOfSelectedItem, 0)
        Settings.set(self.intervals[index], for: Settings.Keys.updateInterval)
        self.notify()
    }

    @objc private func processChanged() {
        let index = max(self.processPopup.indexOfSelectedItem, 0)
        Settings.set(self.processOptions[index], for: Settings.Keys.processCount)
        self.notify()
    }

    @objc private func modeChanged() {
        let index = max(self.modePopup.indexOfSelectedItem, 0)
        Settings.set(self.modes[index].rawValue, for: Settings.Keys.connectivityMode)
        self.notify()
    }

    @objc private func hostsChanged() {
        Settings.set(self.icmpField.stringValue.trimmingCharacters(in: .whitespaces), for: Settings.Keys.icmpHost)
        Settings.set(self.httpField.stringValue.trimmingCharacters(in: .whitespaces), for: Settings.Keys.httpHost)
        self.notify()
    }

    @objc private func publicIPToggled() {
        Settings.set(self.publicIPCheck.state == .on, for: Settings.Keys.publicIP)
        self.notify()
    }

    @objc private func loginToggled() {
        let enable = self.loginCheck.state == .on
        if let error = LoginItem.set(enable) {
            let alert = NSAlert()
            alert.messageText = "无法设置登录项"
            alert.informativeText = error
            alert.runModal()
            self.loginCheck.state = enable ? .off : .on
        }
        self.loginStatus.stringValue = LoginItem.statusText
    }

    @objc private func resetTapped() {
        Settings.reset()
        self.reload()
        self.notify()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        self.hostsChanged()
    }
}
