import AppKit

/// Ring-buffer line chart, ported from Stats' LineChartView with the tooltip
/// and legend machinery stripped out.
final class LineChartView: NSView {
    private var values: [Double?]
    private var head = 0
    private let flipY: Bool
    private let color: NSColor

    init(num: Int, color: NSColor, flipY: Bool) {
        self.values = Array(repeating: nil, count: max(num, 2))
        self.color = color
        self.flipY = flipY
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func addValue(_ value: Double) {
        self.values[self.head] = value
        self.head = (self.head + 1) % self.values.count
        self.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let ordered = Array(self.values[self.head...]) + Array(self.values[..<self.head])
        var points: [CGPoint] = []
        var maxValue: Double = 1
        let step = self.bounds.width / CGFloat(self.values.count - 1)
        let offset: CGFloat = 1 / (NSScreen.main?.backingScaleFactor ?? 1)
        let height = max(self.bounds.height - offset, 1)

        for value in ordered {
            if let value {
                maxValue = max(maxValue, value)
            }
        }

        for (index, value) in ordered.enumerated() {
            guard let value else { continue }
            var y = CGFloat(value / maxValue) * height
            if self.flipY {
                y = height - y
            }
            points.append(CGPoint(x: CGFloat(index) * step, y: y))
        }

        guard points.count > 1 else { return }

        let baseline: CGFloat = self.flipY ? self.bounds.height : 0
        let fill = CGMutablePath()
        fill.addLines(between: points)
        fill.addLine(to: CGPoint(x: points[points.count - 1].x, y: baseline))
        fill.addLine(to: CGPoint(x: points[0].x, y: baseline))
        fill.closeSubpath()

        context.saveGState()
        context.addPath(fill)
        context.setFillColor(self.color.withAlphaComponent(0.18).cgColor)
        context.fillPath()

        context.addLines(between: points)
        context.setStrokeColor(self.color.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }
}

/// Stacked download/upload chart, mirroring Stats' NetworkChartView:
/// upload grows upward from the horizontal center line, download downward.
final class NetworkChartView: NSView {
    private let down: LineChartView
    private let up: LineChartView

    init(num: Int = 180) {
        self.down = LineChartView(num: num, color: .systemBlue, flipY: true)
        self.up = LineChartView(num: num, color: .systemRed, flipY: false)
        super.init(frame: .zero)
        self.addSubview(self.down)
        self.addSubview(self.up)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func addValue(upload: Double, download: Double) {
        self.up.addValue(upload)
        self.down.addValue(download)
    }

    override func layout() {
        super.layout()
        let half = self.bounds.height / 2
        self.up.frame = NSRect(x: 0, y: half, width: self.bounds.width, height: half)
        self.down.frame = NSRect(x: 0, y: 0, width: self.bounds.width, height: half)
    }
}
