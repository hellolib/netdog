import AppKit

/// Connectivity history as a dot matrix, mirroring Stats' GridChartView:
/// 30 columns x 3 rows, newest sample at the top-left.
final class GridChartView: NSView {
    private let okColor = NSColor.systemGreen
    private let failColor = NSColor.systemRed
    private let inactiveColor = NSColor.underPageBackgroundColor.withAlphaComponent(0.4)

    private let rows = 30
    private let columns = 3
    private var values: [Bool?]

    override init(frame frameRect: NSRect) {
        self.values = Array(repeating: nil, count: self.rows * self.columns)
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func addValue(_ ok: Bool) {
        self.values.remove(at: 0)
        self.values.append(ok)
        self.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let spacing: CGFloat = 2
        let width = (self.bounds.width - CGFloat(self.rows - 1) * spacing) / CGFloat(self.rows)
        let height = (self.bounds.height - CGFloat(self.columns - 1) * spacing) / CGFloat(self.columns)
        var x: CGFloat = 0
        var y: CGFloat = (height + spacing) * CGFloat(self.columns - 1)

        var index = 0
        for _ in 0..<self.columns {
            for _ in 0..<self.rows {
                let rect = NSRect(x: x, y: y, width: width, height: height)
                let box = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
                let color = self.values[index].map { $0 ? self.okColor : self.failColor } ?? self.inactiveColor
                color.setFill()
                box.fill()
                index += 1
                x += width + spacing
            }
            x = 0
            y -= height + spacing
        }
    }
}
