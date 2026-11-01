import AppKit

enum PopupMetrics {
    static let width: CGFloat = 264
    static let padding: CGFloat = 8
    static let rowHeight: CGFloat = 22
    static let headerHeight: CGFloat = 30
    static let dashboardHeight: CGFloat = 90
    static let chartHeight: CGFloat = 90
    static let radius: CGFloat = 6
}

final class PopupView: NSView {
    var onSizeChange: ((NSSize) -> Void)?
    var onRequestLocation: (() -> Void)?

    private let chart: NetworkChartView
    private let dashboard = DashboardPanel()
    private let chartContainer = RoundedPanelView(fill: NSColor.lightGray.withAlphaComponent(0.12), radius: PopupMetrics.radius)
    private let totalDownRow = TotalRowView(title: "总下载", color: .systemBlue)
    private let totalUpRow = TotalRowView(title: "总上传", color: .systemRed)
    private let statusRow = BadgeRowView(title: "状态")
    private let internetRow = BadgeRowView(title: "互联网")
    private let latencyRow = DetailRowView(title: "延迟")
    private let jitterRow = DetailRowView(title: "抖动")
    private let interfaceRow = DetailRowView(title: "接口")
    private let macRow = DetailRowView(title: "物理地址")
    private let ssidRow = DetailRowView(title: "网络")
    private let standardRow = DetailRowView(title: "标准")
    private let channelRow = DetailRowView(title: "信道")
    private let speedRow = DetailRowView(title: "速率")
    private let ipv4Row = DetailRowView(title: "本地 IPv4")
    private let ipv6Row = DetailRowView(title: "本地 IPv6")
    private let publicV4Row = DetailRowView(title: "公网 IPv4")
    private let publicV6Row = DetailRowView(title: "公网 IPv6")
    private let locationButton = NSButton(title: "", target: nil, action: nil)
    private let processHeader = SectionHeaderView(title: "进程排行")
    private let processRows = (0..<ProcessReader.maxCount).map { _ in ProcessRowView() }

    var processLimit: Int = Settings.processCount {
        didSet {
            guard self.processLimit != oldValue else { return }
            var changed = false
            for (index, row) in self.processRows.enumerated() where index >= self.processLimit && !row.isHidden {
                row.isHidden = true
                changed = true
            }
            if self.processLimit == 0, !self.processHeader.isHidden {
                self.processHeader.isHidden = true
                changed = true
            }
            if changed {
                self.relayout()
            }
        }
    }

    private var items: [NSView] = []
    private var wifiRowsHidden: Bool?
    private var ipv6RowHidden: Bool?

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
        self.chartContainer.addSubview(self.chart)

        self.locationButton.target = self
        self.locationButton.action = #selector(self.requestLocation)
        self.locationButton.bezelStyle = .rounded
        self.locationButton.controlSize = .small
        self.locationButton.font = .systemFont(ofSize: 10)
        self.locationButton.isHidden = true
        self.ssidRow.addAccessory(self.locationButton)

        let headers = [
            SectionHeaderView(title: "使用记录"),
            SectionHeaderView(title: "流量"),
            SectionHeaderView(title: "接口信息"),
            SectionHeaderView(title: "地址")
        ]

        self.processHeader.toolTip = "按全接口统计（nettop）"
        self.processHeader.isHidden = true
        self.processRows.forEach { row in
            row.setFrameSize(NSSize(width: PopupMetrics.width, height: PopupMetrics.rowHeight))
            row.isHidden = true
        }

        self.latencyRow.setValue("—")
        self.jitterRow.setValue("—")
        self.publicV4Row.isHidden = true
        self.publicV6Row.isHidden = true

        self.items = [
            self.dashboard,
            headers[0], self.chartContainer,
            headers[1], self.totalDownRow, self.totalUpRow, self.statusRow, self.internetRow, self.latencyRow, self.jitterRow,
            headers[2], self.interfaceRow, self.macRow, self.ssidRow, self.standardRow, self.channelRow, self.speedRow,
            headers[3], self.ipv4Row, self.ipv6Row, self.publicV4Row, self.publicV6Row,
            self.processHeader
        ] + self.processRows

