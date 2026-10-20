import AppKit

/// Everything undo/redo needs to restore: the (possibly cropped) base image plus the marks on it.
public struct EditState {
    public var image: CGImage
    public var annotations: [Annotation]
}

public final class CanvasView: NSView, NSTextFieldDelegate {
    public private(set) var state: EditState
    /// The image as it was opened, for the before/after GIF.
    public let originalImage: CGImage
    public let pixelScale: CGFloat

    public var tool: ToolKind = .rectangle {
        didSet {
            guard oldValue != tool else { return }
            commitText()
            commitCounter()
            commitImageText()
            selectedIndex = nil
            selectionRect = nil
            measurePreview = []
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            onStyleContextChange?()
            if tool == .ruler { updateMeasure() }  // the ruler starts measuring right away
        }
    }

    /// Called after any edit that changes the image or annotations.
    public var onChange: (() -> Void)?
    public var onToolShortcut: ((ToolKind) -> Void)?
    public var onEscape: (() -> Void)?
    /// Called when the selection or the active tool changes, i.e. when the style panel needs to reload.
    public var onStyleContextChange: (() -> Void)?
    /// Colour under the pointer (nil when it leaves the image), for the toolbar readout.
    public var onHoverColor: ((NSColor?, NSColor?) -> Void)?
    public enum ZoomCommand {
        case toSelection, selectionTopLeft, selectionBottomRight
        /// Z + click (zoom in, ⌥ = out) and Z + drag (zoom to the dragged area), in image points.
        case point(CGPoint, out: Bool), area(CGRect)
    }
    /// Zoom requests that need the scroll view (⌘2, Q, W).
    public var onZoomCommand: ((ZoomCommand) -> Void)?

    /// The look new marks of each kind start with. Editing the style panel updates these as well as the selection.
    public private(set) var templates: [ToolKind: Annotation] = {
        var t: [ToolKind: Annotation] = [:]
        for kind in ToolKind.allCases {
            var a = Annotation(kind: kind, start: .zero, end: .zero, lineWidth: 4)
            if kind == .highlight { a.color = .systemYellow; a.marker = true; a.lineWidth = 4 }
            if kind == .arrow { a.tapered = true }
            if kind == .text { a.pill = true }
            if kind == .spotlight { a.oval = false }
            t[kind] = a
        }
        return t
    }()

    private var undoStack: [EditState] = []
    private var redoStack: [EditState] = []
    private var draft: Annotation?
    /// Rubber-band selection (image points). Enter crops to it; arrow keys move it; OCR/Copy use it.
    public private(set) var selectionRect: CGRect?
    private var marqueeAnchor: CGPoint?
    // Live probing
    private var probe: PixelProbe?
    private var probedImage: CGImage?
    var hoverPoint: CGPoint?
    private var heldKeys: Set<UInt16> = []
    private var measurePreview: [Annotation] = []
    private var guideKeys: Set<UInt16> = []        // Option+S / Option+D held in the ruler tool
    private var rulerDownPoint: CGPoint?
    private var lastPanPoint: CGPoint?
    /// With the counter or text tool, pressing on an existing counter/label moves it instead of adding another.
    private var movingExisting = false
    private var effectiveTool: ToolKind { movingExisting ? .select : tool }
    private var zoomAnchor: CGPoint?
    private var zoomBand: CGRect?
    private var moveOriginal: Annotation?
    private var moveStart: CGPoint?
    /// Lines the dragged mark is currently snapped to (drawn while dragging).
    private var snapGuides: (xs: [CGFloat], ys: [CGFloat]) = ([], [])
    private var objectClipboard: Annotation?
    private var objectClipboardChange = -1
    public private(set) var selectedIndex: Int? {
        didSet {
            guard oldValue != selectedIndex else { return }
            coalescingStyle = false
            onStyleContextChange?()
        }
    }
    private var lastDragPoint: CGPoint?
    private var movedSinceMouseDown = false
    private var activeHandle: Handle?
    private var handleOriginal: Annotation?
    private var textField: NSTextField?
    private var textEditPushedUndo = false
    private var counterOverride: String?
    private var counterField: NSTextField?
    // Retyping text found in the screenshot (OCR + font matching)
    private var imageTextField: NSTextField?
    private var imageTextEdit: (rect: CGRect, guess: TextStyleGuess, original: String)?
    private var recognisedLines: (image: CGImage, lines: [RecognizedLine])?
    private var counterEditIndex: Int?
    /// Successive style tweaks (a slider drag) on the same selection share one undo step.
    private var coalescingStyle = false

    private static let shortcuts: [String: ToolKind] = [
        "v": .select, "c": .crop, "r": .rectangle, "o": .ellipse, "a": .arrow, "l": .line, "p": .freehand,
        "t": .text, "e": .editText, "b": .blur, "n": .counter, "h": .highlight, "s": .spotlight, "m": .ruler, "g": .magnifier,
    ]

