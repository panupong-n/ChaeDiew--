import AppKit

/// A borderless always-on-top window showing an image. Drag to move, scroll to zoom,
/// right-click for copy / opacity / close, Esc to close.
@MainActor
public final class PinWindow: NSPanel {
    private let nsImage: NSImage
    private let aspect: CGFloat

    public init(image: CGImage, pixelScale: CGFloat, near origin: NSPoint? = nil) {
        let size = NSSize(width: CGFloat(image.width) / pixelScale, height: CGFloat(image.height) / pixelScale)
        nsImage = NSImage(cgImage: image, size: size)
        aspect = size.width / max(size.height, 1)
        let start = origin ?? NSPoint(x: 200, y: 200)
        super.init(
            contentRect: NSRect(origin: start, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = NSImageView(frame: NSRect(origin: .zero, size: size))
        view.image = nsImage
        view.imageScaling = .scaleAxesIndependently
        view.autoresizingMask = [.width, .height]
        view.menu = makeMenu()
        contentView = view
    }

    public override var canBecomeKey: Bool { true }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }
    }

    public override func scrollWheel(with event: NSEvent) {
        let factor = 1 + event.scrollingDeltaY * 0.01
        var size = NSSize(width: frame.width * factor, height: frame.width * factor / aspect)
        size.width = max(size.width, 80)
        size.height = size.width / aspect
        let center = NSPoint(x: frame.midX, y: frame.midY)
        setFrame(NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                        width: size.width, height: size.height), display: true)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copyImage), keyEquivalent: "").target = self
        for percent in [100, 70, 40] {
            let item = NSMenuItem(title: "Opacity \(percent)%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.tag = percent
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(closePin), keyEquivalent: "").target = self
        return menu
    }

    @objc private func copyImage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
        Toast.show("Copied")
    }

    @objc private func setOpacity(_ sender: NSMenuItem) { alphaValue = CGFloat(sender.tag) / 100 }
    @objc private func closePin() { close() }
}
