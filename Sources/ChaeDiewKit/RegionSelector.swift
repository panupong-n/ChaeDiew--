import AppKit

public enum Selection {
    /// A region in screen-local points, top-left origin.
    case rect(CGRect)
    case window(WindowInfo)
}

/// Shows a frozen copy of the screen and lets the user drag out a region, or press Space
/// to switch to picking a whole window.
@MainActor
public final class RegionSelector {
    private var window: SelectorWindow?

    public init() {}

    public func select(
        on screen: NSScreen, image: CGImage, windows: [WindowInfo], startInWindowMode: Bool,
        completion: @escaping @MainActor (Selection?) -> Void
    ) {
        let local = windows.map { ($0, WindowList.localFrame(of: $0.frame, on: screen)) }
            .filter { $0.1.intersects(CGRect(origin: .zero, size: screen.frame.size)) }
        let view = RegionView(
            frame: NSRect(origin: .zero, size: screen.frame.size), image: image, windows: local,
            windowMode: startInWindowMode)
        let window = SelectorWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = true
        window.hasShadow = false
        window.contentView = view
        view.onFinish = { [weak self] selection in
            self?.window?.orderOut(nil)
            self?.window = nil
            completion(selection)
        }
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }
}

private final class SelectorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class RegionView: NSView {
    let image: CGImage
    let windows: [(info: WindowInfo, frame: CGRect)]
    var windowMode: Bool
    var onFinish: ((Selection?) -> Void)?

    private var anchor: CGPoint?
    private var selection: CGRect?
    private var hovered: Int?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, image: CGImage, windows: [(WindowInfo, CGRect)], windowMode: Bool) {
        self.image = image
        self.windows = windows.map { (info: $0.0, frame: $0.1) }
        self.windowMode = windowMode
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func resetCursorRects() { addCursorRect(bounds, cursor: windowMode ? .pointingHand : .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        func drawImage(clippedTo clip: CGRect?) {
            ctx.saveGState()
            if let clip { ctx.clip(to: clip) }
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(origin: .zero, size: bounds.size))
            ctx.restoreGState()
        }
        drawImage(clippedTo: nil)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.fill(bounds)

        if windowMode {
            if let i = hovered {
                let target = windows[i].frame.intersection(bounds)
                drawImage(clippedTo: target)
                ctx.setStrokeColor(NSColor.systemBlue.cgColor)
                ctx.setLineWidth(3)
                ctx.stroke(target.insetBy(dx: 1.5, dy: 1.5))
                let w = windows[i].info
                drawLabel("\(w.owner)\(w.title.isEmpty ? "" : " — \(w.title)")  ·  \(Int(target.width)) × \(Int(target.height))", near: target)
            } else {
                drawHint("Click a window · Space: area · Esc: cancel")
            }
            return
        }

        guard let sel = selection, sel.width > 0, sel.height > 0 else {
            drawHint("Drag to select · Space: window · Esc: cancel")
            return
        }
        drawImage(clippedTo: sel)  // un-dim the selected area
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(sel.insetBy(dx: -0.5, dy: -0.5))
        let scale = CGFloat(image.width) / bounds.width
        drawLabel("\(Int((sel.width * scale).rounded())) × \(Int((sel.height * scale).rounded()))", near: sel)
    }

    private func drawLabel(_ string: String, near rect: CGRect) {
        let text = string as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - 8)
        if origin.y < 4 { origin.y = rect.minY + 6 }
        let pill = CGRect(origin: origin, size: size).insetBy(dx: -6, dy: -3)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
        text.draw(at: origin, withAttributes: attrs)
    }

    private func drawHint(_ string: String) {
        let text = t(string) as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attrs)
        let pill = CGRect(x: bounds.midX - size.width / 2 - 12, y: 28, width: size.width + 24, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
        text.draw(at: CGPoint(x: pill.minX + 12, y: pill.minY + 6), withAttributes: attrs)
    }

    // MARK: Mouse & keys

    override func mouseMoved(with event: NSEvent) {
        guard windowMode else { return }
        let p = convert(event.locationInWindow, from: nil)
        let hit = windows.firstIndex { $0.frame.contains(p) }  // windows are ordered front to back
        if hit != hovered { hovered = hit; needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        if windowMode {
            let p = convert(event.locationInWindow, from: nil)
            if let i = windows.firstIndex(where: { $0.frame.contains(p) }) { onFinish?(.window(windows[i].info)) }
            return
        }
        anchor = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !windowMode, let a = anchor else { return }
        var p = convert(event.locationInWindow, from: nil)
        p.x = min(max(p.x, 0), bounds.width)
        p.y = min(max(p.y, 0), bounds.height)
        selection = Geometry.normalizedRect(from: a, to: p)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !windowMode else { return }
        if let sel = selection, sel.width >= 4, sel.height >= 4 { onFinish?(.rect(sel)) } else { onFinish?(nil) }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onFinish?(nil)                                   // Esc
        case 49:                                                  // Space toggles area / window
            windowMode.toggle()
            anchor = nil; selection = nil; hovered = nil
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        default: break
        }
    }
}
