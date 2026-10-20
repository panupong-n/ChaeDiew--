import AppKit

/// Floating per-object style panel at the canvas' top-right: colour, thickness and the options that
/// belong to the selected mark (or, with nothing selected, to the active drawing tool).
@MainActor
final class StylePanel: DraggableEffectView {
    private weak var canvas: CanvasView?
    private let stack = NSStackView()
    private var actions: [ControlAction] = []

    private static let swatches: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .black, .white,
    ]

    init(canvas: CanvasView) {
        self.canvas = canvas
        super.init(frame: .zero)
        applyPanelSkin()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 312),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Building

    func reload() {
        actions.removeAll()
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        guard let target = canvas?.styleTarget else { isHidden = true; return }
        isHidden = false

        if target.kind != .blur {
            add(target.kind == .text && target.pill ? t("Label color") : t("Color"), colorRow(target.color) { $0.color = $1 ?? $0.color })
        }
        switch target.kind {
        case .rectangle:
            add(t("Thickness"), slider(1, 14, target.lineWidth) { $0.lineWidth = $1 })
            add(t("Fill"), segmented([t("Outline"), t("Hatch"), t("Solid")], target.fill.rawValue) { $0.fill = FillStyle(rawValue: $1) ?? .outline })
            add(t("Corners"), segmented([t("Round"), t("Square")], target.rounded ? 0 : 1) { $0.rounded = $1 == 0 })
            add(t("Look"), sketchControl(target))
        case .ellipse:
            add(t("Thickness"), slider(1, 14, target.lineWidth) { $0.lineWidth = $1 })
            add(t("Fill"), segmented([t("Outline"), t("Hatch"), t("Solid")], target.fill.rawValue) { $0.fill = FillStyle(rawValue: $1) ?? .outline })
            add(t("Look"), sketchControl(target))
        case .line:
            add(t("Thickness"), slider(1, 14, target.lineWidth) { $0.lineWidth = $1 })
            add(t("Look"), sketchControl(target))
        case .freehand:
            add(t("Thickness"), slider(1, 14, target.lineWidth) { $0.lineWidth = $1 })
            add(t("Smoothness"), slider(0, 4, CGFloat(target.level)) { $0.level = Int($1.rounded()) })
            note(t("⌥↑ / ⌥↓ change the smoothness"))
        case .ruler:
            add(t("Thickness"), slider(1, 14, target.lineWidth) { $0.lineWidth = $1 })
            add(t("Units"), segmented([t("Points"), t("Pixels")], target.level == 1 ? 0 : 1) { $0.level = $1 == 0 ? 1 : 0 })
            note(t("Moves over the image measure by themselves. Hold 1 for height, 2 for width. Click to keep. ⌥S / ⌥D: guide lines."))
        case .arrow:
            add(t("Thickness"), slider(1, 14, target.lineWidth) { $0.lineWidth = $1 })
            add(t("Head"), segmented([t("Filled"), t("Hollow"), t("Thin"), t("Double")], target.arrowHead.rawValue) { $0.arrowHead = ArrowHead(rawValue: $1) ?? .normal })
            add(t("Body"), segmented([t("Tapered"), t("Uniform")], target.tapered ? 0 : 1) { $0.tapered = $1 == 0 })
            add(t("Look"), sketchControl(target))
            note(t("Drag the middle handle to curve it"))
        case .text:
            if target.pill { add(t("Text color"), colorRow(target.textColor, allowAuto: true) { $0.textColor = $1 }) }
            add(t("Size"), slider(8, 96, target.fontSize) { $0.fontSize = $1.rounded() })
            add(t("Font"), fontPopup(target))
            add(t("Style"), segmented([t("Label"), t("Plain")], target.pill ? 0 : 1) { $0.pill = $1 == 0 })
        case .blur:
            add(t("Mode"), modePopup(target.blurMode))
            if target.blurMode == .blur || target.blurMode == .blurText {
                add(t("Strength"), slider(1, 9, CGFloat(target.level)) { $0.level = Int($1.rounded()) })
            }
        case .counter:
            add(t("Value"), counterValue(canvas?.selectedAnnotation?.counterText ?? canvas?.nextCounterText ?? "1"))
            add(t("Text color"), colorRow(target.textColor, allowAuto: true) { $0.textColor = $1 })
            add(t("Size"), slider(12, 48, target.fontSize) { $0.fontSize = $1.rounded() })
            note(t("Double-click a counter to type its value, e.g. 1.2 or A3"))
            note(t("Drag the handle beside the bubble to rotate its pointer"))
        case .spotlight:
            add(t("Darkness"), slider(1, 9, CGFloat(target.level)) { $0.level = Int($1.rounded()) })
            add(t("Shape"), segmented([t("Rectangle"), t("Oval")], target.oval ? 1 : 0) { $0.oval = $1 == 1 })
            add(t("Border"), slider(1, 14, target.lineWidth) { $0.lineWidth = $1 })
            note(t("Keys 1–9 change the darkness"))
        case .magnifier:
            add(t("Zoom"), segmented(["2×", "3×", "4×"], max(0, min(2, target.level - 2))) { $0.level = $1 + 2 })
            add(t("Thickness"), slider(1, 14, target.lineWidth) { $0.lineWidth = $1 })
        case .image:
            add(t("Opacity"), slider(1, 10, CGFloat(target.level)) { $0.level = Int($1.rounded()) })
            note(t("Drag to move, use the handles to resize. Keys 1–9 set the opacity."))
        case .highlight:
            add(t("Style"), segmented([t("Marker"), t("Box")], target.marker ? 0 : 1) { $0.marker = $1 == 0 })
            if target.marker {
                add(t("Thickness"), slider(1, 10, target.lineWidth) { $0.lineWidth = $1 })
                add(t("Ends"), segmented([t("Round"), t("Flat")], target.rounded ? 0 : 1) { $0.rounded = $1 == 0 })
            }
        case .select, .crop:
            break
        case .editText:
            note(t("Click any text in the picture to retype it. The new text copies the original typeface, size and colour. Esc cancels."))
        }
        if stack.arrangedSubviews.isEmpty { isHidden = true }
    }

    private func add(_ title: String, _ control: NSView) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = Brand.textMuted
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let row = NSStackView(views: [label, control])
        row.spacing = 6
        row.alignment = .centerY
        stack.addArrangedSubview(row)
    }

    private func note(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = Brand.textFaint
        label.preferredMaxLayoutWidth = 250
        stack.addArrangedSubview(label)
    }

    private func bind(_ run: @escaping (NSControl) -> Void) -> ControlAction {
        let a = ControlAction(run)
        actions.append(a)
        return a
    }

    // MARK: Controls

    /// Swatches plus a colour well. With `allowAuto`, a first "Auto" button means "pick black or white for me" (apply gets nil).
    private func colorRow(_ current: NSColor?, allowAuto: Bool = false, apply: @escaping (inout Annotation, NSColor?) -> Void) -> NSView {
        var views: [NSView] = []
        if allowAuto {
            let auto = NSButton(title: t("Auto"), target: nil, action: nil)
            auto.bezelStyle = .recessed
            auto.controlSize = .small
            auto.state = current == nil ? .on : .off
            auto.setButtonType(.pushOnPushOff)
            let action = bind { [weak self] _ in
                self?.canvas?.updateStyle { apply(&$0, nil) }
                DispatchQueue.main.async { self?.reload() }
            }
            auto.target = action
            auto.action = #selector(ControlAction.fire(_:))
            views.append(auto)
        }
        for color in Self.swatches {
            let isCurrent = current.map { Self.isSame(color, $0) } ?? false
            let button = NSButton(image: Self.swatchImage(color, selected: isCurrent), target: nil, action: nil)
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.setButtonType(.momentaryChange)
            let action = bind { [weak self] _ in
                self?.canvas?.updateStyle { apply(&$0, color) }
                DispatchQueue.main.async { self?.reload() }
            }
            button.target = action
            button.action = #selector(ControlAction.fire(_:))
            views.append(button)
        }
        let well = NSColorWell(style: .minimal)
        well.color = current ?? .gray
        well.widthAnchor.constraint(equalToConstant: 24).isActive = true
        well.heightAnchor.constraint(equalToConstant: 20).isActive = true
        let wellAction = bind { [weak self] sender in
            guard let well = sender as? NSColorWell else { return }
            self?.canvas?.updateStyle { apply(&$0, well.color) }   // applies while the colour panel is open: no need to close it first
        }
        well.target = wellAction
        well.action = #selector(ControlAction.fire(_:))
        views.append(well)
        let row = NSStackView(views: views)
        row.spacing = 2
        return row
    }

    private static func isSame(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return false }
        return abs(x.redComponent - y.redComponent) + abs(x.greenComponent - y.greenComponent) + abs(x.blueComponent - y.blueComponent) < 0.04
    }

    private static func swatchImage(_ color: NSColor, selected: Bool) -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let dot = rect.insetBy(dx: 3, dy: 3)
            color.setFill()
            NSBezierPath(ovalIn: dot).fill()
            NSColor.separatorColor.setStroke()
            let rim = NSBezierPath(ovalIn: dot)
            rim.lineWidth = 0.5
            rim.stroke()
            if selected {
                NSColor.controlAccentColor.setStroke()
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
                ring.lineWidth = 1.5
                ring.stroke()
            }
            return true
        }
    }

    /// An editable counter value (any text: 1.1, 3.6, A2) with − / + that step its last number.
    private func counterValue(_ text: String) -> NSView {
        let field = NSTextField(string: text)
        field.controlSize = .small
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        field.alignment = .center
        field.widthAnchor.constraint(equalToConstant: 92).isActive = true
        let commit = bind { [weak self] sender in
            guard let f = sender as? NSTextField else { return }
            let value = f.stringValue.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { self?.canvas?.setCounterText(value) }
        }
        field.target = commit
        field.action = #selector(ControlAction.fire(_:))
        let stepper = NSStepper()
        stepper.controlSize = .small
        stepper.minValue = -1_000_000; stepper.maxValue = 1_000_000; stepper.integerValue = 0
        let step = bind { [weak self, weak field] sender in
            guard let s = sender as? NSStepper, let field else { return }
            let delta = s.integerValue
            s.integerValue = 0
            let next = CounterText.step(field.stringValue, by: delta)
            field.stringValue = next
            self?.canvas?.setCounterText(next)
        }
        stepper.target = step
        stepper.action = #selector(ControlAction.fire(_:))
        return NSStackView(views: [field, stepper])
    }

    private static let fontChoices: [(title: String, name: String?)] = [
        ("System", nil), ("Helvetica Neue", "Helvetica Neue"), ("Arial", "Arial"), ("Georgia", "Georgia"), ("Times New Roman", "Times New Roman"),
        ("Menlo", "Menlo"), ("Courier New", "Courier New"), ("Verdana", "Verdana"), ("Trebuchet MS", "Trebuchet MS"),
        ("Thonburi", "Thonburi"), ("Sukhumvit Set", "Sukhumvit Set"),
    ]

    private func fontPopup(_ target: Annotation) -> NSView {
        let choices = Self.fontChoices.filter { $0.name == nil || NSFont(name: $0.name!, size: 12) != nil }
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.addItems(withTitles: choices.map(\.title))
        popup.selectItem(at: choices.firstIndex { $0.name == target.fontName } ?? 0)
        let pick = bind { [weak self] sender in
            let i = (sender as? NSPopUpButton)?.indexOfSelectedItem ?? 0
            self?.canvas?.updateStyle { $0.fontName = choices[i].name }
        }
        popup.target = pick
        popup.action = #selector(ControlAction.fire(_:))
        let bold = NSButton(checkboxWithTitle: t("Bold"), target: nil, action: nil)
        bold.controlSize = .small
        bold.state = target.fontBold ? .on : .off
        let toggle = bind { [weak self] sender in
            self?.canvas?.updateStyle { $0.fontBold = (sender as? NSButton)?.state == .on }
        }
        bold.target = toggle
        bold.action = #selector(ControlAction.fire(_:))
        return NSStackView(views: [popup, bold])
    }

    private func sketchControl(_ target: Annotation) -> NSView {
        segmented([t("Clean"), t("Hand-drawn")], target.sketchy ? 1 : 0) { $0.sketchy = $1 == 1 }
    }

    private func slider(_ lo: CGFloat, _ hi: CGFloat, _ value: CGFloat, _ apply: @escaping (inout Annotation, CGFloat) -> Void) -> NSView {
        let s = NSSlider(value: Double(value), minValue: Double(lo), maxValue: Double(hi), target: nil, action: nil)
        s.controlSize = .small
        s.isContinuous = true
        s.trackFillColor = Brand.accent
        s.widthAnchor.constraint(equalToConstant: 168).isActive = true
        let action = bind { [weak self] sender in
            let v = CGFloat((sender as? NSSlider)?.doubleValue ?? 0)
            self?.canvas?.updateStyle { apply(&$0, v) }
        }
        s.target = action
        s.action = #selector(ControlAction.fire(_:))
        return s
    }

    private func segmented(_ titles: [String], _ selected: Int, _ apply: @escaping (inout Annotation, Int) -> Void) -> NSView {
        let bar = ChoiceBar(titles: titles, selected: selected)
        bar.onChange = { [weak self] i in
            self?.canvas?.updateStyle { apply(&$0, i) }
            DispatchQueue.main.async { self?.reload() }
        }
        return bar
    }

    private func stepper(_ lo: Int, _ hi: Int, _ value: Int, _ apply: @escaping (inout Annotation, Int) -> Void) -> NSView {
        let label = NSTextField(labelWithString: String(value))
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 30).isActive = true
        let s = NSStepper()
        s.minValue = Double(lo); s.maxValue = Double(hi); s.integerValue = value
        s.controlSize = .small
        let action = bind { [weak self] sender in
            let v = (sender as? NSStepper)?.integerValue ?? 0
            label.stringValue = String(v)
            self?.canvas?.updateStyle { apply(&$0, v) }
        }
        s.target = action
        s.action = #selector(ControlAction.fire(_:))
        let row = NSStackView(views: [label, s])
        row.spacing = 4
        return row
    }

    private func modePopup(_ current: BlurMode) -> NSView {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.controlSize = .small
        p.addItems(withTitles: [t("Blur"), t("Blur text"), t("Erase"), t("Erase text")])
        p.selectItem(at: current.rawValue)
        let action = bind { [weak self] sender in
            let i = (sender as? NSPopUpButton)?.indexOfSelectedItem ?? 0
            self?.canvas?.updateStyle { $0.blurMode = BlurMode(rawValue: i) ?? .blur }
            DispatchQueue.main.async { self?.reload() }
        }
        p.target = action
        p.action = #selector(ControlAction.fire(_:))
        return p
    }
}

/// Lets a control call a closure (a control's `target` is unowned, so the panel keeps these alive).
@MainActor
final class ControlAction: NSObject {
    private let run: (NSControl) -> Void
    init(_ run: @escaping (NSControl) -> Void) { self.run = run }
    @objc func fire(_ sender: NSControl) { run(sender) }
}
