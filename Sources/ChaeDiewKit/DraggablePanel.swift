import AppKit

/// A floating panel that can be dragged by its background, so it never has to sit on top of what you are drawing.
@MainActor
class DraggableEffectView: NSView {
    /// Solid brand surface with a hairline and a soft shadow, shared by the style and backdrop panels.
    func applyPanelSkin() {
        wantsLayer = true
        layer?.backgroundColor = Brand.inkRaised.cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = Brand.line.cgColor
        layer?.masksToBounds = true
    }

    /// Set by the owner: the constraints that pin the panel to the top-right corner of the canvas area.
    var topConstraint: NSLayoutConstraint?
    var trailingConstraint: NSLayoutConstraint?
    private var lastPoint: CGPoint?

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) { lastPoint = event.locationInWindow }
    override func mouseUp(with event: NSEvent) { lastPoint = nil }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastPoint, let top = topConstraint, let trailing = trailingConstraint, let host = superview else { return }
        let p = event.locationInWindow
        // Window coordinates grow upwards; the constants are measured from the top and the right edge.
        top.constant = min(max(0, top.constant - (p.y - last.y)), max(0, host.bounds.height - 60))
        trailing.constant = max(min(0, trailing.constant + (p.x - last.x)), -max(0, host.bounds.width - 60))
        lastPoint = p
        superview?.layoutSubtreeIfNeeded()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
