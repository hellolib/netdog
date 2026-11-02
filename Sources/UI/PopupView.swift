import AppKit

enum PopupMetrics {
    static let width: CGFloat = 264
    static let margins: CGFloat = 8
    static let headerHeight: CGFloat = 42
    static let rowHeight: CGFloat = 22
    static let sectionHeight: CGFloat = 30
    static let dashboardHeight: CGFloat = 90
    static let chartHeight: CGFloat = 90
    static let connectivityHeight: CGFloat = 30
    static let radius: CGFloat = 6
    static let maxProcessRows = Settings.maxProcessCount
}

/// Content of the network popup. Laid out top-down (flipped) so it can be a
/// scroll document view; metrics mirror Stats' Net popup.
final class PopupView: NSView {
    override var isFlipped: Bool { true }

    var onSizeChange: ((NSSize) -> Void)?
    var onRequestLocation: (() -> Void)?
    var onRefreshPublicIP: (() -> Void)?
    var onResetTotals: (() -> Void)?

    private let chart: NetworkChartView
    private let connectivityChart = GridChartView()
    private let dashboard = DashboardPanel()
    private let chartContainer = RoundedPanelView(fill: NSColor.lightGray.withAlphaComponent(0.1), radius: PopupMetrics.radius)
    private let connectivityContainer = RoundedPanelView(fill: NSColor.lightGray.withAlphaComponent(0.1), radius: 3)

    private let totalUpRow = TotalRowView(title: "总上传", color: .systemRed)
    private let totalDownRow = TotalRowView(title: "总下载", color: .systemBlue)
    private let statusRow = BadgeRowView(title: "状态")
    private let internetRow = BadgeRowView(title: "互联网连接")
    private let latencyRow = DetailRowView(title: "延迟")
    private let jitterRow = DetailRowView(title: "抖动")

    private let interfaceRow = DetailRowView(title: "接口")
    private let interfaceStatusRow = BadgeRowView(title: "状态")
    private let macRow = DetailRowView(title: "物理地址")
    private let ssidRow = DetailRowView(title: "网络")
    private let standardRow = DetailRowView(title: "标准")
    private let channelRow = DetailRowView(title: "信道")
    private let speedRow = DetailRowView(title: "速率")

    private let localIPRow = DetailRowView(title: "本地 IP")
    private let publicV4Row = DetailRowView(title: "公网 IP")
    private let publicV6Row = DetailRowView(title: "公网 IP")

    private let locationButton = NSButton(title: "", target: nil, action: nil)
    private let processHeader = SectionHeaderView(title: "进程排行")
    private let processHeaderRow = ProcessHeaderRowView()
    private var processRows: [ProcessRowView] = []

    private var items: [NSView] = []
    private var detailsEnabled = false
    private var isWiFi = false

    private var enabledSections: Set<PopupSection> = Set(PopupSection.allCases)
    private var sectionViews: [(view: NSView, section: PopupSection)] = []
    private var desiredVisible: [ObjectIdentifier: Bool] = [:]

    var processLimit: Int = Settings.processCount {
        didSet {
            guard self.processLimit != oldValue else { return }
            var changed = false
            for (index, row) in self.processRows.enumerated() where index >= self.processLimit {
                self.setVisible(row, false, &changed)
            }
            if self.processLimit == 0 {
                self.setVisible(self.processHeader, false, &changed)
                self.setVisible(self.processHeaderRow, false, &changed)
            }
            if changed {
                self.relayout()
            }
        }
    }

