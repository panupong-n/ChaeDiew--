import AppKit

/// A toolbar button in the brand look: flat, 30 pt square, a soft highlight on hover, the accent when it is the active tool.
/// It never takes keyboard focus, so the canvas keeps receiving the single-key shortcuts after a click.
@MainActor
final class ChromeButton: NSButton {
    var isActive = false { didSet { restyle() } }
    override var isEnabled: Bool { didSet { restyle() } }
    private var isHovered = false { didSet { restyle() } }
    private var caption: String
    private var textWidth: NSLayoutConstraint?

    init(symbol: String?, title: String = "", tip: String, trailingSymbol: String? = nil, target: AnyObject?, action: Selector?) {
        caption = title
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryChange)
        refusesFirstResponder = true
        toolTip = tip
        setAccessibilityLabel(title.isEmpty ? tip : title)
        wantsLayer = true
        layer?.cornerRadius = 7
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        }
        imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        if symbol == nil {  // a text-only button (size, zoom) is exactly as wide as its text, and never wraps
            cell?.wraps = false
            cell?.lineBreakMode = .byClipping
            let c = widthAnchor.constraint(equalToConstant: 30)
            c.isActive = true
            textWidth = c
        }
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setCaption(_ text: String) { caption = text; restyle() }

    private func restyle() {
        let tint: NSColor = !isEnabled ? Brand.textFaint.withAlphaComponent(0.55) : isActive ? Brand.accent : isHovered ? Brand.text : Brand.textMuted
        contentTintColor = tint
        if !caption.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: tint]
            attributedTitle = NSAttributedString(string: caption, attributes: attrs)
            textWidth?.constant = max(30, ceil((caption as NSString).size(withAttributes: attrs).width) + 18)
        }
        layer?.backgroundColor = (isActive ? Brand.accentSoft : (isHovered && isEnabled ? Brand.inkHover : .clear)).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); isHovered = false }
}

/// Segmented choice in the brand look (the system control cannot carry the accent with readable text on it).
@MainActor
final class ChoiceBar: NSView {
    private var chips: [Chip] = []
    var onChange: ((Int) -> Void)?
    private(set) var selected: Int

    private final class Chip: NSButton {
        var chosen = false { didSet { restyle() } }
        private var hovered = false { didSet { restyle() } }
        private let label: String

        init(_ label: String) {
            self.label = label
            super.init(frame: .zero)
            isBordered = false
            setButtonType(.momentaryChange)
            refusesFirstResponder = true
            wantsLayer = true
            layer?.cornerRadius = 6
            setAccessibilityLabel(label)
            restyle()
        }

        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

        func restyle() {
            let color: NSColor = chosen ? Brand.ink : hovered ? Brand.text : Brand.textMuted
            attributedTitle = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: chosen ? .semibold : .medium), .foregroundColor: color])
            layer?.backgroundColor = (chosen ? Brand.accent : (hovered ? Brand.inkHover : .clear)).cgColor
        }

        override var intrinsicContentSize: NSSize {
            let w = (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width
            return NSSize(width: ceil(w) + 18, height: 24)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
        }
        override func mouseEntered(with event: NSEvent) { hovered = true }
        override func mouseExited(with event: NSEvent) { hovered = false }
    }

    init(titles: [String], selected: Int) {
        self.selected = selected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Brand.ink.cgColor
        layer?.cornerRadius = 8
        layer?.borderColor = Brand.line.cgColor
        layer?.borderWidth = 1
        let stack = NSStackView()
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (i, title) in titles.enumerated() {
            let chip = Chip(title)
            chip.chosen = i == selected
            chip.target = self
            chip.action = #selector(chipClicked(_:))
            chip.tag = i
            chips.append(chip)
            stack.addArrangedSubview(chip)
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityRole(.radioGroup)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func chipClicked(_ sender: NSButton) {
        selected = sender.tag
        for (i, chip) in chips.enumerated() { chip.chosen = i == selected }
        onChange?(selected)
    }
}

/// A hairline separating groups in the toolbar.
func chromeDivider() -> NSView {
    let v = NSView()
    v.wantsLayer = true
    v.layer?.backgroundColor = Brand.line.cgColor
    v.translatesAutoresizingMaskIntoConstraints = false
    v.widthAnchor.constraint(equalToConstant: 1).isActive = true
    v.heightAnchor.constraint(equalToConstant: 18).isActive = true
    return v
}
