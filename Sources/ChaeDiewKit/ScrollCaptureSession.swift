import AppKit

/// Captures a region repeatedly while its content scrolls, and stitches the frames.
/// Auto mode scrolls for you (needs Accessibility permission); manual mode watches you scroll.
@MainActor
final class ScrollCaptureSession {
    private let screen: NSScreen
    private var context: GrabContext
    private let region: CGRect            // screen-local points, top-left origin
    private var auto: Bool
    private let completion: @MainActor (CGImage?, CGFloat) -> Void

    private let stitcher = ScrollStitcher(maxHeight: Settings.shared.scrollMaxHeight)
    private let speed = CGFloat(Settings.shared.scrollSpeed)
    private let reverse = Settings.shared.scrollReverse
    private var hud: HUDPanel?
    private var border: NSWindow?
    private var label = NSTextField(labelWithString: "")
    private var task: Task<Void, Never>?
    private var finished = false

    init(screen: NSScreen, context: GrabContext, region: CGRect, auto: Bool,
         completion: @escaping @MainActor (CGImage?, CGFloat) -> Void) {
        self.screen = screen
        self.context = context
        self.region = region
        self.auto = auto
        self.completion = completion
    }

    func start() {
        if auto && !Self.ensureAccessibility() {
            auto = false
            Toast.show(t("Auto-scroll needs Accessibility permission — switching to manual"), duration: 4)
        }
        showBorder()
        showHUD()
        task = Task { @MainActor in await run() }
    }

    // MARK: Loop

    private func run() async {
        // The filter was built before the border/HUD windows existed; rebuild it so they are excluded from frames.
        try? await Task.sleep(nanoseconds: 150_000_000)
        if let fresh = try? await ScreenGrabber.context(for: screen) { context = fresh }
        if auto { moveCursorToRegionCenter() }
        var step = max(60, region.height * 0.4 * speed)
        var unchanged = 0
        var unmatched = 0
        var iterations = 0

        while !finished && !Task.isCancelled && iterations < 400 {
            iterations += 1
            guard let frame = await settledFrame() else { break }
            let result = stitcher.add(frame)
            label.stringValue = String(format: t("%d px captured"), stitcher.totalHeight)

            switch result {
            case .limitReached: finish(cancelled: false); return
            case .noChange: unchanged += 1; unmatched = 0
            case .unmatched: unmatched += 1; unchanged = 0
            default: unchanged = 0; unmatched = 0
            }

            if auto {
                if unchanged >= 2 { break }                       // content stopped moving: bottom reached
                if unmatched > 0 {
                    // We scrolled further than the frames overlap. Undo that scroll, take smaller steps.
                    postScroll(points: step, down: false)
                    step = max(30, step / 2)
                    if unmatched >= 3 { break }
                    try? await Task.sleep(nanoseconds: UInt64(500_000_000 / speed))
                    continue
                }
                postScroll(points: step, down: true)
                try? await Task.sleep(nanoseconds: UInt64(500_000_000 / speed))
            } else {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        finish(cancelled: false)
    }

    /// A frame of the region once it has stopped animating (two identical captures in a row).
    private func settledFrame() async -> CGImage? {
        var previous: [UInt64]?
        var latest: CGImage?
        for _ in 0..<6 {
            guard let frame = try? await captureRegion() else { return latest }
            latest = frame
            let hashes = ScrollStitcher.rowHashes(frame)
            if hashes == previous { return frame }
            previous = hashes
            try? await Task.sleep(nanoseconds: 110_000_000)
        }
        return latest
    }

    private func captureRegion() async throws -> CGImage? {
        let full = try await ScreenGrabber.capture(context)
        let scale = context.pixelScale
        let rect = CGRect(x: region.minX * scale, y: region.minY * scale,
                          width: region.width * scale, height: region.height * scale).integral
        return full.cropping(to: rect)
    }

    // MARK: Scrolling

    private var globalOrigin: CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        return CGPoint(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY)
    }

    private func moveCursorToRegionCenter() {
        let o = globalOrigin
        CGWarpMouseCursorPosition(CGPoint(x: o.x + region.midX, y: o.y + region.midY))
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func postScroll(points: CGFloat, down: Bool) {
        let amount = Int32(points) * (down != reverse ? -1 : 1)
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: amount, wheel2: 0, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    static func ensureAccessibility() -> Bool {
        if AXIsProcessTrusted() { return true }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        return false
    }

    // MARK: Windows

    private func appKitFrame(for localRect: CGRect) -> NSRect {
        NSRect(x: screen.frame.minX + localRect.minX, y: screen.frame.maxY - localRect.maxY,
               width: localRect.width, height: localRect.height)
    }

    private func showBorder() {
        let window = NSWindow(contentRect: appKitFrame(for: region.insetBy(dx: -3, dy: -3)),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.hasShadow = false
        let view = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
        view.wantsLayer = true
        view.layer?.borderColor = NSColor.systemBlue.cgColor
        view.layer?.borderWidth = 3
        window.contentView = view
        window.orderFrontRegardless()
        border = window
    }

    private func showHUD() {
        let size = NSSize(width: 460, height: 44)
        let panel = HUDPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.onDone = { [weak self] in self?.finish(cancelled: false) }
        panel.onCancel = { [weak self] in self?.finish(cancelled: true) }

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12

        label.stringValue = t(auto ? "Scrolling capture — scrolling for you…" : "Scrolling capture — scroll the content, then press Done")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        let done = NSButton(title: t("Done"), target: panel, action: #selector(HUDPanel.doneClicked))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        let cancel = NSButton(title: t("Cancel"), target: panel, action: #selector(HUDPanel.cancelClicked))
        cancel.bezelStyle = .rounded
        let stack = NSStackView(views: [label, done, cancel])
        stack.spacing = 10
        stack.frame = background.bounds.insetBy(dx: 14, dy: 8)
        stack.autoresizingMask = [.width, .height]
        background.addSubview(stack)
        panel.contentView = background

        // Below the region if there is room, otherwise inside the screen's bottom edge.
        let below = screen.frame.maxY - region.maxY - size.height - 12
        let y = below > screen.frame.minY + 8 ? below : screen.frame.minY + 24
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: y))
        panel.makeKeyAndOrderFront(nil)
        hud = panel
    }

    private func finish(cancelled: Bool) {
        guard !finished else { return }
        finished = true
        task?.cancel()
        hud?.orderOut(nil)
        border?.orderOut(nil)
        hud = nil
        border = nil
        completion(cancelled ? nil : stitcher.finish(), context.pixelScale)
    }
}

private final class HUDPanel: NSPanel {
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()
        case 36, 76: onDone?()
        default: super.keyDown(with: event)
        }
    }

    @objc func doneClicked() { onDone?() }
    @objc func cancelClicked() { onCancel?() }
}