    init(chart: NetworkChartView) {
        self.chart = chart
        super.init(frame: NSRect(x: 0, y: 0, width: PopupMetrics.width, height: 0))
        self.build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func build() {
        self.chartContainer.setFrameSize(NSSize(width: PopupMetrics.width, height: PopupMetrics.chartHeight))
        self.chart.frame = self.chartContainer.bounds.insetBy(dx: 1, dy: 1)
        self.chartContainer.addSubview(self.chart)

        self.connectivityContainer.setFrameSize(NSSize(width: PopupMetrics.width, height: PopupMetrics.connectivityHeight))
        self.connectivityChart.frame = self.connectivityContainer.bounds.insetBy(dx: 1, dy: 1)
        self.connectivityContainer.addSubview(self.connectivityChart)

        self.locationButton.bezelStyle = .rounded
        self.locationButton.controlSize = .small
        self.locationButton.font = .systemFont(ofSize: 11)
        self.locationButton.target = self
        self.locationButton.action = #selector(self.requestLocation)
        self.locationButton.isHidden = true
        self.locationButton.sizeToFit()
        self.ssidRow.addAccessory(self.locationButton)

        let resetButton = Self.symbolButton("arrow.clockwise", tooltip: "重置累计流量")
        resetButton.target = self
        resetButton.action = #selector(self.resetTotals)
        let detailsButton = Self.symbolButton("slider.horizontal.3", tooltip: "显示接口详情")
        detailsButton.target = self
        detailsButton.action = #selector(self.toggleDetails)
        let refreshButton = Self.symbolButton("arrow.clockwise", tooltip: "刷新公网 IP")
        refreshButton.target = self
        refreshButton.action = #selector(self.refreshPublicIP)

        self.detailsEnabled = Settings.interfaceDetails
        self.standardRow.isHidden = !self.detailsEnabled
        self.channelRow.isHidden = !self.detailsEnabled
        self.speedRow.isHidden = !self.detailsEnabled
        self.publicV4Row.isHidden = true
        self.publicV6Row.isHidden = true
        self.processHeader.isHidden = true
        self.processHeaderRow.isHidden = true

        self.processRows = (0..<PopupMetrics.maxProcessRows).map { _ in
            let row = ProcessRowView(frame: NSRect(x: 0, y: 0, width: PopupMetrics.width, height: PopupMetrics.rowHeight))
            row.isHidden = true
            return row
        }

        let usageHeader = SectionHeaderView(title: "负载历史")
        let connectivityHeader = SectionHeaderView(title: "连接历史")
        let trafficHeader = SectionHeaderView(title: "接口", accessory: resetButton)
        let interfaceHeader = SectionHeaderView(title: "接口", accessory: detailsButton)
        let addressHeader = SectionHeaderView(title: "地址", accessory: refreshButton)

        self.items = [
            self.dashboard,
            usageHeader, self.chartContainer,
            connectivityHeader, self.connectivityContainer,
            trafficHeader,
            self.totalUpRow, self.totalDownRow, self.statusRow, self.internetRow, self.latencyRow, self.jitterRow,
            interfaceHeader,
            self.interfaceRow, self.interfaceStatusRow, self.macRow, self.ssidRow, self.standardRow, self.channelRow, self.speedRow,
            addressHeader,
            self.localIPRow, self.publicV4Row, self.publicV6Row,
            self.processHeader, self.processHeaderRow
        ] + self.processRows

        self.registerSection(.usageHistory, [usageHeader, self.chartContainer])
        self.registerSection(.connectivityHistory, [connectivityHeader, self.connectivityContainer])
        self.registerSection(.traffic, [
            trafficHeader, self.totalUpRow, self.totalDownRow, self.statusRow,
            self.internetRow, self.latencyRow, self.jitterRow
        ])
        self.registerSection(.interfaceInfo, [
            interfaceHeader, self.interfaceRow, self.interfaceStatusRow, self.macRow,
            self.ssidRow, self.standardRow, self.channelRow, self.speedRow
        ])
        self.registerSection(.address, [addressHeader, self.localIPRow, self.publicV4Row, self.publicV6Row])
        self.registerSection(.processes, [self.processHeader, self.processHeaderRow] + self.processRows)

        self.items.forEach { self.addSubview($0) }

        self.enabledSections = Set(Settings.popupSections)
        self.snapshotDesired()
        _ = self.applySectionVisibility()
        self.relayout()
    }

    private func registerSection(_ section: PopupSection, _ views: [NSView]) {
        views.forEach { self.sectionViews.append((view: $0, section: section)) }
    }

    private func section(for view: NSView) -> PopupSection? {
        return self.sectionViews.first { $0.view === view }?.section
    }

    private func snapshotDesired() {
        for entry in self.sectionViews {
            self.desiredVisible[ObjectIdentifier(entry.view)] = !entry.view.isHidden
        }
    }

    /// Re-applies the section toggles on top of the current dynamic visibility.
    func applySettings() {
        self.enabledSections = Set(Settings.popupSections)
        if self.applySectionVisibility() {
            self.relayout()
        }
    }

    private func applySectionVisibility() -> Bool {
        var changed = false
        for entry in self.sectionViews {
            let visible = self.desiredVisible[ObjectIdentifier(entry.view)] ?? true
            let hidden = !(visible && self.enabledSections.contains(entry.section))
            if entry.view.isHidden != hidden {
                entry.view.isHidden = hidden
                changed = true
            }
        }
        return changed
    }

    private static func symbolButton(_ symbol: String, tooltip: String) -> NSButton {
        let button = NSButton()
        button.title = ""
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .lightGray
        button.toolTip = tooltip
        button.frame = NSRect(x: 0, y: 0, width: 20, height: 16)
        return button
    }

    private func relayout() {
        let visible = self.items.filter { !$0.isHidden }
        let height = visible.reduce(CGFloat(0)) { $0 + $1.frame.height }
        self.setFrameSize(NSSize(width: PopupMetrics.width, height: height))

        var y: CGFloat = 0
        for item in visible {
            item.setFrameOrigin(NSPoint(x: 0, y: y))
            y += item.frame.height
        }

        self.onSizeChange?(self.frame.size)
    }

    private func setVisible(_ view: NSView, _ visible: Bool, _ changed: inout Bool) {
        self.desiredVisible[ObjectIdentifier(view)] = visible
        let sectionEnabled = self.section(for: view).map { self.enabledSections.contains($0) } ?? true
        let hidden = !(visible && sectionEnabled)
        guard view.isHidden != hidden else { return }
        view.isHidden = hidden
        changed = true
    }

    // MARK: - updates

    func update(_ usage: NetworkUsage) {
        self.dashboard.update(download: usage.bandwidth.download, upload: usage.bandwidth.upload)
        self.totalDownRow.setValue(Units.readableMemory(usage.total.download))
        self.totalUpRow.setValue(Units.readableMemory(usage.total.upload))
        self.statusRow.set(status: usage.status)

        var changed = false

        if let info = usage.interface {
            var name = "\(info.displayName) (\(info.bsdName))"
            if let country = usage.wifi.countryCode, !country.isEmpty {
                name += ", \(country)"
            }
            self.interfaceRow.setValue(name)
            self.interfaceStatusRow.set(status: info.status)
            self.macRow.setValue(info.mac.isEmpty ? "未知" : info.mac)
            self.speedRow.setValue(info.transmitRate > 0 ? "\(Int(info.transmitRate.rounded()))Mbps" : "未知")
        } else {
            self.interfaceRow.setValue("未知")
            self.interfaceStatusRow.set(status: false)
            self.macRow.setValue("未知")
            self.speedRow.setValue("未知")
        }

        let isWiFi = usage.connectionType == .wifi
        self.isWiFi = isWiFi
        self.setVisible(self.ssidRow, isWiFi, &changed)
        self.setVisible(self.standardRow, self.detailsEnabled && isWiFi, &changed)
        self.setVisible(self.channelRow, self.detailsEnabled && isWiFi, &changed)
        self.setVisible(self.speedRow, self.detailsEnabled, &changed)

        if isWiFi {
            let authorized = usage.wifiAuthorization == .authorized
            self.locationButton.isHidden = authorized
            self.locationButton.title = usage.wifiAuthorization == .notDetermined ? "允许访问 Wi-Fi 详情" : "打开定位设置"
            self.locationButton.sizeToFit()
            self.ssidRow.needsLayout = true
            self.ssidRow.setValueHidden(!authorized)
            if authorized {
                var text = usage.wifi.ssid ?? "未知"
                if let rssi = usage.wifi.rssi {
                    text += " (\(rssi))"
                }
                self.ssidRow.setValue(text)
            }
            self.standardRow.setValue(usage.wifi.standard ?? "未知")
            self.channelRow.setValue(usage.wifi.channel ?? "未知")
            if let rssi = usage.wifi.rssi, let noise = usage.wifi.noise {
                self.channelRow.toolTip = "RSSI: \(rssi) dBm\nNoise: \(noise) dBm\n频段: \(usage.wifi.channelBand ?? "未知")\n带宽: \(usage.wifi.channelWidth ?? "未知")"
            } else {
                self.channelRow.toolTip = nil
            }
        }

        self.localIPRow.setValue(usage.laddr.v4 ?? usage.laddr.v6 ?? "未知")

        if changed {
            self.relayout()
        }
    }

    func updateConnectivity(_ value: Connectivity) {
        self.internetRow.set(status: value.status)
        self.latencyRow.setValue(value.status ? "\(Int(value.latency.rounded())) ms" : "")
        self.jitterRow.setValue(value.status ? "\(Int(value.jitter.rounded())) ms" : "")
        self.connectivityChart.addValue(value.status)
    }

    func updatePublicIP(_ address: PublicAddress?) {
        var changed = false

        if let v4 = address?.v4, !v4.isEmpty {
            var text = v4
            if let country = address?.country, !country.isEmpty {
                if Settings.emojiCC, let flag = countryFlag(country) {
                    text += " \(flag)"
                } else {
                    text += " (\(country))"
                }
            }
            self.publicV4Row.setValue(text)
            self.setVisible(self.publicV4Row, true, &changed)
        }

        if let v6 = address?.v6, !v6.isEmpty {
            var text = v6
            if let country = address?.country, !country.isEmpty {
                if Settings.emojiCC, let flag = countryFlag(country) {
                    text += " \(flag)"
                } else {
                    text += " (\(country))"
                }
            }
            self.publicV6Row.setValue(text)
            self.setVisible(self.publicV6Row, true, &changed)
        }

        if changed {
            self.relayout()
        }
    }

    func updateProcesses(_ processes: [ProcessUsage]) {
        let limit = min(processes.count, self.processLimit)
        guard limit > 0 else { return }
        var changed = false

        self.setVisible(self.processHeader, true, &changed)
        self.setVisible(self.processHeaderRow, true, &changed)

        for (index, row) in self.processRows.enumerated() {
            if index < limit {
                row.update(processes[index])
                self.setVisible(row, true, &changed)
            } else {
                row.update(nil)
                self.setVisible(row, false, &changed)
            }
        }

        if changed {
            self.relayout()
        }
    }

    func clearProcesses() {
        var changed = false
        self.setVisible(self.processHeader, false, &changed)
        self.setVisible(self.processHeaderRow, false, &changed)
        for row in self.processRows {
            self.setVisible(row, false, &changed)
        }
        if changed {
            self.relayout()
        }
    }

    func clearPublicIP() {
        var changed = false
        self.setVisible(self.publicV4Row, false, &changed)
        self.setVisible(self.publicV6Row, false, &changed)
        if changed {
            self.relayout()
        }
    }

    // MARK: - actions

    @objc private func requestLocation() {
        self.onRequestLocation?()
    }

    @objc private func refreshPublicIP() {
        self.onRefreshPublicIP?()
    }

    @objc private func resetTotals() {
        self.onResetTotals?()
    }

    @objc private func toggleDetails() {
        self.detailsEnabled.toggle()
        Settings.set(self.detailsEnabled, for: Settings.Keys.interfaceDetails)
        var changed = false
        self.setVisible(self.standardRow, self.detailsEnabled && self.isWiFi, &changed)
        self.setVisible(self.channelRow, self.detailsEnabled && self.isWiFi, &changed)
        self.setVisible(self.speedRow, self.detailsEnabled, &changed)
        if changed {
            self.relayout()
        }
    }
}

// MARK: - dashboard

private final class DashboardPanel: NSView {
    private let download = MetricView(title: "下载", color: .systemBlue)
    private let upload = MetricView(title: "上传", color: .systemRed)

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: PopupMetrics.width, height: PopupMetrics.dashboardHeight))
        self.addSubview(self.download)
        self.addSubview(self.upload)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        let half = self.bounds.width / 2
        self.download.frame = NSRect(x: 0, y: 0, width: half, height: self.bounds.height)
        self.upload.frame = NSRect(x: half, y: 0, width: half, height: self.bounds.height)
    }

    func update(download: Int64, upload: Int64) {
        self.download.update(download)
        self.upload.update(upload)
    }
}

