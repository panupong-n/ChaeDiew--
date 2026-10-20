import AppKit

/// A small floating preview that appears in the screen corner after a capture: click it to edit,
/// or use the buttons. It fades away by itself unless the pointer is over it.
@MainActor
public final class ThumbnailPanel: NSPanel {
    private static var current: ThumbnailPanel?
    private var dismissTimer: Timer?
    private var onEdit: (() -> Void)?

    public static func show(
        image: CGImage, pixelScale: CGFloat,
        onEdit: @escaping () -> Void, onCopy: @escaping () -> Void, onSave: @escaping () -> Void, duration: TimeInterval = 8
    ) {
        current?.dismiss()
        let panel = ThumbnailPanel(image: image, pixelScale: pixelScale, onEdit: onEdit, onCopy: onCopy, onSave: onSave)
        current = panel
        panel.orderFrontRegardless()
        panel.dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak panel] _ in
            MainActor.assumeIsolated { panel?.dismiss() }
        }
    }

    private init(image: CGImage, pixelScale: CGFloat, onEdit: @escaping () -> Void, onCopy: @escaping () -> Void, onSave: @escaping () -> Void) {
        let ratio = CGFloat(image.height) / CGFloat(max(1, image.width))
        let width: CGFloat = 240, height = min(220, max(80, width * ratio))
        let size = NSSize(width: width + 16, height: height + 16 + 30)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        super.init(
            contentRect: NSRect(x: screen.maxX - size.width - 16, y: screen.minY + 16, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.onEdit = onEdit
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10

        let picture = ClickableImageView(frame: NSRect(x: 8, y: 38, width: width, height: height))
        picture.image = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / pixelScale, height: CGFloat(image.height) / pixelScale))
        picture.imageScaling = .scaleProportionallyUpOrDown
        picture.onClick = { [weak self] in self?.dismiss(); onEdit() }
        picture.toolTip = t("Open editor")
        background.addSubview(picture)

        func button(_ title: String, _ action: @escaping () -> Void) -> NSButton {
            let b = ActionButton(title: title) { [weak self] in action(); self?.dismiss() }
            b.bezelStyle = .rounded
            b.controlSize = .small
            return b
        }
        let row = NSStackView(views: [
            button(t("Open editor"), onEdit), button(t("Copy"), onCopy), button(t("Save"), onSave),
            ActionButton(title: "✕") { [weak self] in self?.dismiss() },
        ])
        row.spacing = 6
        row.frame = NSRect(x: 8, y: 6, width: width, height: 26)
        background.addSubview(row)
        contentView = background
    }

    public func dismiss() {
        dismissTimer?.invalidate()
        if ThumbnailPanel.current === self { ThumbnailPanel.current = nil }
        orderOut(nil)
    }

    public override func mouseEntered(with event: NSEvent) { dismissTimer?.invalidate() }
}

private final class ClickableImageView: NSImageView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}

private final class ActionButton: NSButton {
    private let run: () -> Void
    init(title: String, _ run: @escaping () -> Void) {
        self.run = run
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        controlSize = .small
        target = self
        action = #selector(fire)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    @objc private func fire() { run() }
}
