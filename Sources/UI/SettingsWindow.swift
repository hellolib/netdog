import AppKit
import SystemConfiguration

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Scrollable settings window covering the full Stats network option set.
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    var onChange: (() -> Void)?

    private let scrollView = NSScrollView()
    private let stack = NSStackView()

    private var interfacePopup: NSPopUpButton?
    private var fixedScaleRow: NSView?
    private var thresholdRow: NSView?
    private var publicIPRefreshPopup: NSPopUpButton?
    private var loginCheck: NSButton?
    private let loginStatus = NSTextField(labelWithString: "")

    private let intervals: [Double] = [1, 2, 3, 5, 10, 15, 30, 60]
    private let processOptions = [0, 3, 5, 8, 10, 15]
    private let chartHistories = [60, 90, 180, 360]
    private let connectivityIntervals = [1, 2, 3, 5, 10, 30, 60]

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 660),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NetDog 设置"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 420)
        window.center()
        super.init(window: window)
        self.build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - build

    private func build() {
        let content = FlippedView()
        self.window?.contentView = content

        self.scrollView.hasVerticalScroller = true
        self.scrollView.autohidesScrollers = true
        self.scrollView.drawsBackground = false
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false

        self.stack.orientation = .vertical
        self.stack.alignment = .leading
        self.stack.spacing = 10
        self.stack.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(self.stack)
        self.scrollView.documentView = document
        content.addSubview(self.scrollView)

        NSLayoutConstraint.activate([
            self.scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            self.scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            document.widthAnchor.constraint(equalTo: self.scrollView.contentView.widthAnchor),

            self.stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 18),
            self.stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            self.stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
            self.stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -18)
        ])

        self.populate()
    }

    private func populate() {
        self.stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        self.addSection("通用", rows: [
            self.row("刷新间隔", control: self.makePopup(
                key: Settings.Keys.updateInterval,
                items: self.intervals.map { ("\(Int($0)) 秒", $0 as Any) },
                selected: Settings.updateInterval
            )),
            self.row("数据源", control: self.makePopup(
                key: Settings.Keys.readerType,
                items: [("按接口", "interface"), ("按进程（nettop）", "process")],
                selected: Settings.readerType
            )),
            self.row("网络接口", control: self.makeInterfacePopup()),
            self.row("进程排行数量", control: self.makePopup(
                key: Settings.Keys.processCount,
                items: self.processOptions.map { ($0 == 0 ? "关闭" : "\($0)", $0 as Any) },
                selected: Settings.processCount
            ))
        ])

        self.addSection("显示", rows: [
            self.row("速率基准", control: self.makePopup(
                key: Settings.Keys.base,
                items: [("字节（B）", "byte"), ("比特（b）", "bit")],
                selected: Settings.base.rawValue
            )),
            self.row("速度单位", control: self.makePopup(
                key: Settings.Keys.speedUnit,
                items: [("自动", "auto"), ("KB/s", "KB"), ("MB/s", "MB"), ("GB/s", "GB"), ("TB/s", "TB")],
                selected: Settings.speedUnit
            )),
            self.row("菜单栏行数", control: self.makePopup(
                key: Settings.Keys.menuBarMode,
                items: [("双行", "twoRows"), ("单行", "oneRow")],
                selected: Settings.menuBarMode
            )),
            self.row("菜单栏图标", control: self.makePopup(
                key: Settings.Keys.menuBarIcon,
                items: [("圆点", "dots"), ("箭头", "arrows"), ("无", "none")],
                selected: Settings.menuBarIcon
            )),
            self.makeSwitchRow("菜单栏显示单位", key: Settings.Keys.menuBarUnits, state: Settings.menuBarUnits),
            self.makeSwitchRow("单色模式", key: Settings.Keys.menuBarMono, state: Settings.menuBarMono),
            self.makeSwitchRow("速率低于阈值时显示 0", key: Settings.Keys.thresholdState, state: Settings.thresholdEnabled),
            self.row("阈值", control: self.makeThresholdControl()),
            self.makeSwitchRow("公网 IP 显示国旗", key: Settings.Keys.emojiCC, state: Settings.emojiCC)
        ])

        self.addSection("图表", rows: [
            self.row("历史采样点", control: self.makePopup(
                key: Settings.Keys.chartHistory,
                items: self.chartHistories.map { ("\($0)", $0 as Any) },
                selected: Settings.chartHistory
            )),
            self.row("缩放", control: self.makePopup(
                key: Settings.Keys.chartScale,
                items: [("线性", "none"), ("平方", "square"), ("立方", "cube"), ("对数", "logarithmic"), ("固定上限", "fixed")],
                selected: Settings.chartScale.rawValue
            )),
            self.row("固定上限", control: self.makeFixedScaleControl()),
            self.makeSwitchRow("上传显示在上方", key: Settings.Keys.reverseOrder, state: Settings.reverseOrder),
            self.row("下载颜色", control: self.makeColorWell(key: Settings.Keys.downloadColor, color: Settings.downloadColor)),
            self.row("上传颜色", control: self.makeColorWell(key: Settings.Keys.uploadColor, color: Settings.uploadColor))
        ])

        self.addSection("用量统计", rows: [
            self.row("重置策略", control: self.makePopup(
                key: Settings.Keys.usageReset,
                items: [("从不", "never"), ("启动时", "atStart"), ("每天", "daily"), ("每周", "weekly"), ("每月", "monthly")],
                selected: Settings.usageReset.rawValue
            ))
        ])

        self.addSection("公网 IP", rows: [
            self.makeSwitchRow("显示公网 IP", key: Settings.Keys.publicIP, state: Settings.publicIPEnabled),
            self.row("自动刷新", control: self.makePublicIPRefreshPopup())
        ])

        self.addSection("连通性", rows: [
            self.row("检测方式", control: self.makePopup(
                key: Settings.Keys.connectivityMode,
                items: [("自动（ICMP 优先）", "auto"), ("仅 ICMP", "icmp"), ("仅 HTTP", "http")],
                selected: Settings.connectivityMode.rawValue
            )),
            self.row("ICMP 主机", control: self.makeField(key: Settings.Keys.icmpHost, value: Settings.icmpHost, placeholder: Settings.defaultICMPHost)),
            self.row("HTTP 地址", control: self.makeField(key: Settings.Keys.httpHost, value: Settings.httpHost, placeholder: Settings.defaultHTTPHost)),
            self.row("检测间隔", control: self.makePopup(
                key: Settings.Keys.connectivityInterval,
                items: self.connectivityIntervals.map { ("\($0) 秒", $0 as Any) },
                selected: Settings.connectivityInterval
            ))
        ])

        self.addSection("启动", rows: [
            self.makeLoginRow()
        ])

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 12
        footer.alignment = .centerY
        let resetButton = NSButton(title: "恢复默认设置", target: self, action: #selector(self.resetTapped))
        resetButton.bezelStyle = .rounded
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let versionLabel = NSTextField(labelWithString: "NetDog \(version)")
        versionLabel.font = .systemFont(ofSize: 10)
        versionLabel.textColor = .tertiaryLabelColor
        footer.addArrangedSubview(resetButton)
        footer.addArrangedSubview(versionLabel)
        self.stack.addArrangedSubview(footer)

        self.updateVisibility()
    }

    private func addSection(_ title: String, rows: [NSView]) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        let section = NSStackView(views: [titleLabel] + rows)
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8

        self.stack.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: self.stack.widthAnchor).isActive = true
        for row in rows {
            row.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }
    }

    // MARK: - controls

    private func row(_ title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.lineBreakMode = .byClipping
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makeSwitchRow(_ title: String, key: String, state: Bool) -> NSView {
        let check = NSButton(checkboxWithTitle: title, target: self, action: #selector(self.switchChanged(_:)))
        check.identifier = NSUserInterfaceItemIdentifier(key)
        check.state = state ? .on : .off
        check.font = .systemFont(ofSize: 12)
        return check
    }

    private func makePopup(key: String, items: [(String, Any)], selected: Any) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.identifier = NSUserInterfaceItemIdentifier(key)
        for (title, value) in items {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = value
            popup.menu?.addItem(item)
        }
        popup.target = self
        popup.action = #selector(self.popupChanged(_:))
        popup.widthAnchor.constraint(equalToConstant: 260).isActive = true

        for item in popup.itemArray {
            if let value = item.representedObject as? String, let selected = selected as? String, value == selected {
                popup.select(item)
                break
            }
            if let value = item.representedObject as? Int, let selected = selected as? Int, value == selected {
                popup.select(item)
                break
            }
            if let value = item.representedObject as? Double, let selected = selected as? Double, value == selected {
                popup.select(item)
                break
            }
            if let value = item.representedObject as? Int, let selected = selected as? Double, Double(value) == selected {
                popup.select(item)
                break
            }
        }
        return popup
    }

    private func makeInterfacePopup() -> NSPopUpButton {
        var items: [(String, Any)] = [("自动检测", "")]
        for item in SCNetworkInterfaceCopyAll() as NSArray {
            let sc = item as! SCNetworkInterface
            guard let bsd = SCNetworkInterfaceGetBSDName(sc) else { continue }
            let name = bsd as String
            var title = name
            if let display = SCNetworkInterfaceGetLocalizedDisplayName(sc) {
                title = "\(display) (\(name))"
            }
            items.append((title, name))
        }

        let popup = self.makePopup(key: Settings.Keys.interfaceName, items: items, selected: Settings.interfaceName)
        self.interfacePopup = popup
        return popup
    }

    private func makeThresholdControl() -> NSView {
        let value = NSTextField(string: Settings.threshold > 0 ? "\(Settings.threshold)" : "")
        value.identifier = NSUserInterfaceItemIdentifier(Settings.Keys.threshold)
        value.font = .systemFont(ofSize: 12)
        value.alignment = .right
        value.delegate = self
        value.target = self
        value.action = #selector(self.thresholdChanged(_:))
        value.widthAnchor.constraint(equalToConstant: 70).isActive = true

        let unit = self.makePopup(
            key: Settings.Keys.thresholdSize,
            items: SizeUnit.allCases.map { ("\($0.rawValue)", $0.rawValue) },
            selected: Settings.thresholdSize
        )

        let row = NSStackView(views: [value, unit])
        row.orientation = .horizontal
        row.spacing = 8
        self.thresholdRow = row
        return row
    }

    private func makeFixedScaleControl() -> NSView {
        let value = NSTextField(string: "\(Settings.chartFixedScale)")
        value.identifier = NSUserInterfaceItemIdentifier(Settings.Keys.chartFixedScale)
        value.font = .systemFont(ofSize: 12)
        value.alignment = .right
        value.delegate = self
        value.target = self
        value.action = #selector(self.fixedScaleChanged(_:))
        value.widthAnchor.constraint(equalToConstant: 70).isActive = true

        let unit = self.makePopup(
            key: Settings.Keys.chartFixedScaleSize,
            items: SizeUnit.allCases.map { ("\($0.rawValue)", $0.rawValue) },
            selected: Settings.chartFixedScaleSize
        )

        let row = NSStackView(views: [value, unit])
        row.orientation = .horizontal
        row.spacing = 8
        self.fixedScaleRow = row
        return row
    }

    private func makeColorWell(key: String, color: NSColor) -> NSColorWell {
        let well = NSColorWell()
        well.identifier = NSUserInterfaceItemIdentifier(key)
        well.color = color
        well.target = self
        well.action = #selector(self.colorChanged(_:))
        well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return well
    }

    private func makeField(key: String, value: String, placeholder: String) -> NSTextField {
        let field = NSTextField(string: value)
        field.identifier = NSUserInterfaceItemIdentifier(key)
        field.font = .systemFont(ofSize: 12)
        field.placeholderString = placeholder
        field.delegate = self
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true
        return field
    }

    private func makePublicIPRefreshPopup() -> NSPopUpButton {
        let popup = self.makePopup(
            key: Settings.Keys.publicIPRefresh,
            items: [("从不", "never"), ("每小时", "hour"), ("每 12 小时", "12"), ("每 24 小时", "24")],
            selected: Settings.publicIPRefresh
        )
        self.publicIPRefreshPopup = popup
        return popup
    }

    private func makeLoginRow() -> NSView {
        let check = NSButton(checkboxWithTitle: "登录时自动启动", target: self, action: #selector(self.loginToggled))
        check.state = LoginItem.isEnabled ? .on : .off
        self.loginCheck = check

        self.loginStatus.font = .systemFont(ofSize: 10)
        self.loginStatus.textColor = .secondaryLabelColor
        self.loginStatus.lineBreakMode = .byClipping
        self.loginStatus.stringValue = LoginItem.statusText

        let row = NSStackView(views: [check, self.loginStatus])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 4
        return row
    }

    // MARK: - actions

    @objc private func popupChanged(_ sender: NSPopUpButton) {
        guard let key = sender.identifier?.rawValue, let value = sender.selectedItem?.representedObject else { return }
        if let number = value as? Int {
            Settings.set(number, for: key)
        } else {
            Settings.set(value as? String ?? "", for: key)
        }
        self.changed(key: key)
    }

    @objc private func switchChanged(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        Settings.set(sender.state == .on, for: key)
        self.changed(key: key)
    }

    @objc private func thresholdChanged(_ sender: NSTextField) {
        let value = max(Int(sender.stringValue) ?? 0, 0)
        Settings.set(value, for: Settings.Keys.threshold)
        self.changed(key: Settings.Keys.threshold)
    }

    @objc private func fixedScaleChanged(_ sender: NSTextField) {
        let value = max(Int(sender.stringValue) ?? 1, 1)
        Settings.set(value, for: Settings.Keys.chartFixedScale)
        self.changed(key: Settings.Keys.chartFixedScale)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        guard let key = sender.identifier?.rawValue else { return }
        Settings.setColor(sender.color, for: key)
        self.changed(key: key)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let key = field.identifier?.rawValue else { return }
        if key == Settings.Keys.threshold || key == Settings.Keys.chartFixedScale {
            return
        }
        Settings.set(field.stringValue.trimmingCharacters(in: .whitespaces), for: key)
        self.changed(key: key)
    }

    @objc private func loginToggled() {
        let enable = self.loginCheck?.state == .on
        if let error = LoginItem.set(enable) {
            let alert = NSAlert()
            alert.messageText = "无法设置登录项"
            alert.informativeText = error
            alert.runModal()
            self.loginCheck?.state = enable ? .off : .on
        }
        self.loginStatus.stringValue = LoginItem.statusText
    }

    @objc private func resetTapped() {
        Settings.reset()
        self.populate()
        self.onChange?()
    }

    private func changed(key: String) {
        self.updateVisibility()
        self.onChange?()
    }

    private func updateVisibility() {
        self.interfacePopup?.isEnabled = Settings.readerType == "interface"
        self.fixedScaleRow?.isHidden = Settings.chartScale != .fixed
        self.thresholdRow?.isHidden = !Settings.thresholdEnabled
        self.publicIPRefreshPopup?.isEnabled = Settings.publicIPEnabled
    }
}