private final class MetricView: NSView {
    private let valueField = NSTextField(labelWithString: "0")
    private let unitField = NSTextField(labelWithString: "KB/s")
    private let titleField = NSTextField(labelWithString: "")
    private let dot: DotView

    init(title: String, color: NSColor) {
        self.dot = DotView(size: 12, color: color, radius: 4)
        super.init(frame: .zero)

        self.valueField.font = .systemFont(ofSize: 26, weight: .light)
        self.valueField.alignment = .right
        self.valueField.lineBreakMode = .byClipping
        self.unitField.font = .systemFont(ofSize: 13, weight: .light)
        self.unitField.textColor = .labelColor
        self.unitField.lineBreakMode = .byClipping
        self.titleField.font = .systemFont(ofSize: 11)
        self.titleField.textColor = .secondaryLabelColor
        self.titleField.lineBreakMode = .byClipping
        self.titleField.stringValue = title

        self.addSubview(self.valueField)
        self.addSubview(self.unitField)
        self.addSubview(self.dot)
        self.addSubview(self.titleField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(_ value: Int64) {
        let (readable, unit) = Units.readableTuple(value)
        self.valueField.stringValue = readable
        self.unitField.stringValue = unit
        self.needsLayout = true
    }

    override func layout() {
        super.layout()

        let topHeight: CGFloat = 30
        let titleHeight: CGFloat = 15

        let valueSize = self.valueField.intrinsicContentSize
        let unitSize = self.unitField.intrinsicContentSize
        let valueWidth = valueSize.width + 6
        let unitWidth = unitSize.width + 6
        let topWidth = valueWidth + unitWidth
        let topY = (self.bounds.height - topHeight - titleHeight) / 2 + titleHeight

        self.valueField.frame = NSRect(x: (self.bounds.width - topWidth) / 2, y: topY, width: valueWidth, height: topHeight)
        self.unitField.frame = NSRect(x: self.valueField.frame.maxX, y: topY + 4, width: unitWidth, height: 15)

        let titleWidth = self.titleField.intrinsicContentSize.width + 8
        let dotSize: CGFloat = 12
        let bottomWidth = titleWidth + dotSize
        let bottomY = topY - titleHeight - 2
        self.dot.frame = NSRect(x: (self.bounds.width - bottomWidth) / 2, y: bottomY + 2, width: dotSize, height: dotSize)
        self.titleField.frame = NSRect(x: self.dot.frame.maxX, y: bottomY, width: titleWidth, height: titleHeight)
    }
}

// MARK: - section header

private final class SectionHeaderView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let leftLine = NSView()
    private let rightLine = NSView()
    private let accessory: NSButton?

    init(title: String, accessory: NSButton? = nil) {
        self.accessory = accessory
        super.init(frame: NSRect(x: 0, y: 0, width: PopupMetrics.width, height: PopupMetrics.sectionHeight))

        self.label.attributedStringValue = NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .kern: 1.0
        ])
        self.label.lineBreakMode = .byClipping
        self.label.cell?.usesSingleLineMode = true
        self.leftLine.wantsLayer = true
        self.leftLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        self.rightLine.wantsLayer = true
        self.rightLine.layer?.backgroundColor = NSColor.separatorColor.cgColor

