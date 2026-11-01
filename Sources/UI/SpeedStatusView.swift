import AppKit

/// Two-row menu bar readout mirroring Stats' default speed widget:
/// colored dots on the left, right-aligned values, upload on top, download below.
final class SpeedStatusView: NSView {
    private static let dotSize: CGFloat = 6
    private static let margin: CGFloat = 2
    private let font = NSFont.systemFont(ofSize: 9, weight: .light)

    private var download: Int64 = 0
    private var upload: Int64 = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(download: Int64, upload: Int64) {
        self.download = download
        self.upload = upload
        self.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rowHeight = self.bounds.height / 2
        self.drawRow(value: self.upload, y: rowHeight, color: self.color(for: self.upload, base: .red))
        self.drawRow(value: self.download, y: 0, color: self.color(for: self.download, base: .systemBlue))
    }

    private func color(for value: Int64, base: NSColor) -> NSColor {
        return value < 1024 ? .textColor : base
    }

    private func drawRow(value: Int64, y: CGFloat, color: NSColor) {
        let rowHeight = self.bounds.height / 2

        let dotRect = NSRect(
            x: Self.margin,
            y: y + (rowHeight - Self.dotSize) / 2,
            width: Self.dotSize,
            height: Self.dotSize
        )
        color.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        let text = Units.readableSpeed(value) as NSString
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
}
