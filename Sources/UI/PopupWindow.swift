import AppKit

final class PopupHeaderView: NSView {
    var onSettings: (() -> Void)?
    var onActivityMonitor: (() -> Void)?

    private let titleField = NSTextField(labelWithString: "netdog")
    private let activityButton = NSButton()
    private let settingsButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        self.titleField.font = .systemFont(ofSize: 13, weight: .regular)
        self.titleField.alignment = .center
        self.titleField.textColor = .textColor
        self.titleField.lineBreakMode = .byClipping

        self.activityButton.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: nil)
        self.activityButton.bezelStyle = .regularSquare
        self.activityButton.isBordered = false
        self.activityButton.imageScaling = .scaleProportionallyDown
        self.activityButton.contentTintColor = .lightGray
        self.activityButton.toolTip = "打开活动监视器"
        self.activityButton.target = self
        self.activityButton.action = #selector(self.openActivityMonitor)

        self.settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        self.settingsButton.bezelStyle = .regularSquare
        self.settingsButton.isBordered = false
        self.settingsButton.imageScaling = .scaleProportionallyDown
        self.settingsButton.contentTintColor = .lightGray
        self.settingsButton.toolTip = "打开设置"
        self.settingsButton.target = self
        self.settingsButton.action = #selector(self.openSettings)

        self.addSubview(self.titleField)
        self.addSubview(self.activityButton)
        self.addSubview(self.settingsButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        let buttonWidth: CGFloat = 24
        let buttonHeight: CGFloat = 24
        self.activityButton.frame = NSRect(x: 4, y: (self.bounds.height - buttonHeight) / 2, width: buttonWidth, height: buttonHeight)
        self.settingsButton.frame = NSRect(x: self.bounds.width - buttonWidth - 4, y: (self.bounds.height - buttonHeight) / 2, width: buttonWidth, height: buttonHeight)
        self.titleField.frame = NSRect(x: buttonWidth + 8, y: (self.bounds.height - 20) / 2, width: self.bounds.width - (buttonWidth + 8) * 2, height: 20)
    }

    @objc private func openSettings() {
        self.onSettings?()
    }

    @objc private func openActivityMonitor() {
        self.onActivityMonitor?()
    }
}

/// White overlay used in light mode, mirroring Stats' PopupView background.
private final class OverlayView: NSView {
    var isDark = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !self.isDark else { return }
        NSColor.white.setFill()
        self.bounds.fill()
    }
}

/// Popup body mirroring Stats' PopupWindow layout: vibrancy background, 42pt
/// header, 8pt margins, scrollable body that reserves 20pt for the scroller.
final class PopupContainerView: NSView {
    let content: PopupView
    let header = PopupHeaderView()

    private let effect = NSVisualEffectView()
    private let overlay = OverlayView()
    private let scrollView = NSScrollView()
    private var scrollable = false

    init(content: PopupView) {
        self.content = content
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 400))

        self.effect.material = .titlebar
        self.effect.blendingMode = .behindWindow
        self.effect.state = .active
        self.effect.wantsLayer = true
        self.effect.layer?.cornerRadius = PopupMetrics.radius
        self.effect.layer?.masksToBounds = true
        self.effect.addSubview(self.overlay)

        self.scrollView.drawsBackground = false
        self.scrollView.borderType = .noBorder
        self.scrollView.hasVerticalScroller = true
        self.scrollView.hasHorizontalScroller = false
        self.scrollView.autohidesScrollers = true
        self.scrollView.horizontalScrollElasticity = .none
        self.scrollView.documentView = content

        self.addSubview(self.effect, positioned: .below, relativeTo: nil)
        self.addSubview(self.scrollView)
        self.addSubview(self.header)

        self.updateOverlay()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.updateOverlay()
    }

    private func updateOverlay() {
        self.overlay.isDark = self.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        self.overlay.needsDisplay = true
    }

    /// Returns the window size, capping to the screen and reserving room for
    /// the scroller exactly like Stats' resizeBody.
    @discardableResult
    func updateLayout(contentSize: NSSize, visibleHeight: CGFloat) -> NSSize {
        let margins = PopupMetrics.margins
        let headerHeight = PopupMetrics.headerHeight

        var height = contentSize.height + headerHeight + margins * 2
        self.scrollable = false
        if height > visibleHeight - 24 {
            height = visibleHeight - 24
            self.scrollable = true
        }

        let size = NSSize(width: contentSize.width + margins * 2, height: height)
        self.frame = NSRect(origin: .zero, size: size)

        self.effect.frame = self.bounds
        self.overlay.frame = self.effect.bounds
        self.header.frame = NSRect(x: 0, y: height - headerHeight, width: size.width, height: headerHeight)

        let offset: CGFloat = self.scrollable ? 20 : 0
        self.scrollView.frame = NSRect(
            x: margins,
            y: margins,
            width: size.width - margins * 2 + offset,
            height: height - headerHeight - margins * 2
        )
        self.content.frame = NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height)

        return size
    }

    func scrollToTop() {
        self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
    }
}

final class PopupWindowController: NSWindowController, NSWindowDelegate {
    let container: PopupContainerView
    private weak var anchorButton: NSStatusBarButton?
    private var lastResignAt: Date = .distantPast

    var onOpenSettings: (() -> Void)?
    var onOpenActivityMonitor: (() -> Void)?

    init(content: PopupView) {
        self.container = PopupContainerView(content: content)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 400),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }

        super.init(window: panel)

        panel.delegate = self
        panel.contentView = self.container
        self.container.header.onSettings = { [weak self] in self?.onOpenSettings?() }
        self.container.header.onActivityMonitor = { [weak self] in self?.onOpenActivityMonitor?() }
        self.resizeToFit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var isVisible: Bool {
        return self.window?.isVisible ?? false
    }

    func resizeToFit() {
        guard self.window != nil else { return }
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 900
        let size = self.container.updateLayout(contentSize: self.container.content.frame.size, visibleHeight: visibleHeight)
        self.window?.setContentSize(size)
        if self.isVisible {
            self.position()
        }
    }

    func toggle(at button: NSStatusBarButton) {
        // A click outside hides the panel on resign; ignore the immediate
        // status-item click so it does not reopen and flicker.
        if !self.isVisible, Date().timeIntervalSince(self.lastResignAt) < 0.25 {
            return
        }
        if self.isVisible {
            self.hide()
        } else {
            self.show(at: button)
        }
    }

    func show(at button: NSStatusBarButton) {
        self.anchorButton = button
        self.resizeToFit()
        self.position()
        self.window?.orderFrontRegardless()
        self.window?.makeKey()
        self.container.scrollToTop()
    }

    func hide() {
        self.window?.orderOut(nil)
    }

    private func position() {
        guard let window, let button = self.anchorButton, let buttonWindow = button.window else { return }

        let buttonFrame = buttonWindow.frame
        let size = window.frame.size
        var x = buttonFrame.origin.x - size.width / 2 + buttonFrame.width / 2
        let y = buttonFrame.origin.y - size.height - 3
        let anchorPoint = NSPoint(x: buttonFrame.origin.x + buttonFrame.width / 2, y: buttonFrame.origin.y)

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorPoint) }) ?? NSScreen.main {
            if x + size.width > screen.frame.maxX {
                x = screen.frame.maxX - size.width - 3
            }
            if x < screen.frame.minX {
                x = screen.frame.minX + 3
            }
        }

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func windowDidResignKey(_ notification: Notification) {
        self.lastResignAt = Date()
        self.hide()
    }
}