        self.addSubview(self.leftLine)
        self.addSubview(self.label)
        self.addSubview(self.rightLine)
        if let accessory {
            self.addSubview(accessory)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        let size = self.label.intrinsicContentSize
        let gap: CGFloat = 8
        // NSTextField draws its glyphs about 3pt below the frame center at
        // this font size; compensate so the text and the line share a center.
        let textAdjustment: CGFloat = 3.0
        let lineY = self.bounds.height / 2 - 0.5
        // NSTextField truncates the last glyph when the frame matches
        // intrinsicContentSize exactly, so reserve padding.
        let labelWidth = size.width + 8
        self.label.frame = NSRect(
            x: (self.bounds.width - labelWidth) / 2,
            y: (self.bounds.height - size.height) / 2 + textAdjustment,
            width: labelWidth,
            height: size.height
        )

        let rightInset: CGFloat = self.accessory != nil ? 24 : 0
        self.leftLine.frame = NSRect(x: 0, y: lineY, width: max(self.label.frame.minX - gap, 0), height: 1)
        self.rightLine.frame = NSRect(x: self.label.frame.maxX + gap, y: lineY, width: max(self.bounds.width - rightInset - self.label.frame.maxX - gap, 0), height: 1)

        if let accessory {
            accessory.frame = NSRect(x: self.bounds.width - 22, y: (self.bounds.height - 16) / 2, width: 20, height: 16)
        }
    }
}

