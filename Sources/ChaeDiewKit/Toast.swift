import AppKit

/// A small non-activating message near the bottom of the main screen.
@MainActor
public enum Toast {
    private static var panel: NSPanel?
    private static var generation = 0

    /// Removes the current toast immediately (before a capture, so it can't appear in the image).
    public static func dismiss() {
        generation += 1
        panel?.orderOut(nil)
        panel = nil
    }

    public static func show(_ message: String, duration: TimeInterval = 1.8) {
        panel?.orderOut(nil)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.sizeToFit()

        let size = NSSize(width: min(label.frame.width, 520) + 36, height: label.frame.height + 20)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        let background = NSView(frame: NSRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        background.layer?.cornerRadius = 10
        label.frame = NSRect(x: 18, y: 10, width: size.width - 36, height: label.frame.height)
        background.addSubview(label)
        panel.contentView = background

        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 120))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        generation += 1
        let mine = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard mine == generation else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }) {
                panel.orderOut(nil)
            }
        }
    }
}