        self.items.forEach { self.addSubview($0) }
        self.relayout()
    }

    override func layout() {
        super.layout()
        self.chart.frame = self.chartContainer.bounds.insetBy(dx: 1, dy: 1)
    }

    private func relayout() {
        let visible = self.items.filter { !$0.isHidden }
        let height = visible.reduce(CGFloat(0)) { $0 + $1.frame.height }
        self.setFrameSize(NSSize(width: PopupMetrics.width, height: height))

        var y = height
        for item in visible {
            y -= item.frame.height
            item.setFrameOrigin(NSPoint(x: 0, y: y))
        }

        self.onSizeChange?(self.frame.size)
    }

    func update(_ usage: NetworkUsage) {
        self.dashboard.update(download: usage.bandwidth.download, upload: usage.bandwidth.upload)
        self.totalDownRow.setValue(Units.readableMemory(usage.total.download))
        self.totalUpRow.setValue(Units.readableMemory(usage.total.upload))
        self.statusRow.set(status: usage.status)

        if let info = usage.interface {
            self.interfaceRow.setValue("\(info.displayName) (\(info.bsdName))")
            self.macRow.setValue(info.mac.isEmpty ? "—" : info.mac)
            self.speedRow.setValue(info.transmitRate > 0 ? "\(Int(info.transmitRate.rounded())) Mbps" : "—")
        } else {
            self.interfaceRow.setValue("未知")
            self.macRow.setValue("—")
            self.speedRow.setValue("—")
        }

        let isWiFi = usage.connectionType == .wifi
        self.applyWiFi(usage)
        self.applyAddresses(usage)

        let wifiChanged = self.wifiRowsHidden != !isWiFi
        let v6Changed = self.ipv6RowHidden != (usage.laddr.v6 == nil)
        if wifiChanged || v6Changed {
            self.wifiRowsHidden = !isWiFi
            self.ipv6RowHidden = usage.laddr.v6 == nil
            self.relayout()
        }
    }

    func updateConnectivity(_ value: Connectivity) {
        self.internetRow.set(status: value.status)
        self.latencyRow.setValue(value.status ? "\(Int(value.latency.rounded())) ms" : "—")
        self.jitterRow.setValue(value.status ? "\(Int(value.jitter.rounded())) ms" : "—")
    }

    func updatePublicIP(_ address: PublicAddress?) {
        var needsRelayout = false

        if let v4 = address?.v4, !v4.isEmpty {
            var text = v4
            if let country = address?.country, !country.isEmpty {
                text += " (\(country))"
            }
            self.publicV4Row.setValue(text)
            if self.publicV4Row.isHidden {
                self.publicV4Row.isHidden = false
                needsRelayout = true
            }
        }

        if let v6 = address?.v6, !v6.isEmpty {
            var text = v6
            if let country = address?.country, !country.isEmpty {
                text += " (\(country))"
            }
            self.publicV6Row.setValue(text)
            if self.publicV6Row.isHidden {
                self.publicV6Row.isHidden = false
                needsRelayout = true
            }
        }

        if needsRelayout {
            self.relayout()
        }
    }

    func updateProcesses(_ processes: [ProcessUsage]) {
        let limit = min(processes.count, self.processLimit)
        guard limit > 0 else { return }
        var needsRelayout = false

        if self.processHeader.isHidden {
            self.processHeader.isHidden = false
            needsRelayout = true
        }

        for (index, row) in self.processRows.enumerated() {
            if index < limit {
                row.update(processes[index])
                if row.isHidden {
                    row.isHidden = false
                    needsRelayout = true
                }
            } else if !row.isHidden {
                row.update(nil)
                row.isHidden = true
                needsRelayout = true
            }
        }

        if needsRelayout {
            self.relayout()
        }
    }

    func clearProcesses() {
        var changed = false
        if !self.processHeader.isHidden {
            self.processHeader.isHidden = true
            changed = true
        }
        for row in self.processRows where !row.isHidden {
            row.isHidden = true
            changed = true
        }
        if changed {
            self.relayout()
        }
    }

    func clearPublicIP() {
        var changed = false
        if !self.publicV4Row.isHidden {
            self.publicV4Row.isHidden = true
            changed = true
        }
        if !self.publicV6Row.isHidden {
            self.publicV6Row.isHidden = true
            changed = true
        }
        if changed {
            self.relayout()
        }
    }

    private func applyWiFi(_ usage: NetworkUsage) {
        let isWiFi = usage.connectionType == .wifi
        self.ssidRow.isHidden = !isWiFi
        self.standardRow.isHidden = !isWiFi
        self.channelRow.isHidden = !isWiFi
        guard isWiFi else { return }

        let authorized = usage.wifiAuthorization == .authorized
        self.locationButton.isHidden = authorized
        self.locationButton.title = usage.wifiAuthorization == .notDetermined ? "允许访问 Wi-Fi 详情" : "打开定位设置"
        self.ssidRow.setValueHidden(!authorized)

        if authorized {
            var text = usage.wifi.ssid ?? "未知"
            if let rssi = usage.wifi.rssi {
                text += " (\(rssi))"
            }
            self.ssidRow.setValue(text)
        }
        self.standardRow.setValue(usage.wifi.standard ?? "—")
        self.channelRow.setValue(usage.wifi.channel ?? "—")

        if let rssi = usage.wifi.rssi, let noise = usage.wifi.noise {
            self.channelRow.toolTip = "RSSI: \(rssi) dBm\nNoise: \(noise) dBm\n频段: \(usage.wifi.channelBand ?? "—")\n带宽: \(usage.wifi.channelWidth ?? "—")"
        } else {
            self.channelRow.toolTip = nil
        }
    }

    private func applyAddresses(_ usage: NetworkUsage) {
        self.ipv4Row.setValue(usage.laddr.v4 ?? "—")
        if let v6 = usage.laddr.v6, !v6.isEmpty {
            self.ipv6Row.isHidden = false
            self.ipv6Row.setValue(v6)
        } else {
            self.ipv6Row.isHidden = true
        }
    }

    @objc private func requestLocation() {
        self.onRequestLocation?()
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
        self.unitField.font = .systemFont(ofSize: 13, weight: .light)
        self.unitField.textColor = .labelColor
        self.titleField.font = .systemFont(ofSize: 11)
        self.titleField.textColor = .secondaryLabelColor
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
        let valueWidth = valueSize.width + 2
        let unitWidth = unitSize.width + 4
        let topWidth = valueWidth + unitWidth
        let topY = (self.bounds.height - topHeight - titleHeight) / 2 + titleHeight

        self.valueField.frame = NSRect(x: (self.bounds.width - topWidth) / 2, y: topY, width: valueWidth, height: topHeight)
        self.unitField.frame = NSRect(x: self.valueField.frame.maxX, y: topY + 4, width: unitWidth, height: 15)

        let titleWidth = self.titleField.intrinsicContentSize.width + 6
        let dotSize: CGFloat = 12
        let bottomWidth = titleWidth + dotSize
        let bottomY = topY - titleHeight - 2
        self.dot.frame = NSRect(x: (self.bounds.width - bottomWidth) / 2, y: bottomY + 2, width: dotSize, height: dotSize)
        self.titleField.frame = NSRect(x: self.dot.frame.maxX, y: bottomY, width: titleWidth, height: titleHeight)
    }
}

