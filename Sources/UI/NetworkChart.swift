import AppKit

enum ChartScale: String {
    case none
    case square
    case cube
    case logarithmic
    case fixed
}

/// Ring-buffer line chart ported from Stats' LineChartView with the tooltip
/// and legend machinery stripped out.
final class LineChartView: NSView {
    private var values: [Double?]
    private var head = 0
    private var flipY: Bool
    private var color: NSColor
    private var scale: ChartScale
    private var fixedScale: Double

    init(num: Int, color: NSColor, flipY: Bool, scale: ChartScale = .none, fixedScale: Double = 1) {
        self.values = Array(repeating: nil, count: max(num, 2))
        self.color = color
        self.flipY = flipY
        self.scale = scale
        self.fixedScale = fixedScale
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

    func configure(num: Int? = nil, color: NSColor? = nil, flipY: Bool? = nil, scale: ChartScale? = nil, fixedScale: Double? = nil) {
        if let num, num != self.values.count {
            self.values = Array(repeating: nil, count: max(num, 2))
            self.head = 0
        }
        if let color {
            self.color = color
        }
        if let flipY {
            self.flipY = flipY
        }
        if let scale {
            self.scale = scale
        }
        if let fixedScale {
            self.fixedScale = fixedScale
        }
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

        if self.scale != .fixed {
            for value in ordered {
                if let value {
                    maxValue = max(maxValue, value)
                }
            }
        } else {
            maxValue = self.fixedScale
        }

        for (index, value) in ordered.enumerated() {
            guard let value else { continue }
            var y = self.scaleValue(value, maxValue: maxValue, height: height)
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

    private func scaleValue(_ value: Double, maxValue: Double, height: CGFloat) -> CGFloat {
        var value = value
        var localMax = maxValue
        if self.scale == .none, value > 1, localMax != 0 {
            value /= localMax
        }
        var y = value * height

        switch self.scale {
        case .square:
            if value > 0 { value = sqrt(value) }
            if localMax > 0 { localMax = sqrt(localMax) }
        case .cube:
            if value > 0 { value = cbrt(value) }
            if localMax > 0 { localMax = cbrt(localMax) }
        case .logarithmic:
            if value > 0 { value = log(value / 256.0) }
            if localMax > 0 { localMax = log(localMax / 256.0) }
        case .fixed:
            if value > self.fixedScale { value = self.fixedScale }
            localMax = self.fixedScale
        case .none:
            break
        }

        if value < 0 { value = 0 }
        if localMax <= 0 { localMax = 1 }
        if self.scale != .none {
            y = height * value / localMax
        }

        return y
    }
}

/// Stacked download/upload chart, mirroring Stats' NetworkChartView:
/// upload grows upward from the horizontal center line, download downward.
final class NetworkChartView: NSView {
    private let down: LineChartView
    private let up: LineChartView
    private var reversedOrder: Bool

    init(num: Int = Settings.chartHistory) {
        self.reversedOrder = Settings.reverseOrder
        let scale = Settings.chartScale
        let fixedScale = Double(Settings.chartFixedScaleBytes)
        self.down = LineChartView(
            num: num,
            color: Settings.downloadColor,
            flipY: !self.reversedOrder,
            scale: scale,
            fixedScale: fixedScale
        )
        self.up = LineChartView(
            num: num,
            color: Settings.uploadColor,
            flipY: self.reversedOrder,
            scale: scale,
            fixedScale: fixedScale
        )
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

    func reconfigure() {
        let reversed = Settings.reverseOrder
        let reversedChanged = reversed != self.reversedOrder
        self.reversedOrder = reversed

        self.down.configure(
            num: Settings.chartHistory,
            color: Settings.downloadColor,
            flipY: !reversed,
            scale: Settings.chartScale,
            fixedScale: Double(Settings.chartFixedScaleBytes)
        )
        self.up.configure(
            num: Settings.chartHistory,
            color: Settings.uploadColor,
            flipY: reversed,
            scale: Settings.chartScale,
            fixedScale: Double(Settings.chartFixedScaleBytes)
        )
        if reversedChanged {
            self.needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        let half = self.bounds.height / 2
        let top = NSRect(x: 0, y: half, width: self.bounds.width, height: half)
        let bottom = NSRect(x: 0, y: 0, width: self.bounds.width, height: half)
        self.down.frame = self.reversedOrder ? top : bottom
        self.up.frame = self.reversedOrder ? bottom : top
    }
}