// MARK: - rows

private final class DetailRowView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")
    private let valueContainer = NSView()

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: PopupMetrics.width, height: PopupMetrics.rowHeight))

        self.label.font = .systemFont(ofSize: 12)
        self.label.textColor = .secondaryLabelColor
        self.label.lineBreakMode = .byClipping
        self.label.stringValue = title

        self.value.font = .systemFont(ofSize: 13)
        self.value.textColor = .textColor
        self.value.alignment = .right
        self.value.lineBreakMode = .byTruncatingMiddle
        self.value.isSelectable = true
        self.value.isBordered = false
        self.value.isEditable = false
        self.value.drawsBackground = false

        self.addSubview(self.label)
        self.addSubview(self.valueContainer)
        self.valueContainer.addSubview(self.value)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setValue(_ text: String) {
        self.value.stringValue = text
    }

    func setValueHidden(_ hidden: Bool) {
        self.value.isHidden = hidden
    }

    func addAccessory(_ view: NSView) {
        self.valueContainer.addSubview(view)
    }

    override func layout() {
        super.layout()
        let labelWidth = self.label.intrinsicContentSize.width + 8
        self.label.frame = NSRect(x: 0, y: (self.bounds.height - 16) / 2, width: labelWidth, height: 16)

        self.valueContainer.frame = NSRect(x: labelWidth, y: 0, width: self.bounds.width - labelWidth, height: self.bounds.height)
        self.value.frame = NSRect(x: 0, y: (self.bounds.height - 16) / 2, width: self.valueContainer.bounds.width, height: 16)

        for subview in self.valueContainer.subviews where subview !== self.value {
            let size = subview.fittingSize
            subview.frame = NSRect(x: self.valueContainer.bounds.width - size.width, y: (self.bounds.height - size.height) / 2, width: size.width, height: size.height)
        }
    }
}

