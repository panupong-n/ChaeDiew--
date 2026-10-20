import AppKit

/// The backdrop editor: type (solid / gradient / image), colours, gradient style, padding, shadow, rounded corners and a preset grid.
/// Every change is applied to the editor live.
@MainActor
final class BackdropPanel: DraggableEffectView {
    var spec: BackdropSpec
    var onChange: ((BackdropSpec) -> Void)?
    var onDone: (() -> Void)?
    var onRemove: (() -> Void)?

    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private var actions: [ControlAction] = []
    private var heightConstraint: NSLayoutConstraint?

    init(spec: BackdropSpec) {
        self.spec = spec
        super.init(frame: .zero)
        applyPanelSkin()
        translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 336),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor), stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor), stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func changed() { onChange?(spec) }

    // MARK: Building

    func rebuild() {
        actions.removeAll()
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }

        let title = NSTextField(labelWithString: t("Backdrop"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = Brand.text
        stack.addArrangedSubview(title)

        // Type
        let kinds: [BackdropSpec.Kind] = [.solid, .gradient, .image]
        stack.addArrangedSubview(segmented([t("Solid"), t("Gradient"), t("Image")], kinds.firstIndex(of: spec.kind) ?? 1) { [weak self] i in
            guard let self else { return }
            self.spec.kind = kinds[i]
            if kinds[i] == .solid { self.spec.colors = [self.spec.colors[0], self.spec.colors[0], self.spec.colors[0], self.spec.colors[0]] }
            self.changed()
            self.rebuild()
        })

        // Colours
        switch spec.kind {
        case .solid:
            row(t("Color"), wells(count: 1))
        case .gradient:
            row(t("Style"), popup([t("Linear"), t("Radial"), t("Mesh gradient")], BackdropSpec.GradientStyle.allCases.firstIndex(of: spec.gradient) ?? 0) { [weak self] i in
                guard let self else { return }
                self.spec.gradient = BackdropSpec.GradientStyle.allCases[i]
                self.changed()
                self.rebuild()
            })
            row(t("Colors"), wells(count: spec.gradient == .mesh ? 4 : 2))
            if spec.gradient == .linear {
                row(t("Angle"), slider(0, 360, spec.angle) { [weak self] v in self?.spec.angle = v; self?.changed() })
            }
        case .image:
            let name = spec.imagePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? t("No image chosen")
            let choose = button(t("Choose image…")) { [weak self] in self?.chooseImage() }
            let label = NSTextField(labelWithString: name)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingMiddle
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 150).isActive = true
            row(t("Picture"), NSStackView(views: [choose, label]))
        case .none:
            break
        }
        if spec.kind != .image {
            let swap = iconButton("arrow.left.arrow.right", t("Swap colors")) { [weak self] in self?.spec.swapColors(); self?.changed(); self?.rebuild() }
            let dice = iconButton("dice", t("Random colors")) { [weak self] in self?.spec.randomizeColors(); self?.changed(); self?.rebuild() }
            row("", NSStackView(views: [swap, dice]))
        }

        // Metrics
        row(t("Padding"), slider(0, 200, spec.padding) { [weak self] v in self?.spec.padding = v.rounded(); self?.changed() })
        row(t("Shadow"), slider(0, 100, spec.shadow * 100) { [weak self] v in self?.spec.shadow = v / 100; self?.changed() })
        row(t("Shadow blur"), slider(0, 80, spec.shadowBlur) { [weak self] v in self?.spec.shadowBlur = v; self?.changed() })
        row(t("Outer radius"), slider(0, 80, spec.outerRadius) { [weak self] v in self?.spec.outerRadius = v.rounded(); self?.changed() })
        row(t("Inner radius"), slider(0, 40, spec.innerRadius) { [weak self] v in self?.spec.innerRadius = v.rounded(); self?.changed() })

        // Presets
        let heading = NSTextField(labelWithString: t("Presets"))
        heading.font = .systemFont(ofSize: 11, weight: .medium)
        heading.textColor = Brand.textMuted
        stack.addArrangedSubview(heading)
        let perRow = 6
        var rows: [NSStackView] = []
        for (i, preset) in BackdropSpec.presets.enumerated() {
            if i % perRow == 0 { let r = NSStackView(); r.spacing = 6; rows.append(r) }
            let b = NSButton(image: Backdrop.thumbnail(preset.spec, size: NSSize(width: 40, height: 28)), target: nil, action: nil)
            b.isBordered = false
            b.imagePosition = .imageOnly
            b.toolTip = t(preset.name)
            let action = bind { [weak self] _ in
                guard let self else { return }
                var next = preset.spec
                next.padding = self.spec.padding; next.shadow = self.spec.shadow; next.shadowBlur = self.spec.shadowBlur
                next.outerRadius = self.spec.outerRadius; next.innerRadius = self.spec.innerRadius
                self.spec = next
                self.changed()
                self.rebuild()
            }
            b.target = action
            b.action = #selector(ControlAction.fire(_:))
            rows[rows.count - 1].addArrangedSubview(b)
        }
        rows.forEach { stack.addArrangedSubview($0) }

        // Buttons
        let remove = button(t("Remove")) { [weak self] in self?.onRemove?() }
        let done = button(t("Done")) { [weak self] in self?.onDone?() }
        done.keyEquivalent = "\r"
        done.bezelColor = Brand.accent
        done.attributedTitle = NSAttributedString(string: t("Done"), attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: Brand.ink])
        let buttons = NSStackView(views: [remove, done])
        buttons.spacing = 8
        stack.addArrangedSubview(buttons)

        layoutSubtreeIfNeeded()
        let wanted = min(560, stack.fittingSize.height)
        if let heightConstraint { heightConstraint.constant = wanted } else {
            let c = heightAnchor.constraint(equalToConstant: wanted)
            c.priority = .init(750)
            c.isActive = true
            heightConstraint = c
        }
    }

    // MARK: Controls

    private func bind(_ run: @escaping (NSControl) -> Void) -> ControlAction {
        let a = ControlAction(run)
        actions.append(a)
        return a
    }

    private func row(_ title: String, _ control: NSView) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = Brand.textMuted
        label.widthAnchor.constraint(equalToConstant: 76).isActive = true
        let r = NSStackView(views: [label, control])
        r.spacing = 6
        r.alignment = .centerY
        stack.addArrangedSubview(r)
    }

    private func slider(_ lo: Double, _ hi: Double, _ value: Double, _ apply: @escaping (Double) -> Void) -> NSView {
        let s = NSSlider(value: value, minValue: lo, maxValue: hi, target: nil, action: nil)
        s.controlSize = .small
        s.isContinuous = true
        s.trackFillColor = Brand.accent
        s.widthAnchor.constraint(equalToConstant: 170).isActive = true
        let valueLabel = NSTextField(labelWithString: String(Int(value.rounded())))
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        valueLabel.textColor = Brand.textFaint
        valueLabel.widthAnchor.constraint(equalToConstant: 30).isActive = true
        let action = bind { sender in
            let v = (sender as? NSSlider)?.doubleValue ?? 0
            valueLabel.stringValue = String(Int(v.rounded()))
            apply(v)
        }
        s.target = action
        s.action = #selector(ControlAction.fire(_:))
        return NSStackView(views: [s, valueLabel])
    }

    private func segmented(_ titles: [String], _ selected: Int, _ apply: @escaping (Int) -> Void) -> NSView {
        let bar = ChoiceBar(titles: titles, selected: selected)
        bar.onChange = { i in DispatchQueue.main.async { apply(i) } }
        bar.widthAnchor.constraint(equalToConstant: 298).isActive = true
        return bar
    }

    private func popup(_ titles: [String], _ selected: Int, _ apply: @escaping (Int) -> Void) -> NSView {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.controlSize = .small
        p.addItems(withTitles: titles)
        p.selectItem(at: selected)
        let action = bind { sender in
            let i = (sender as? NSPopUpButton)?.indexOfSelectedItem ?? 0
            DispatchQueue.main.async { apply(i) }
        }
        p.target = action
        p.action = #selector(ControlAction.fire(_:))
        return p
    }

    private func iconButton(_ symbol: String, _ tip: String, _ run: @escaping () -> Void) -> ChromeButton {
        let action = bind { _ in run() }
        return ChromeButton(symbol: symbol, tip: tip, target: action, action: #selector(ControlAction.fire(_:)))
    }

    private func button(_ title: String, _ run: @escaping () -> Void) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil)
        b.bezelStyle = .rounded
        b.controlSize = .small
        let action = bind { _ in run() }
        b.target = action
        b.action = #selector(ControlAction.fire(_:))
        return b
    }

    private func wells(count: Int) -> NSView {
        var views: [NSView] = []
        for i in 0..<count {
            let well = NSColorWell(style: .minimal)
            well.color = spec.colors[i].nsColor
            well.widthAnchor.constraint(equalToConstant: 34).isActive = true
            well.heightAnchor.constraint(equalToConstant: 22).isActive = true
            let action = bind { [weak self] sender in
                guard let self, let w = sender as? NSColorWell else { return }
                self.spec.colors[i] = RGBColor(w.color)
                if self.spec.kind == .solid { self.spec.colors = Array(repeating: RGBColor(w.color), count: 4) }
                self.changed()
            }
            well.target = action
            well.action = #selector(ControlAction.fire(_:))
            views.append(well)
        }
        return NSStackView(views: views)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        spec.kind = .image
        spec.imagePath = url.path
        changed()
        rebuild()
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