    public var pointSize: CGSize {
        CGSize(width: CGFloat(state.image.width) / pixelScale, height: CGFloat(state.image.height) / pixelScale)
    }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }

    public init(image: CGImage, pixelScale: CGFloat) {
        self.state = EditState(image: image, annotations: [])
        self.originalImage = image
        self.pixelScale = pixelScale
        super.init(frame: NSRect(
            x: 0, y: 0, width: CGFloat(image.width) / pixelScale, height: CGFloat(image.height) / pixelScale))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Style

    public var selectedAnnotation: Annotation? {
        guard let i = selectedIndex, state.annotations.indices.contains(i) else { return nil }
        return state.annotations[i]
    }

    /// What the style panel edits: the selected mark, otherwise the defaults of the active drawing tool.
    public var styleTarget: Annotation? {
        if let a = selectedAnnotation { return a }
        guard tool != .select, tool != .crop, var t = templates[tool] else { return nil }
        if tool == .counter { Self.applyCounterText(&t, nextCounterText) }
        return t
    }

    /// What the next counter will say: one step on from the latest counter placed (or edited), unless the user typed something.
    /// "Latest" is by placement order, not list order: clicked marks come to the front, which reorders the list.
    public var nextCounterText: String {
        if let o = counterOverride { return o }
        let counters = state.annotations.filter { $0.kind == .counter }
        guard let latest = counters.max(by: { ($0.serial, $0.number) < ($1.serial, $1.number) }) else { return "1" }
        return CounterText.next(latest.counterText)
    }

    public var nextCounterNumber: Int {
        Int(nextCounterText) ?? ((state.annotations.filter { $0.kind == .counter }.map(\.number).max() ?? 0) + 1)
    }

    /// Stores counter text on a mark: plain integers use `number`, anything else ("1.2", "A3") uses `label`.
    static func applyCounterText(_ a: inout Annotation, _ text: String) {
        if let n = Int(text), String(n) == text {
            a.number = n
            a.label = ""
        } else {
            a.label = text
            a.number = Int(text.prefix { $0.isNumber }) ?? 0
        }
    }

    /// Sets the text of the selected counter, or what the next counter will say.
    public func setCounterText(_ text: String) {
        updateStyle { Self.applyCounterText(&$0, text) }
    }

    /// Applies a style change to the selected mark (one undo step per burst of changes) and to the defaults.
    public func updateStyle(_ body: (inout Annotation) -> Void) {
        let kind = selectedAnnotation?.kind ?? tool
        if kind == .counter, selectedAnnotation == nil {
            var probe = Annotation(kind: .counter, start: .zero, end: .zero)
            Self.applyCounterText(&probe, nextCounterText)
            body(&probe)
            counterOverride = probe.counterText
        }
        if var t = templates[kind] {
            body(&t)
            t.number = 0
            t.label = ""
            templates[kind] = t
        }
        if kind == .text, let field = textField { styleTextField(field) }  // a label being typed follows the panel at once
        if let i = selectedIndex, state.annotations.indices.contains(i) {
            if !coalescingStyle {
                pushUndo()
                coalescingStyle = true
            }
            body(&state.annotations[i])
            if frame.size != pointSize { setFrameSize(pointSize) }
            needsDisplay = true
            onChange?()
        }
    }

    /// A fresh mark of the active tool, in the tool's current style.
    private func makeAnnotation(at p: CGPoint) -> Annotation {
        var a = templates[tool] ?? Annotation(kind: tool, start: p, end: p)
        a.start = p
        a.end = p
        a.points = tool == .freehand ? [p] : []
        return a
    }

    // MARK: Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        var all = state.annotations
        if let draft { all.append(draft) }
        all.append(contentsOf: measurePreview)
        AnnotationRenderer.draw(image: state.image, pointSize: pointSize, annotations: all, in: ctx)

        if let a = selectedAnnotation {
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [5, 3])
            ctx.stroke(a.bounds.insetBy(dx: -5, dy: -5))
            ctx.setLineDash(phase: 0, lengths: [])
            let half = handleSize / 2
            for (_, p) in a.handles() {
                let box = CGRect(x: p.x - half, y: p.y - half, width: handleSize, height: handleSize)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(box)
                ctx.stroke(box)
            }
            ctx.restoreGState()
        }
        if !snapGuides.xs.isEmpty || !snapGuides.ys.isEmpty {
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.systemPink.cgColor)
            ctx.setLineWidth(max(0.5, 1 / max(0.1, enclosingScrollView?.magnification ?? 1)))
            for x in snapGuides.xs { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: bounds.height)) }
            for y in snapGuides.ys { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: bounds.width, y: y)) }
            ctx.strokePath()
            ctx.restoreGState()
        }
        if let band = zoomBand {
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineDash(phase: 0, lengths: [5, 3])
            ctx.setLineWidth(max(1, 1.5 / max(0.1, enclosingScrollView?.magnification ?? 1)))
            ctx.stroke(band)
            ctx.restoreGState()
        }
        if let crop = selectionRect {
            ctx.saveGState()
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(crop)
            ctx.addPath(path)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            ctx.fillPath(using: .evenOdd)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(crop)
            ctx.restoreGState()
            drawSelectionLabel(for: crop)
        }
    }

    private func drawSelectionLabel(for crop: CGRect) {
        let px = "\(Int((crop.width * pixelScale).rounded())) × \(Int((crop.height * pixelScale).rounded()))"
        let text = crop.width >= 4 ? "\(px)  ·  ⏎ \(t("crop"))  ·  Esc" : px
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white,
        ]
        let size = NSString(string: text).size(withAttributes: attrs)
        let box = NSRect(x: crop.minX, y: crop.maxY + 4 + size.height + 6 <= bounds.maxY ? crop.maxY + 4 : max(0, crop.minY - size.height - 10),
                         width: size.width + 12, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        NSString(string: text).draw(at: NSPoint(x: box.minX + 6, y: box.minY + 2), withAttributes: attrs)
    }

    /// Handle squares stay roughly the same size on screen whatever the zoom.
    private var handleSize: CGFloat { 8 / max(0.1, enclosingScrollView?.magnification ?? 1) }

    public override func resetCursorRects() {
        let cursor: NSCursor
        switch tool {
        case .select: cursor = .arrow
        case .text: cursor = .iBeam
        default: cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: Mouse

    private func handle(at p: CGPoint, of a: Annotation) -> Handle? {
        let reach = handleSize * 1.2
        return a.handles().first { hypot($0.point.x - p.x, $0.point.y - p.y) <= reach }?.handle
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)  // commits any in-progress text
        let p = convert(event.locationInWindow, from: nil)
        movedSinceMouseDown = false
        activeHandle = nil
        if heldKeys.contains(6) { zoomAnchor = p; return }  // Z held: quick zoom instead of the tool

        // Grab points of the selected mark win over starting something new, whatever the tool.
        if tool != .crop, let a = selectedAnnotation, let h = handle(at: p, of: a) {
            activeHandle = h
            handleOriginal = a
            return
        }
        if tool == .counter || tool == .text,
           let existing = state.annotations.lastIndex(where: { $0.kind == tool && $0.hitTest(p) }) {
            if tool == .text, event.clickCount == 2 { selectedIndex = existing; editText(at: existing); return }
            if tool == .counter, event.clickCount == 2 { selectedIndex = existing; editCounter(at: existing); return }
            movingExisting = true
            var target = existing
            if event.modifierFlags.contains(.option) {                       // ⌥-drag duplicates here too
                let copy = state.annotations[existing]
                edit { $0.annotations.append(copy) }
                target = state.annotations.count - 1
            } else if existing != state.annotations.count - 1 {
                let mark = state.annotations.remove(at: existing)
                state.annotations.append(mark)
                target = state.annotations.count - 1
            }
            selectedIndex = target
            lastDragPoint = p
            moveOriginal = state.annotations[target]
            moveStart = p
            selectionRect = nil
            needsDisplay = true
            return
        }
        switch tool {
        case .select:
            let hit = state.annotations.lastIndex { $0.hitTest(p) }
            if event.clickCount == 2, let hit, state.annotations[hit].kind == .text {
                selectedIndex = hit
                editText(at: hit)
                return
            }
            if event.clickCount == 2, let hit, state.annotations[hit].kind == .counter {
                selectedIndex = hit
                editCounter(at: hit)
                return
            }
            if hit == nil, event.clickCount == 2, let sel = selectionRect, sel.contains(p) {
                applyCrop()
                return
            }
            if hit == nil, event.modifierFlags.contains(.command), let box = smartSelection(at: p) {  // ⌘-click a flat object
                selectedIndex = nil
                selectionRect = box
                needsDisplay = true
                return
            }
            var target = hit
            if let h = hit, event.modifierFlags.contains(.option) {          // Option-drag duplicates
                let copy = state.annotations[h]
                edit { $0.annotations.append(copy) }
                target = state.annotations.count - 1
            } else if let h = hit, h != state.annotations.count - 1 {        // the clicked mark comes to the front
                let mark = state.annotations.remove(at: h)
                state.annotations.append(mark)
                target = state.annotations.count - 1
                needsDisplay = true
            }
            selectedIndex = target
            lastDragPoint = target == nil ? nil : p
            moveOriginal = target.flatMap { state.annotations.indices.contains($0) ? state.annotations[$0] : nil }
            moveStart = p
            if hit == nil {  // empty space: start a selection
                marqueeAnchor = p
                selectionRect = nil
            } else {
                selectionRect = nil
            }
            needsDisplay = true
        case .text:
            selectedIndex = nil
            beginText(at: p)
        case .editText:
            selectedIndex = nil
            beginEditImageText(at: p)
        case .counter:
            var a = makeAnnotation(at: p)
            Self.applyCounterText(&a, nextCounterText)
            a.serial = (state.annotations.filter { $0.kind == .counter }.map(\.serial).max() ?? 0) + 1
            counterOverride = nil
            edit { $0.annotations.append(a) }
            selectedIndex = state.annotations.count - 1
        case .crop:
            marqueeAnchor = p
            selectionRect = nil
            needsDisplay = true
        case .ruler:
            rulerDownPoint = p  // a plain click imprints the live measurement; a drag draws a manual line
        default:
            selectedIndex = nil
            var d = makeAnnotation(at: p)
            if d.kind == .magnifier { d.bubble = nil }
            draft = d
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        var p = convert(event.locationInWindow, from: nil)
        hoverPoint = p
        if heldKeys.contains(49) { pan(to: event.locationInWindow); return }  // Space + drag pans
        if let z = zoomAnchor {  // Z + drag: rubber band for the area to zoom to
            selectionRect = nil
            zoomBand = Geometry.normalizedRect(from: z, to: p)
            needsDisplay = true
            return
        }
        if let h = activeHandle, let i = selectedIndex, let original = handleOriginal, state.annotations.indices.contains(i) {
            if !movedSinceMouseDown {
                movedSinceMouseDown = true
                pushUndo()
            }
            state.annotations[i] = original.moving(h, to: p)
            needsDisplay = true
            return
        }
        if let a = marqueeAnchor, tool == .select || tool == .crop {
            if event.modifierFlags.contains(.shift) { p = Self.constrained(from: a, to: p, kind: .rectangle) }
            selectionRect = Geometry.normalizedRect(from: a, to: clamp(p)).intersection(bounds)
            needsDisplay = true
            return
        }
        if tool == .ruler, draft == nil, let o = rulerDownPoint, hypot(p.x - o.x, p.y - o.y) >= 3 {
            draft = makeAnnotation(at: o)
            measurePreview = []
        }
        switch effectiveTool {
        case .select:
            guard let i = selectedIndex, let last = lastDragPoint, state.annotations.indices.contains(i) else { return }
            if !movedSinceMouseDown {
                movedSinceMouseDown = true
                pushUndo()  // one undo step per drag, taken before the first movement
            }
            _ = last
            if let original = moveOriginal, let start = moveStart {
                var moved = original.translated(by: CGPoint(x: p.x - start.x, y: p.y - start.y))
                snapGuides = ([], [])
                if Settings.shared.snapToObjects, !event.modifierFlags.contains(.control) {
                    let reach = 6 / max(0.1, enclosingScrollView?.magnification ?? 1)
                    var targets = state.annotations.enumerated().filter { $0.offset != i }.map { $0.element.bounds }
                    targets.append(CGRect(origin: .zero, size: pointSize))
                    let snap = Snap.adjust(moving: moved.bounds, targets: targets, threshold: reach)
                    if snap.dx != 0 || snap.dy != 0 { moved = moved.translated(by: CGPoint(x: snap.dx, y: snap.dy)) }
                    snapGuides = (snap.guideXs, snap.guideYs)
                }
                state.annotations[i] = moved
            }
            lastDragPoint = p
            needsDisplay = true
        default:
            guard var d = draft else { return }
            if event.modifierFlags.contains(.shift) { p = Self.constrained(from: d.start, to: p, kind: d.kind == .highlight && d.marker ? .line : d.kind) }
            d.end = p
            if d.kind == .freehand { d.points.append(p) }
            draft = d
            needsDisplay = true
        }
    }

    public override func mouseUp(with event: NSEvent) {
        if let z = zoomAnchor {
            zoomAnchor = nil
            let band = zoomBand
            zoomBand = nil
            needsDisplay = true
            if let band, band.width > 4, band.height > 4 { onZoomCommand?(.area(band)) }
            else { onZoomCommand?(.point(z, out: event.modifierFlags.contains(.option))) }
            return
        }
        if activeHandle != nil {
            if movedSinceMouseDown {
                if !expandCanvasIfNeeded() { stateDidChange() }
            }
            activeHandle = nil
            handleOriginal = nil
            return
        }
        if marqueeAnchor != nil {
            marqueeAnchor = nil
            if let r = selectionRect, r.width < 4 || r.height < 4 { selectionRect = nil }
            needsDisplay = true
            return
        }
        switch effectiveTool {
        case .select:
            if movedSinceMouseDown { onChange?() }
            lastDragPoint = nil
            moveOriginal = nil
            movingExisting = false
            if !snapGuides.xs.isEmpty || !snapGuides.ys.isEmpty { snapGuides = ([], []); needsDisplay = true }
        case .crop:
            break
        case .counter, .text:
            break
        case .ruler where draft == nil:
            rulerDownPoint = nil
            let marks = measurePreview
            if !marks.isEmpty { edit { $0.annotations.append(contentsOf: marks) } }
        default:
            rulerDownPoint = nil
            guard var d = draft else { return }
            draft = nil
            let moved = hypot(d.end.x - d.start.x, d.end.y - d.start.y) >= 3 || d.points.count > 2
            if moved, d.kind == .arrow, event.modifierFlags.contains(.command) { swap(&d.start, &d.end) }  // ⌘: reversed arrow
            if moved {
                if d.kind == .magnifier { d.bubble = bubbleCenter(for: d) }
                edit { $0.annotations.append(d) }
                expandCanvasIfNeeded()  // a magnifier whose bubble sticks out makes the canvas grow
                selectedIndex = state.annotations.count - 1
            } else { needsDisplay = true }
        }
    }

    /// Puts a new magnifier's bubble on the first side (right, left, below, above) where it fits inside the
    /// image; if none does it goes to the right and the canvas expands to hold it.
    private func bubbleCenter(for a: Annotation) -> CGPoint {
        let r = a.sourceRadius, br = a.bubbleRadius, gap: CGFloat = 10
        let reach = r + br + gap
        let image = CGRect(origin: .zero, size: pointSize)
        let candidates = [
            CGPoint(x: a.start.x + reach, y: a.start.y), CGPoint(x: a.start.x - reach, y: a.start.y),
            CGPoint(x: a.start.x, y: a.start.y + reach), CGPoint(x: a.start.x, y: a.start.y - reach),
        ]
        return candidates.first { image.contains(CGRect(x: $0.x - br, y: $0.y - br, width: br * 2, height: br * 2)) } ?? candidates[0]
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    /// Shift snaps lines/arrows to 45° steps and boxes to squares.
    static func constrained(from a: CGPoint, to b: CGPoint, kind: ToolKind) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        switch kind {
        case .line, .arrow, .ruler:
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            let length = hypot(dx, dy)
            return CGPoint(x: a.x + length * cos(angle), y: a.y + length * sin(angle))
        case .rectangle, .ellipse, .highlight, .blur, .spotlight:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: a.x + (dx < 0 ? -side : side), y: a.y + (dy < 0 ? -side : side))
        default:
            return b
        }
    }

    // MARK: Keyboard

    public override func keyDown(with event: NSEvent) {
        heldKeys.insert(event.keyCode)
        let shift = event.modifierFlags.contains(.shift)
        let command = event.modifierFlags.contains(.command)
        if event.keyCode == 6, !command { return }  // Z: held for quick zoom (click or drag)
        let step: CGFloat = shift ? 10 : 1
        if event.keyCode == 53 {
            if selectionRect != nil { selectionRect = nil; needsDisplay = true; return }
            onEscape?()
            return
        }
        if event.keyCode == 48 { copyHoverColor(darkest: shift); return }  // Tab / Shift+Tab

        // Ruler guides: Option+S puts a vertical line at the pointer, Option+D a horizontal one; click to keep it.
        if tool == .ruler, event.modifierFlags.contains(.option), event.keyCode == 1 || event.keyCode == 2 {
            guideKeys.insert(event.keyCode)
            updateMeasure()
            return
        }
        // A rubber-band selection: Enter crops, arrows move it, ⌘+arrows resize it, [ ] grow/shrink it, C copies its mean colour.
        if selectionRect != nil, selectedIndex == nil {
            switch event.keyCode {
            case 36, 76: applyCrop(); return
            case 123...126: adjustSelection(keyCode: event.keyCode, step: step, resize: command); return
            case 0 where !command: autoAdjustSelection(); return
            case 12 where !command: onZoomCommand?(.selectionTopLeft); return
            case 13 where !command: onZoomCommand?(.selectionBottomRight); return
            case 33: growSelection(by: -step); return
            case 30: growSelection(by: step); return
            case 8 where !command: copySelectionAverageColor(); return
            default: break
            }
        }
        // Ruler: it measures by itself; hold 1 / ↑↓ for height only, 2 / ←→ for width only.
        if tool == .ruler, [123, 124, 125, 126, 18, 19].contains(event.keyCode) {
            updateMeasure()
            return
        }
        // ⌥↑ / ⌥↓: pen smoothness
        if event.modifierFlags.contains(.option), event.keyCode == 125 || event.keyCode == 126, styleTarget?.kind == .freehand {
            let delta = event.keyCode == 126 ? 1 : -1
            let current = styleTarget?.level ?? 0
            updateStyle { $0.level = min(4, max(0, current + delta)) }
            onStyleContextChange?()
            return
        }
        switch event.keyCode {
        case 51, 117: deleteSelected(); return
        case 123: nudgeSelected(dx: -step, dy: 0); return
        case 124: nudgeSelected(dx: step, dy: 0); return
        case 125: nudgeSelected(dx: 0, dy: step); return
        case 126: nudgeSelected(dx: 0, dy: -step); return
        default: break
        }
        let blockers: NSEvent.ModifierFlags = [.command, .control, .option]
        if event.modifierFlags.intersection(blockers).isEmpty {
            // 1…9 set the spotlight's darkness, like Shottr.
            if let ch = event.charactersIgnoringModifiers, let n = Int(ch), (1...9).contains(n), styleTarget?.kind == .spotlight {
                updateStyle { $0.level = n }
                onStyleContextChange?()
                return
            }
            // 1…9 set a pasted picture's opacity in tenths (5 = half transparent, for comparing two versions).
            if let ch = event.charactersIgnoringModifiers, let n = Int(ch), (1...9).contains(n), selectedAnnotation?.kind == .image {
                updateStyle { $0.level = n }
                onStyleContextChange?()
                return
            }
            if let key = event.charactersIgnoringModifiers?.lowercased(), let tool = Self.shortcuts[key] {
                onToolShortcut?(tool)
                return
            }
        }
        super.keyDown(with: event)
    }

    public override func keyUp(with event: NSEvent) {
        heldKeys.remove(event.keyCode)
        guideKeys.remove(event.keyCode)
        if tool == .ruler { updateMeasure() }
        super.keyUp(with: event)
    }

    public override func flagsChanged(with event: NSEvent) {
        if tool == .ruler { updateMeasure() }
        super.flagsChanged(with: event)
    }

    public override func resignFirstResponder() -> Bool {
        heldKeys.removeAll()
        guideKeys.removeAll()
        measurePreview = []
        needsDisplay = true
        return super.resignFirstResponder()
    }

    // MARK: Selection (rubber band)

    /// Moves (or, with `resize`, grows/shrinks) the selection by `step` image pixels.
    private func adjustSelection(keyCode: UInt16, step: CGFloat, resize: Bool) {
        guard var r = selectionRect else { return }
        let unit = step / pixelScale
        var dx: CGFloat = 0, dy: CGFloat = 0
        switch keyCode {
        case 123: dx = -unit
        case 124: dx = unit
        case 125: dy = unit
        default: dy = -unit
        }
        if resize {
            r.size.width = max(1 / pixelScale, r.width + dx)
            r.size.height = max(1 / pixelScale, r.height + dy)
        } else {
            r.origin.x += dx
            r.origin.y += dy
        }
        r.origin.x = min(max(0, r.origin.x), max(0, bounds.width - r.width))
        r.origin.y = min(max(0, r.origin.y), max(0, bounds.height - r.height))
        r.size.width = min(r.width, bounds.width - r.minX)
        r.size.height = min(r.height, bounds.height - r.minY)
        selectionRect = r
        needsDisplay = true
    }

    private func growSelection(by step: CGFloat) {
        guard let r = selectionRect else { return }
        let unit = step / pixelScale
        let grown = r.insetBy(dx: -unit, dy: -unit).intersection(bounds)
        if grown.width >= 1 / pixelScale, grown.height >= 1 / pixelScale { selectionRect = grown; needsDisplay = true }
    }

    /// ⌘-click: the connected flat-coloured object under the pointer, as a selection (image points).
    public func smartSelection(at p: CGPoint) -> CGRect? {
        guard let probe = currentProbe(),
              let b = probe.floodBounds(x: Int(p.x * pixelScale), y: Int(p.y * pixelScale)) else { return nil }
        let r = CGRect(x: CGFloat(b.x0) / pixelScale, y: CGFloat(b.y0) / pixelScale,
                       width: CGFloat(b.x1 - b.x0 + 1) / pixelScale, height: CGFloat(b.y1 - b.y0 + 1) / pixelScale)
        return r.width >= 2 && r.height >= 2 && r.size != pointSize ? r : nil
    }

    /// A: snaps the selection to the content inside it; if it holds only flat colour, grows it to that flat object instead.
    public func autoAdjustSelection() {
        guard let sel = selectionPixelRect, let probe = currentProbe() else { return }
        if let tight = probe.contentBounds(x0: Int(sel.minX), y0: Int(sel.minY), x1: Int(sel.maxX) - 1, y1: Int(sel.maxY) - 1) {
            selectionRect = CGRect(x: CGFloat(tight.x0) / pixelScale, y: CGFloat(tight.y0) / pixelScale,
                                   width: CGFloat(tight.x1 - tight.x0 + 1) / pixelScale, height: CGFloat(tight.y1 - tight.y0 + 1) / pixelScale)
        } else if let b = probe.floodBounds(x: Int(sel.midX), y: Int(sel.midY)) {
            selectionRect = CGRect(x: CGFloat(b.x0) / pixelScale, y: CGFloat(b.y0) / pixelScale,
                                   width: CGFloat(b.x1 - b.x0 + 1) / pixelScale, height: CGFloat(b.y1 - b.y0 + 1) / pixelScale)
        }
        needsDisplay = true
    }

    public func setSelection(_ rect: CGRect?) {
        selectionRect = rect.map { $0.intersection(bounds) }
        needsDisplay = true
    }

    /// The selection in image pixels (whole pixels, inside the image).
    public var selectionPixelRect: CGRect? {
        guard let r = selectionRect else { return nil }
        let px = CGRect(x: r.minX * pixelScale, y: r.minY * pixelScale, width: r.width * pixelScale, height: r.height * pixelScale)
            .integral.intersection(CGRect(x: 0, y: 0, width: state.image.width, height: state.image.height))
        return px.isNull || px.isEmpty ? nil : px
    }

    /// The selected part of the base image (without marks), e.g. for OCR.
    public func selectionImage() -> CGImage? {
        selectionPixelRect.flatMap { state.image.cropping(to: $0) }
    }

    /// Crops the image to the selection (Enter).
    public func applyCrop() {
        guard let r = selectionRect, r.width >= 1, r.height >= 1 else { return }
        selectionRect = nil
        crop(to: r)
    }

    // MARK: Pointer probing: colour readout and edge-measuring ruler

    private func currentProbe() -> PixelProbe? {
        if probedImage !== state.image {
            probe = PixelProbe(image: state.image)
            probedImage = state.image
        }
        return probe
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    public override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        hoverPoint = p
        func ns(_ c: PixelProbe.RGB?) -> NSColor? { c.map { NSColor(srgbRed: CGFloat($0.r) / 255, green: CGFloat($0.g) / 255, blue: CGFloat($0.b) / 255, alpha: 1) } }
        let under = pixelColor(at: p)
        // The darkest pixel within 10 px is the colour of any text there; it feeds the contrast readout.
        let text = currentProbe()?.darkest(x: Int(p.x * pixelScale), y: Int(p.y * pixelScale))
        onHoverColor?(ns(under), ns(text))
        if tool == .ruler { updateMeasure() }
    }

    public override func mouseExited(with event: NSEvent) {
        hoverPoint = nil
        onHoverColor?(nil, nil)
        if !measurePreview.isEmpty { measurePreview = []; needsDisplay = true }
    }

    public func pixelColor(at p: CGPoint) -> PixelProbe.RGB? {
        currentProbe()?.color(x: Int((p.x * pixelScale).rounded(.down)), y: Int((p.y * pixelScale).rounded(.down)))
    }

    private func copyColor(_ c: PixelProbe.RGB?) {
        guard let c else { return }
        let text = ColorFormats.string(r: Double(c.r) / 255, g: Double(c.g) / 255, b: Double(c.b) / 255, format: Settings.shared.colorFormat)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Toast.show("\(t("Copied")): \(text)")
    }

    /// Tab copies the colour under the pointer; Shift+Tab the darkest pixel within 10 px (the colour of text).
    public func copyHoverColor(darkest: Bool) {
        guard let p = hoverPoint, let probe = currentProbe() else { return }
        let x = Int(p.x * pixelScale), y = Int(p.y * pixelScale)
        copyColor(darkest ? probe.darkest(x: x, y: y) : probe.color(x: x, y: y))
    }

    public func copySelectionAverageColor() {
        guard let r = selectionPixelRect, let probe = currentProbe() else { return }
        copyColor(probe.average(x0: Int(r.minX), y0: Int(r.minY), x1: Int(r.maxX) - 1, y1: Int(r.maxY) - 1))
    }

    /// Ruler marks for the flat-coloured element under `p`, one per requested axis.
    public func measureMarks(at p: CGPoint, horizontal: Bool, vertical: Bool, outer: Bool = false) -> [Annotation] {
        guard let probe = currentProbe() else { return [] }
        let x = Int((p.x * pixelScale).rounded(.down)), y = Int((p.y * pixelScale).rounded(.down))
        var style = templates[.ruler] ?? Annotation(kind: .ruler, start: .zero, end: .zero)
        style.number = 0
        var marks: [Annotation] = []
        if horizontal, let r = probe.run(x: x, y: y, horizontal: true, maxGap: outer ? 48 : 0) {
            var a = style
            a.start = CGPoint(x: CGFloat(r.lowerBound) / pixelScale, y: p.y)
            a.end = CGPoint(x: CGFloat(r.upperBound + 1) / pixelScale, y: p.y)
            marks.append(a)
        }
        if vertical, let r = probe.run(x: x, y: y, horizontal: false, maxGap: outer ? 48 : 0) {
            var a = style
            a.start = CGPoint(x: p.x, y: CGFloat(r.lowerBound) / pixelScale)
            a.end = CGPoint(x: p.x, y: CGFloat(r.upperBound + 1) / pixelScale)
            marks.append(a)
        }
        return marks
    }

    /// Live ruler: with nothing held it measures the flat element under the pointer both ways; 1 or ↑↓ restricts to
    /// height, 2 or ←→ to width. Option+S / Option+D show full-length guide lines instead.
    private func updateMeasure() {
        defer { needsDisplay = true }
        measurePreview = []
        guard tool == .ruler, let p = hoverPoint else { return }
        if !guideKeys.isEmpty {
            var guide = templates[.ruler] ?? Annotation(kind: .ruler, start: .zero, end: .zero)
            guide.kind = .line
            guide.lineWidth = 1
            if guideKeys.contains(1) { var g = guide; g.start = CGPoint(x: p.x, y: 0); g.end = CGPoint(x: p.x, y: pointSize.height); measurePreview.append(g) }
            if guideKeys.contains(2) { var g = guide; g.start = CGPoint(x: 0, y: p.y); g.end = CGPoint(x: pointSize.width, y: p.y); measurePreview.append(g) }
            return
        }
        let vertical = !heldKeys.isDisjoint(with: [125, 126, 18])
        let horizontal = !heldKeys.isDisjoint(with: [123, 124, 19])
        let both = !vertical && !horizontal
        // Shift: the outer size (measure through text and icons to the element's real edges).
        measurePreview = measureMarks(at: p, horizontal: horizontal || both, vertical: vertical || both,
                                      outer: NSEvent.modifierFlags.contains(.shift))
    }

    // MARK: Panning, copy & paste of marks

    /// Space+drag and right-button drag move the view like a hand tool.
    private func pan(to windowPoint: CGPoint) {
        defer { lastPanPoint = windowPoint }
        guard let last = lastPanPoint, let clip = enclosingScrollView?.contentView else { return }
        let mag = max(0.1, enclosingScrollView?.magnification ?? 1)
        var origin = clip.bounds.origin
        origin.x -= (windowPoint.x - last.x) / mag
        origin.y += (windowPoint.y - last.y) / mag   // the document is flipped
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    public override func rightMouseDown(with event: NSEvent) { lastPanPoint = event.locationInWindow }
    public override func rightMouseDragged(with event: NSEvent) { pan(to: event.locationInWindow) }
    public override func rightMouseUp(with event: NSEvent) { lastPanPoint = nil }

    public var hasSelectedMark: Bool { selectedAnnotation != nil }

    /// ⌘C on a selected mark: remembered inside the app (the system clipboard keeps a marker so a later image copy wins).
    @discardableResult
    public func copySelectedMark() -> Bool {
        guard let a = selectedAnnotation else { return false }
        objectClipboard = a
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Tenix-ChaeDiew mark", forType: .string)
        objectClipboardChange = NSPasteboard.general.changeCount
        return true
    }

    /// ⌘V: pastes the copied mark (slightly offset) if nothing was copied since; false means "paste an image instead".
    @discardableResult
    public func pasteMark() -> Bool {
        guard let a = objectClipboard, objectClipboardChange == NSPasteboard.general.changeCount else { return false }
        let copy = a.translated(by: CGPoint(x: 12, y: 12))
        edit { $0.annotations.append(copy) }
        selectedIndex = state.annotations.count - 1
        objectClipboard = copy
        return true
    }

    // MARK: Text

    private func beginText(at p: CGPoint, initial: String = "") {
        let style = templates[.text] ?? Annotation(kind: .text, start: p, end: p)
        let field = NSTextField(frame: NSRect(x: p.x, y: p.y, width: 60, height: style.fontSize + 10))
        field.isBordered = false
        field.focusRingType = .none
        styleTextField(field)
        field.stringValue = initial
        field.delegate = self
        field.target = self
        field.action = #selector(commitText)
        addSubview(field)
        fitTextField(field)
        window?.makeFirstResponder(field)
        // Putting the caret at the end: typing then adds to existing text instead of replacing it all.
        if let editor = field.currentEditor() { editor.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0) }
        textField = field
    }

    /// Makes the typing field look like the finished label (typeface, size, colours), and keeps it in step with the panel.
    private func styleTextField(_ field: NSTextField) {
        let style = templates[.text] ?? Annotation(kind: .text, start: .zero, end: .zero)
        field.drawsBackground = style.pill
        field.backgroundColor = style.color
        field.font = style.textFont
        field.textColor = style.pill ? style.labelTextColor : style.color
        if let editor = field.currentEditor() as? NSTextView {
            editor.insertionPointColor = field.textColor ?? .labelColor
            editor.textColor = field.textColor
            editor.font = field.font
        }
        field.setFrameSize(NSSize(width: field.frame.width, height: style.fontSize + 10))
        fitTextField(field)
    }

    private func fitTextField(_ field: NSTextField) {
        let width = NSString(string: field.stringValue.isEmpty ? " " : field.stringValue)
            .size(withAttributes: [.font: field.font ?? NSFont.boldSystemFont(ofSize: 18)]).width
        field.setFrameSize(NSSize(width: max(60, ceil(width) + 16), height: field.frame.height))
    }

    public func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField, field === textField { fitTextField(field) }
    }

    // MARK: Retyping text that is part of the screenshot

    /// OCR (once per image) finds the line under the pointer; a field with the line's own typeface, size and colours opens on it.
    private func beginEditImageText(at p: CGPoint) {
        commitImageText()
        let image = state.image
        let scale = pixelScale
        Task { @MainActor in
            if recognisedLines?.image !== image {
                Toast.show(t("Reading text…"), duration: 1.5)
                recognisedLines = (image, (try? await OCR.recognizeLines(image)) ?? [])
            }
            guard image === state.image, let lines = recognisedLines?.lines else { return }
            let px = CGPoint(x: p.x * scale, y: p.y * scale)
            let hit = lines.compactMap { line -> (RecognizedLine, CGRect)? in
                guard let r = line.pixelRect(for: line.text.startIndex..<line.text.endIndex) else { return nil }
                return r.insetBy(dx: -6, dy: -6).contains(px) ? (line, r) : nil
            }.first
            guard let (line, rect) = hit else { return Toast.show(t("No text found here")) }
            let guess = await Task.detached(priority: .userInitiated) {
                FontMatcher.guess(image: image, lineRect: rect, text: line.text, pixelScale: scale)
            }.value
            guard let guess else { return Toast.show(t("Could not match this text")) }
            openImageTextField(original: line.text, lineRect: rect, guess: guess)
        }
    }

    private func openImageTextField(original: String, lineRect: CGRect, guess: TextStyleGuess) {
        let pt = CGRect(x: lineRect.minX / pixelScale, y: lineRect.minY / pixelScale, width: lineRect.width / pixelScale, height: lineRect.height / pixelScale)
        var style = Annotation(kind: .text, start: .zero, end: .zero, color: guess.ink, fontSize: guess.sizePoints, fontName: guess.fontName, fontBold: guess.bold)
        style.text = original
        let origin = CGPoint(x: guess.originPixels.x / pixelScale, y: guess.originPixels.y / pixelScale)
        let field = NSTextField(frame: NSRect(x: origin.x - 2, y: origin.y - 3, width: pt.width + 16, height: guess.sizePoints * 1.4 + 6))
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.backgroundColor = guess.background
        field.font = style.textFont
        field.textColor = guess.ink
        field.stringValue = original
        field.delegate = self
        field.target = self
        field.action = #selector(commitImageText)
        addSubview(field)
        window?.makeFirstResponder(field)
        if let editor = field.currentEditor() as? NSTextView {
            editor.insertionPointColor = guess.ink
            editor.selectedRange = NSRange(location: (original as NSString).length, length: 0)
        }
        imageTextField = field
        imageTextEdit = (pt, guess, original)
    }

    /// Enter / click away: the original text is erased (background restored) and the new text is set where it was.
    /// One undo step; an empty field just deletes the text.
    @objc private func commitImageText() {
        guard let field = imageTextField, let info = imageTextEdit else { return }
        imageTextField = nil
        imageTextEdit = nil
        let string = field.stringValue
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        guard string != info.original else { needsDisplay = true; return }
        let cover = info.rect.insetBy(dx: -2, dy: -2)
        var erase = Annotation(kind: .blur, start: cover.origin, end: CGPoint(x: cover.maxX, y: cover.maxY), blurMode: .eraseText)
        erase.level = 5
        var newText = Annotation(
            kind: .text, start: CGPoint(x: info.guess.originPixels.x / pixelScale, y: info.guess.originPixels.y / pixelScale),
            end: .zero, color: info.guess.ink, text: string, fontSize: info.guess.sizePoints,
            pill: false, fontName: info.guess.fontName, fontBold: info.guess.bold)
        newText.end = newText.start
        edit {
            $0.annotations.append(erase)
            if !string.isEmpty { $0.annotations.append(newText) }
        }
        if !string.isEmpty { selectedIndex = state.annotations.count - 1 }
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)), control === imageTextField {
            imageTextField?.stringValue = imageTextEdit?.original ?? ""   // Esc: leave the picture untouched
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    // MARK: Counter text

    /// Double-click on a counter: type any text for it ("1.1", "3.6", "A2"). Counters placed afterwards continue from it.
    private func editCounter(at index: Int) {
        commitText()
        commitCounter()
        guard state.annotations.indices.contains(index) else { return }
        let a = state.annotations[index]
        let box = a.bounds
        let field = NSTextField(frame: NSRect(x: box.midX - max(36, box.width / 2 + 10), y: box.midY - 13, width: max(72, box.width + 20), height: 26))
        field.stringValue = a.counterText
        field.alignment = .center
        field.font = .boldSystemFont(ofSize: 14)
        field.focusRingType = .default
        field.delegate = self
        field.target = self
        field.action = #selector(commitCounter)
        addSubview(field)
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        counterField = field
        counterEditIndex = index
    }

    @objc private func commitCounter() {
        guard let field = counterField, let i = counterEditIndex else { return }
        counterField = nil
        counterEditIndex = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        field.removeFromSuperview()
        if !text.isEmpty, state.annotations.indices.contains(i), text != state.annotations[i].counterText {
            let serial = (state.annotations.filter { $0.kind == .counter }.map(\.serial).max() ?? 0) + 1
            edit {
                Self.applyCounterText(&$0.annotations[i], text)
                $0.annotations[i].serial = serial   // the edited counter becomes the one the next continues from
            }
        }
        window?.makeFirstResponder(self)
        onStyleContextChange?()
    }

    /// Re-opens an existing text mark for editing; the change is one undo step.
    private func editText(at index: Int) {
        commitText()
        guard state.annotations.indices.contains(index) else { return }
        let a = state.annotations[index]
        pushUndo()
        textEditPushedUndo = true
        state.annotations.remove(at: index)
        selectedIndex = nil
        // Keep the mark's own look while editing.
        templates[.text] = { var t = a; t.text = ""; t.number = 0; return t }()
        needsDisplay = true
        let inset: (x: CGFloat, y: CGFloat) = a.pill ? (-6, 1) : (2, 3)
        beginText(at: CGPoint(x: a.start.x - inset.x, y: a.start.y - inset.y), initial: a.text)
    }

    @objc private func commitText() {
        guard let field = textField else { return }
        textField = nil
        let string = field.stringValue
        let origin = field.frame.origin
        let style = templates[.text] ?? Annotation(kind: .text, start: .zero, end: .zero)
        field.removeFromSuperview()
        let pushed = textEditPushedUndo
        textEditPushedUndo = false
        if !string.isEmpty {
            // The field insets its text slightly; match that so committed text doesn't jump.
            let at = style.pill ? CGPoint(x: origin.x - 6, y: origin.y - 1) : CGPoint(x: origin.x + 2, y: origin.y + 3)
            var a = style
            a.start = at; a.end = at; a.text = string; a.number = 0
            if pushed {
                state.annotations.append(a)
                stateDidChange()
            } else {
                edit { $0.annotations.append(a) }
            }
            selectedIndex = state.annotations.count - 1
        } else if pushed {
            stateDidChange()
        }
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        if let field = obj.object as? NSTextField, field === counterField { commitCounter() }
        else if let field = obj.object as? NSTextField, field === imageTextField { commitImageText() }
        else { commitText() }
    }

    // MARK: Edits & history

    private func pushUndo() {
        undoStack.append(state)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        coalescingStyle = false
    }

    /// Applies one undoable change.
    private func edit(_ body: (inout EditState) -> Void) {
        pushUndo()
        body(&state)
        stateDidChange()
    }

    private func stateDidChange() {
        selectionRect = nil
        if let i = selectedIndex, !state.annotations.indices.contains(i) { selectedIndex = nil }
        if frame.size != pointSize { setFrameSize(pointSize) }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        onChange?()
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func undo() {
        commitText()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(state)
        state = previous
        coalescingStyle = false
        stateDidChange()
        onStyleContextChange?()
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state)
        state = next
        coalescingStyle = false
        stateDidChange()
        onStyleContextChange?()
    }

    /// Adds a mark programmatically (one undo step).
    public func append(_ annotation: Annotation) { edit { $0.annotations.append(annotation) } }

    /// Selects the mark at `index` (nil clears the selection).
    public func select(_ index: Int?) {
        selectedIndex = index.flatMap { state.annotations.indices.contains($0) ? $0 : nil }
        needsDisplay = true
    }

    public func deleteSelected() {
        guard let i = selectedIndex, state.annotations.indices.contains(i) else { return }
        selectedIndex = nil
        edit { $0.annotations.remove(at: i) }
    }

    private func nudgeSelected(dx: CGFloat, dy: CGFloat) {
        guard let i = selectedIndex, state.annotations.indices.contains(i) else { return }
        edit { $0.annotations[i] = $0.annotations[i].translated(by: CGPoint(x: dx, y: dy)) }
    }

    /// Adds pixelation over each pixel-space rectangle (used by auto-redact) as one undo step.
    public func addPixelation(pixelRects: [CGRect]) {
        guard !pixelRects.isEmpty else { return }
        edit { state in
            for r in pixelRects {
                let pts = CGRect(x: r.minX / pixelScale, y: r.minY / pixelScale,
                                 width: r.width / pixelScale, height: r.height / pixelScale)
                state.annotations.append(Annotation(kind: .blur, start: pts.origin, end: CGPoint(x: pts.maxX, y: pts.maxY)))
            }
        }
    }

    /// Crops the base image to `crop` (image points); marks move with it. One undo step.
    public func crop(to crop: CGRect) {
        let pixelRect = CGRect(
            x: crop.minX * pixelScale, y: crop.minY * pixelScale,
            width: crop.width * pixelScale, height: crop.height * pixelScale
        ).integral.intersection(CGRect(x: 0, y: 0, width: state.image.width, height: state.image.height))
        guard let cropped = state.image.cropping(to: pixelRect) else { return }
        let shift = CGPoint(x: -pixelRect.minX / pixelScale, y: -pixelRect.minY / pixelScale)
        edit {
            $0.image = cropped
            $0.annotations = $0.annotations.map { $0.translated(by: shift) }
        }
    }

    /// Resamples the image by `factor`; marks scale with it.
    public func resize(by factor: CGFloat) {
        let w = max(1, Int((CGFloat(state.image.width) * factor).rounded()))
        let h = max(1, Int((CGFloat(state.image.height) * factor).rounded()))
        guard w != state.image.width, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        ctx.interpolationQuality = .high
        ctx.draw(state.image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let resized = ctx.makeImage() else { return }
        let applied = CGFloat(w) / CGFloat(state.image.width)
        edit {
            $0.image = resized
            $0.annotations = $0.annotations.map { $0.scaled(by: applied) }
        }
    }

    // MARK: Image operations (rasterize, paste, add capture, auto-expanding canvas)

    /// The state with the canvas grown so every magnifier bubble and pasted picture is fully inside; nil if nothing sticks out.
    private func expanded(_ s: EditState) -> EditState? {
        let size = CGSize(width: CGFloat(s.image.width) / pixelScale, height: CGFloat(s.image.height) / pixelScale)
        var union = CGRect(origin: .zero, size: size)
        for a in s.annotations where a.kind == .magnifier || a.kind == .image {
            union = union.union(a.bounds.insetBy(dx: -3, dy: -3))
        }
        let left = max(0, Int(ceil(-union.minX * pixelScale))), top = max(0, Int(ceil(-union.minY * pixelScale)))
        let right = max(0, Int(ceil((union.maxX - size.width) * pixelScale))), bottom = max(0, Int(ceil((union.maxY - size.height) * pixelScale)))
        guard left + top + right + bottom > 0,
              let padded = ImageOps.padded(s.image, left: left, top: top, right: right, bottom: bottom, fill: ImageOps.edgeColor(of: s.image))
        else { return nil }
        let shift = CGPoint(x: CGFloat(left) / pixelScale, y: CGFloat(top) / pixelScale)
        var out = s
        out.image = padded
        out.annotations = s.annotations.map { $0.translated(by: shift) }
        return out
    }

    /// Grows the canvas in place (inside the current undo step) when something sticks out. Returns whether it grew.
    @discardableResult
    public func expandCanvasIfNeeded() -> Bool {
        guard let grown = expanded(state) else { return false }
        state = grown
        stateDidChange()
        return true
    }

    /// Bakes all marks into the image ("Rasterize / Merge"). One undo step; marks become part of the pixels.
    @discardableResult
    public func rasterize() -> Bool {
        commitText()
        guard !state.annotations.isEmpty else { return false }
        let base = expanded(state) ?? state
        guard let merged = AnnotationRenderer.export(image: base.image, pixelScale: pixelScale, annotations: base.annotations) else { return false }
        selectedIndex = nil
        edit {
            $0.image = merged
            $0.annotations = []
        }
        return true
    }

    /// Lays a picture over the screenshot as a movable, resizable mark (large pictures are shrunk to fit).
    public func addImageOverlay(_ picture: CGImage, imageScale: CGFloat, at center: CGPoint? = nil) {
        var w = CGFloat(picture.width) / imageScale, h = CGFloat(picture.height) / imageScale
        let fit = min(1, pointSize.width * 0.8 / w, pointSize.height * 0.8 / h)
        w *= fit; h *= fit
        let c = center ?? CGPoint(x: pointSize.width / 2, y: pointSize.height / 2)
        let origin = CGPoint(x: min(max(0, c.x - w / 2), max(0, pointSize.width - w)),
                             y: min(max(0, c.y - h / 2), max(0, pointSize.height - h)))
        let mark = Annotation(kind: .image, start: origin, end: CGPoint(x: origin.x + w, y: origin.y + h), image: picture)
        if let onToolShortcut { onToolShortcut(.select) } else { tool = .select }
        edit { $0.annotations.append(mark) }
        selectedIndex = state.annotations.count - 1
    }

    /// Joins another capture to the image (Add Capture): below it when about as wide, otherwise to its right.
    public func appendImage(_ new: CGImage, edge: ImageOps.Edge? = nil) {
        let side = edge ?? ImageOps.preferredEdge(base: state.image, new: new)
        guard let merged = ImageOps.appended(new, to: state.image, edge: side) else { return }
        edit { $0.image = merged }
    }

    public func exportImage() -> CGImage? {
        commitText()
        commitCounter()
        commitImageText()
        return AnnotationRenderer.export(image: state.image, pixelScale: pixelScale, annotations: state.annotations)
    }
}