private final class TotalRowView: NSView {
    private let dot: DotView
    private let label = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "0")

    init(title: String, color: NSColor) {
        self.dot = DotView(size: 10, color: color, radius: 3)
        super.init(frame: NSRect(x: 0, y: 0, width: PopupMetrics.width, height: PopupMetrics.rowHeight))

        self.label.font = .systemFont(ofSize: 12)
        self.label.textColor = .secondaryLabelColor
        self.label.lineBreakMode = .byClipping
        self.label.stringValue = title
        self.value.font = .systemFont(ofSize: 13)
        self.value.textColor = .textColor
        self.value.alignment = .right
        self.value.isSelectable = true
        self.value.isBordered = false
        self.value.isEditable = false
        self.value.drawsBackground = false

        self.addSubview(self.dot)
        self.addSubview(self.label)
        self.addSubview(self.value)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setValue(_ text: String) {
        self.value.stringValue = text
    }

    override func layout() {
        super.layout()
        let dotSize: CGFloat = 10
        self.dot.frame = NSRect(x: 3, y: (self.bounds.height - dotSize) / 2, width: dotSize, height: dotSize)
        let labelWidth = min(180, self.label.intrinsicContentSize.width + 8)
        self.label.frame = NSRect(x: 18, y: (self.bounds.height - 16) / 2, width: labelWidth, height: 16)
        self.value.frame = NSRect(x: 18 + labelWidth, y: (self.bounds.height - 16) / 2, width: self.bounds.width - labelWidth - 18, height: 16)
    }
}

private final class BadgeRowView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let badge = BadgeView()

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: PopupMetrics.width, height: PopupMetrics.rowHeight))

        self.label.font = .systemFont(ofSize: 12)
        self.label.textColor = .secondaryLabelColor
        self.label.lineBreakMode = .byClipping
        self.label.stringValue = title

        self.addSubview(self.label)
        self.addSubview(self.badge)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func set(status: Bool?) {
        self.badge.status = status
    }

    override func layout() {
        super.layout()
        let labelWidth = self.label.intrinsicContentSize.width + 8
        self.label.frame = NSRect(x: 0, y: (self.bounds.height - 16) / 2, width: labelWidth, height: 16)
        self.badge.frame = NSRect(x: self.bounds.width - 50, y: (self.bounds.height - 14) / 2, width: 50, height: 14)
    }
}