// MARK: - rows

private final class SectionHeaderView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let leftLine = NSView()
    private let rightLine = NSView()

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: PopupMetrics.width, height: PopupMetrics.headerHeight))
        self.label.attributedStringValue = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .kern: 1.0
        ])
        self.leftLine.wantsLayer = true
        self.leftLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        self.rightLine.wantsLayer = true
        self.rightLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        self.addSubview(self.leftLine)
        self.addSubview(self.label)
        self.addSubview(self.rightLine)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        let size = self.label.intrinsicContentSize
        let gap: CGFloat = 8
        self.label.frame = NSRect(x: (self.bounds.width - size.width) / 2, y: (self.bounds.height - size.height) / 2, width: size.width, height: size.height)
        let lineY = self.bounds.height / 2
        self.leftLine.frame = NSRect(x: PopupMetrics.padding, y: lineY, width: max(self.label.frame.minX - gap - PopupMetrics.padding, 0), height: 1)
        self.rightLine.frame = NSRect(x: self.label.frame.maxX + gap, y: lineY, width: max(self.bounds.width - self.label.frame.maxX - gap - PopupMetrics.padding, 0), height: 1)
    }
}

private final class DetailRowView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")
    private let valueContainer = NSView()

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: PopupMetrics.width, height: PopupMetrics.rowHeight))

        self.label.font = .systemFont(ofSize: 12)
        self.label.textColor = .secondaryLabelColor
        self.label.stringValue = title

        self.value.font = .systemFont(ofSize: 12)
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
        let labelWidth = self.label.intrinsicContentSize.width + 4
        self.label.frame = NSRect(x: PopupMetrics.padding, y: (self.bounds.height - 16) / 2, width: labelWidth, height: 16)

        let containerX = self.label.frame.maxX
        self.valueContainer.frame = NSRect(x: containerX, y: 0, width: self.bounds.width - containerX - PopupMetrics.padding, height: self.bounds.height)
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
        self.label.stringValue = title
        self.value.font = .systemFont(ofSize: 12)
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
        self.dot.frame = NSRect(x: PopupMetrics.padding + 3, y: (self.bounds.height - dotSize) / 2, width: dotSize, height: dotSize)
        let labelWidth = self.label.intrinsicContentSize.width + 4
        self.label.frame = NSRect(x: self.dot.frame.maxX + 6, y: (self.bounds.height - 16) / 2, width: labelWidth, height: 16)
        self.value.frame = NSRect(x: self.label.frame.maxX, y: (self.bounds.height - 16) / 2, width: self.bounds.width - self.label.frame.maxX - PopupMetrics.padding, height: 16)
    }
}

