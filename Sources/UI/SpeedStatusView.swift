import AppKit

/// Menu bar readout mirroring Stats' speed widget. Supports two rows / one row,
/// dots / arrows / no icon, optional units and monochrome mode.
final class SpeedStatusView: NSView {
    private var download: Int64 = 0
    private var upload: Int64 = 0

    private var mode = "twoRows"
    private var iconStyle = "dots"
    private var showsUnits = true
    private var mono = false
    private var downColor: NSColor = .systemBlue
    private var upColor: NSColor = .systemRed

    private let font = NSFont.systemFont(ofSize: 9, weight: .light)
    private static let dotSize: CGFloat = 6
    private static let margin: CGFloat = 2

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure() {
        self.mode = Settings.menuBarMode
        self.iconStyle = Settings.menuBarIcon
        self.showsUnits = Settings.menuBarUnits
        self.mono = Settings.menuBarMono
        self.downColor = Settings.downloadColor
        self.upColor = Settings.uploadColor
        self.needsDisplay = true
    }

    var preferredWidth: CGFloat {
        return self.mode == "oneRow" ? 104 : 58
    }

    func update(download: Int64, upload: Int64) {
        self.download = download
        self.upload = upload
        self.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if self.mode == "oneRow" {
            self.drawOneRow()
        } else {
            let rowHeight = self.bounds.height / 2
            self.drawRow(value: self.upload, y: rowHeight, color: self.color(for: self.upload, base: self.upColor))
            self.drawRow(value: self.download, y: 0, color: self.color(for: self.download, base: self.downColor))
        }
    }

    private func color(for value: Int64, base: NSColor) -> NSColor {
        if self.mono {
            return .textColor
        }
        return value < 1024 ? .textColor : base
    }

    private func drawRow(value: Int64, y: CGFloat, color: NSColor) {
        let rowHeight = self.bounds.height / 2
        let x = Self.margin

        switch self.iconStyle {
        case "dots":
            let dotRect = NSRect(x: x, y: y + (rowHeight - Self.dotSize) / 2, width: Self.dotSize, height: Self.dotSize)
            color.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        case "arrows":
            self.drawSymbol(down: y == 0, x: x, y: y, height: rowHeight, color: color)
        default:
            break
        }

        let text = Units.readableSpeed(value, omitUnits: !self.showsUnits) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: self.font,
            .foregroundColor: color
        ]
        let size = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: self.bounds.width - size.width - Self.margin,
            y: y + (rowHeight - size.height) / 2,
            width: size.width,
            height: size.height
        )
        text.draw(in: textRect, withAttributes: attributes)
    }

    private func drawOneRow() {
        let down = "↓" + Units.readableSpeed(self.download, omitUnits: !self.showsUnits)
        let up = "↑" + Units.readableSpeed(self.upload, omitUnits: !self.showsUnits)

        let downAttributes: [NSAttributedString.Key: Any] = [
            .font: self.font,
            .foregroundColor: self.color(for: self.download, base: self.downColor)
        ]
        let upAttributes: [NSAttributedString.Key: Any] = [
            .font: self.font,
            .foregroundColor: self.color(for: self.upload, base: self.upColor)
        ]

        let downText = down as NSString
        let upText = up as NSString
        let downSize = downText.size(withAttributes: downAttributes)
        let upSize = upText.size(withAttributes: upAttributes)
        let gap: CGFloat = 6
        let totalWidth = downSize.width + gap + upSize.width
        let x = max((self.bounds.width - totalWidth) / 2, Self.margin)
        let y = (self.bounds.height - downSize.height) / 2

        downText.draw(at: NSPoint(x: x, y: y), withAttributes: downAttributes)
        upText.draw(at: NSPoint(x: x + downSize.width + gap, y: y), withAttributes: upAttributes)
    }

    private func drawSymbol(down: Bool, x: CGFloat, y: CGFloat, height: CGFloat, color: NSColor) {
        let symbol = down ? "↓" : "↑"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: color
        ]
        let size = (symbol as NSString).size(withAttributes: attributes)
        (symbol as NSString).draw(
            at: NSPoint(x: x, y: y + (height - size.height) / 2),
            withAttributes: attributes
        )
    }
}