private final class BadgeView: NSView {
    var status: Bool? {
        didSet { self.needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color = self.status.map { $0 ? NSColor.systemGreen : NSColor.systemRed } ?? NSColor.secondaryLabelColor
        color.setFill()
        NSBezierPath(roundedRect: self.bounds, xRadius: 4, yRadius: 4).fill()

        guard let status = self.status else { return }
        let text = (status ? "UP" : "DOWN") as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .light),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (self.bounds.width - size.width) / 2, y: (self.bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }
}

private final class ProcessHeaderRowView: NSView {
    private let nameField = NSTextField(labelWithString: "进程")
    private let downBlock = DotView(size: 12, color: .systemBlue, radius: 4)
    private let upBlock = DotView(size: 12, color: .systemRed, radius: 4)

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: PopupMetrics.width, height: PopupMetrics.rowHeight))
        self.nameField.font = .systemFont(ofSize: 11, weight: .medium)
        self.nameField.textColor = .tertiaryLabelColor
        self.nameField.lineBreakMode = .byClipping
        self.downBlock.toolTip = "下载"
        self.upBlock.toolTip = "上传"
        self.addSubview(self.nameField)
        self.addSubview(self.downBlock)
        self.addSubview(self.upBlock)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        let valueWidth: CGFloat = 68
        self.nameField.frame = NSRect(x: 22, y: (self.bounds.height - 16) / 2, width: self.bounds.width - 22 - valueWidth * 2, height: 16)
        self.downBlock.frame = NSRect(x: self.bounds.width - valueWidth * 2 + (valueWidth - 12) / 2, y: (self.bounds.height - 12) / 2, width: 12, height: 12)
        self.upBlock.frame = NSRect(x: self.bounds.width - valueWidth + (valueWidth - 12) / 2, y: (self.bounds.height - 12) / 2, width: 12, height: 12)
    }
}

final class ProcessRowView: NSView {
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let downField = NSTextField(labelWithString: "")
    private let upField = NSTextField(labelWithString: "")
    private var currentPID: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        self.iconView.imageScaling = .scaleProportionallyDown

        self.nameField.font = .systemFont(ofSize: 12)
        self.nameField.textColor = .labelColor
        self.nameField.lineBreakMode = .byTruncatingTail

        self.downField.font = .systemFont(ofSize: 10)
        self.downField.textColor = .textColor
        self.downField.alignment = .right
        self.downField.lineBreakMode = .byClipping
        self.upField.font = .systemFont(ofSize: 10)
        self.upField.textColor = .textColor
        self.upField.alignment = .right
        self.upField.lineBreakMode = .byClipping

        self.addSubview(self.iconView)
        self.addSubview(self.nameField)
        self.addSubview(self.downField)
        self.addSubview(self.upField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(_ process: ProcessUsage?) {
        guard let process else {
            self.currentPID = nil
            self.iconView.image = nil
            self.nameField.stringValue = ""
            self.downField.stringValue = ""
            self.upField.stringValue = ""
            self.toolTip = nil
            return
        }

        self.nameField.stringValue = process.name
        self.downField.stringValue = Units.readableSpeed(Int64(process.download))
        self.upField.stringValue = Units.readableSpeed(Int64(process.upload))
        if self.currentPID != process.pid || self.iconView.image == nil {
            self.iconView.image = ProcessIconCache.shared.icon(for: process.pid)
            self.currentPID = process.pid
        }
        self.toolTip = "\(process.name) (pid \(process.pid))"
    }

    override func layout() {
        super.layout()
        let valueWidth: CGFloat = 68
        let iconSize: CGFloat = 12

        self.iconView.frame = NSRect(x: 2, y: (self.bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        self.nameField.frame = NSRect(x: 22, y: (self.bounds.height - 16) / 2, width: self.bounds.width - 22 - valueWidth * 2, height: 16)
        self.downField.frame = NSRect(x: self.bounds.width - valueWidth * 2, y: (self.bounds.height - 16) / 2, width: valueWidth, height: 16)
        self.upField.frame = NSRect(x: self.bounds.width - valueWidth, y: (self.bounds.height - 16) / 2, width: valueWidth, height: 16)
    }
}

// MARK: - primitives

private final class DotView: NSView {
    private let color: NSColor
    private let radius: CGFloat

    init(size: CGFloat, color: NSColor, radius: CGFloat) {
        self.color = color
        self.radius = radius
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        self.color.setFill()
        NSBezierPath(roundedRect: self.bounds, xRadius: self.radius, yRadius: self.radius).fill()
    }
}

final class RoundedPanelView: NSView {
    private let fill: NSColor
    private let radius: CGFloat

    init(fill: NSColor, radius: CGFloat) {
        self.fill = fill
        self.radius = radius
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        self.fill.setFill()
        NSBezierPath(roundedRect: self.bounds, xRadius: self.radius, yRadius: self.radius).fill()
    }
}