private final class BadgeRowView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let badge = BadgeView()

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: PopupMetrics.width, height: PopupMetrics.rowHeight))

        self.label.font = .systemFont(ofSize: 12)
        self.label.textColor = .secondaryLabelColor
        self.label.stringValue = title
        self.badge.isHidden = true

        self.addSubview(self.label)
        self.addSubview(self.badge)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func set(status: Bool) {
        self.badge.isHidden = false
        self.badge.status = status
        self.needsLayout = true
    }

    override func layout() {
        super.layout()
        let labelWidth = self.label.intrinsicContentSize.width + 4
        self.label.frame = NSRect(x: PopupMetrics.padding, y: (self.bounds.height - 16) / 2, width: labelWidth, height: 16)
        let badgeWidth: CGFloat = 44
        let badgeHeight: CGFloat = 14
        self.badge.frame = NSRect(
            x: self.bounds.width - PopupMetrics.padding - badgeWidth,
            y: (self.bounds.height - badgeHeight) / 2,
            width: badgeWidth,
            height: badgeHeight
        )
    }
}

private final class BadgeView: NSView {
    var status = true {
        didSet { self.needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color = self.status ? NSColor.systemGreen : NSColor.systemRed
        color.setFill()
        NSBezierPath(roundedRect: self.bounds, xRadius: self.bounds.height / 2, yRadius: self.bounds.height / 2).fill()

        let text = (self.status ? "UP" : "DOWN") as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (self.bounds.width - size.width) / 2, y: (self.bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }
}

final class ProcessRowView: NSView {
    private let nameField = NSTextField(labelWithString: "—")
    private let downField = NSTextField(labelWithString: "")
    private let upField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        self.nameField.font = .systemFont(ofSize: 11)
        self.nameField.lineBreakMode = .byTruncatingMiddle
        self.nameField.textColor = .labelColor

        self.downField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        self.downField.textColor = .systemBlue
        self.downField.alignment = .right

        self.upField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        self.upField.textColor = .systemRed
        self.upField.alignment = .right

        self.addSubview(self.nameField)
        self.addSubview(self.downField)
        self.addSubview(self.upField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(_ process: ProcessUsage?) {
        guard let process else {
            self.nameField.stringValue = ""
            self.downField.stringValue = ""
            self.upField.stringValue = ""
            self.toolTip = nil
            return
        }
        self.nameField.stringValue = process.name
        self.downField.stringValue = "↓\(Units.readableSpeed(Int64(process.download)))"
        self.upField.stringValue = "↑\(Units.readableSpeed(Int64(process.upload)))"
        self.toolTip = "\(process.name) (pid \(process.pid))"
    }

    override func layout() {
        super.layout()
        let margin = PopupMetrics.padding
        let valueWidth: CGFloat = 68
        let nameWidth = self.bounds.width - margin * 2 - valueWidth * 2 - 4
        let textY = (self.bounds.height - 16) / 2

        self.nameField.frame = NSRect(x: margin, y: textY, width: nameWidth, height: 16)
        self.downField.frame = NSRect(x: margin + nameWidth + 2, y: textY, width: valueWidth, height: 16)
        self.upField.frame = NSRect(x: margin + nameWidth + 2 + valueWidth, y: textY, width: valueWidth, height: 16)
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
