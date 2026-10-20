import AppKit

@MainActor
public final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, NSToolbarDelegate {
    public var onClose: ((EditorWindowController) -> Void)?
    public var onNeedsUploadSetup: (() -> Void)?
    /// Asks the capture coordinator for another area capture to join to this image.
    public var onRequestAddCapture: ((EditorWindowController) -> Void)?
    /// Opens a picture dropped onto the window in a new editor.
    public var onOpenImage: ((CGImage, CGFloat) -> Void)?

    let canvas: CanvasView
    private let pixelScale: CGFloat
    private let scroll = NSScrollView()
    private var toolButtons: [ChromeButton] = []
    private var undoButton: ChromeButton!
    private var redoButton: ChromeButton!
    private var toolbarGroups: [NSToolbarItem.Identifier: (label: String, view: NSView, menu: () -> NSMenuItem?)] = [:]
    private var backdrop: BackdropSpec = .none
    var backdropPanel: BackdropPanel?
    private var rootView: NSView?
    private var dragHandle = DragHandle()
    var stylePanel: StylePanel?
    private let readoutSwatch = NSView()
    private let readoutLabel = NSTextField(labelWithString: "")
    private var sizeButton: ChromeButton!
    private var zoomButton: ChromeButton!
    private var backdropMenu: NSMenu?
    private var container: BackdropContainer!
    private let contrastButton = NSButton()
    private var useAPCA = UserDefaults.standard.bool(forKey: "contrastAPCA")

    private static let tools: [(kind: ToolKind, symbol: String, tip: String)] = [
        (.select, "cursorarrow", "Select / move (V)"),
        (.crop, "crop", "Crop (C)"),
        (.rectangle, "rectangle", "Rectangle (R)"),
        (.ellipse, "circle", "Ellipse (O)"),
        (.arrow, "arrow.up.right", "Arrow (A)"),
        (.line, "line.diagonal", "Line (L)"),
        (.freehand, "pencil.tip", "Pen (P)"),
        (.text, "textformat", "Text (T)"),
        (.editText, "character.cursor.ibeam", "Edit text in the picture (E)"),
        (.blur, "square.grid.3x3.fill", "Pixelate – hide sensitive info (B)"),
        (.counter, "1.circle", "Numbered marker (N)"),
        (.highlight, "highlighter", "Highlight (H)"),
        (.spotlight, "circle.lefthalf.filled", "Spotlight (S)"),
        (.ruler, "ruler", "Measure pixels (M)"),
        (.magnifier, "magnifyingglass", "Magnifier (G)"),
    ]

    public init(image: CGImage, pixelScale: CGFloat) {
        self.pixelScale = pixelScale
        self.canvas = CanvasView(image: image, pixelScale: pixelScale)

        let chrome: CGFloat = 0   // the toolbar sits in the title bar, outside the content area
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1400, height: 900)
        let content = NSSize(
            width: min(max(canvas.frame.width, 1260), visible.width * 0.96),
            height: min(canvas.frame.height + chrome, visible.height * 0.9))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: content),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 360)
        super.init(window: window)
        window.delegate = self
        buildInterface(in: window, chrome: chrome)
        canvas.onChange = { [weak self] in self?.refresh() }
        canvas.onEscape = { [weak self] in self?.handleEscape() }
        canvas.onToolShortcut = { [weak self] kind in self?.selectTool(kind) }
        canvas.onHoverColor = { [weak self] color, text in self?.showReadout(color, text: text) }
        canvas.onStyleContextChange = { [weak self] in self?.stylePanel?.reload() }
        canvas.onZoomCommand = { [weak self] command in
            switch command {
            case .toSelection: self?.zoomToSelection()
            case .selectionTopLeft: self?.zoomToCorner(topLeft: true)
            case .selectionBottomRight: self?.zoomToCorner(topLeft: false)
            case .point(let p, let out): self?.zoomAround(p, out: out)
            case .area(let r): self?.zoomToArea(r)
            }
        }
        selectTool(canvas.tool)
        refresh()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeFirstResponder(canvas)
        DispatchQueue.main.async { [weak self] in self?.zoomFitIfLarge() }
    }

    public func addAnnotation(_ annotation: Annotation) { canvas.append(annotation) }
    public func selectAnnotation(_ index: Int?) { canvas.select(index) }
    public func setSelection(_ rect: CGRect?) { canvas.setSelection(rect) }

    // MARK: Layout

    private func symbolImage(_ name: String, _ tip: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: tip) ?? NSImage()
    }

    private func chromeButton(_ symbol: String?, _ tip: String, title: String = "", _ action: Selector) -> ChromeButton {
        ChromeButton(symbol: symbol, title: title, tip: tip, target: self, action: action)
    }

    private func group(_ views: [NSView], spacing: CGFloat = 2) -> NSStackView {
        let g = NSStackView(views: views)
        g.spacing = spacing
        g.alignment = .centerY
        g.translatesAutoresizingMaskIntoConstraints = false
        return g
    }

    private static let idBrand = NSToolbarItem.Identifier("chaediew.brand")
    private static let idActions = NSToolbarItem.Identifier("chaediew.actions")
    private static let idHistory = NSToolbarItem.Identifier("chaediew.history")
    private static let idTools = NSToolbarItem.Identifier("chaediew.tools")
    private static let idExtras = NSToolbarItem.Identifier("chaediew.extras")
    private static let idReadout = NSToolbarItem.Identifier("chaediew.readout")
    private static let idInfo = NSToolbarItem.Identifier("chaediew.info")

    /// One bar in the title bar: logo · file actions · history · every tool · PII/OCR/Image · colour readout · size · zoom.
    /// When the window is too narrow the lowest-priority groups fold into the » menu, so nothing is ever cut off.
    private func buildToolbar(for window: NSWindow) {
        // Brand: the wordmark carries the viewfinder corners, so it works on its own at this size.
        let word = NSImageView(image: Brand.wordmarkOnDark ?? NSImage())
        word.imageScaling = .scaleProportionallyUpOrDown
        word.translatesAutoresizingMaskIntoConstraints = false
        let aspect = (Brand.wordmarkOnDark?.size.width ?? 4) / max(1, Brand.wordmarkOnDark?.size.height ?? 1)
        word.heightAnchor.constraint(equalToConstant: 17).isActive = true
        word.widthAnchor.constraint(equalToConstant: 17 * aspect).isActive = true
        word.setAccessibilityLabel("Tenix-ChaeDiew")
        let brand = group([word, chromeDivider()], spacing: 12)
        brand.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 8)

        // File actions
        let copy = chromeButton("doc.on.doc", t("Copy image") + "  ⇧⌘C", #selector(copyImage))
        let save = chromeButton("square.and.arrow.down", t("Save") + "  ⌘S", #selector(saveImage))
        let upload = chromeButton("icloud.and.arrow.up", t("Upload") + "  ⌘E", #selector(uploadImage))
        let pin = chromeButton("pin", t("Pin") + "  ⌘P", #selector(pinImage))
        dragHandle.provider = { [weak self] in self?.writeTemporaryFile() }
        dragHandle.setTip(t("Drag this into another app"))
        let actions = group([copy, save, upload, pin, dragHandle, chromeDivider()])

        // History
        undoButton = chromeButton("arrow.uturn.backward", t("Undo") + "  ⌘Z", #selector(undoAnnotation))
        redoButton = chromeButton("arrow.uturn.forward", t("Redo") + "  ⇧⌘Z", #selector(redoAnnotation))
        let history = group([undoButton, redoButton, chromeDivider()])

        // Tools
        toolButtons = Self.tools.enumerated().map { i, tool in
            let b = chromeButton(tool.symbol, t(tool.tip), #selector(toolButtonClicked(_:)))
            b.tag = i
            return b
        }
        let tools = group(toolButtons + [chromeDivider()])

        // PII / OCR / Image
        let pii = chromeButton("eye.slash", t("Hide PII") + "  ⇧⌘H", #selector(hidePII))
        let ocr = chromeButton("text.viewfinder", t("OCR") + "  ⇧⌘T", #selector(runOCR))
        let imageButton = chromeButton("photo.on.rectangle", t("Add a capture, paste a picture, resize, backdrop…"), #selector(showImageMenu(_:)))
        let extras = group([pii, ocr, imageButton])

        // Readouts
        readoutSwatch.wantsLayer = true
        readoutSwatch.layer?.cornerRadius = 4
        readoutSwatch.layer?.borderWidth = 1
        readoutSwatch.layer?.borderColor = Brand.line.cgColor
        readoutSwatch.translatesAutoresizingMaskIntoConstraints = false
        readoutSwatch.widthAnchor.constraint(equalToConstant: 14).isActive = true
        readoutSwatch.heightAnchor.constraint(equalToConstant: 14).isActive = true
        readoutLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        readoutLabel.textColor = Brand.textMuted
        readoutLabel.toolTip = t("Colour under the pointer. Tab copies it, Shift+Tab copies the darkest nearby pixel.")
        readoutLabel.stringValue = "—"
        contrastButton.isBordered = false
        contrastButton.refusesFirstResponder = true
        contrastButton.target = self
        contrastButton.action = #selector(toggleContrastMode)
        contrastButton.toolTip = t("Contrast of the text next to the pointer against the colour under it. Click: WCAG ↔ APCA.")
        contrastButton.isHidden = true
        readoutSwatch.isHidden = true
        let readout = group([readoutSwatch, readoutLabel, contrastButton, chromeDivider()], spacing: 8)
        readout.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 0)

        sizeButton = ChromeButton(symbol: nil, title: " ", tip: t("Image size — click to resize"), target: self, action: #selector(showSizeMenu(_:)))
        zoomButton = ChromeButton(symbol: nil, title: " ", tip: t("Zoom — click for options"), target: self, action: #selector(showZoomMenu(_:)))
        let info = group([sizeButton, zoomButton])

        func menuItem(_ title: String, _ build: @escaping (NSMenu) -> Void) -> () -> NSMenuItem? {
            { let m = NSMenuItem(title: title, action: nil, keyEquivalent: ""); let sub = NSMenu(); build(sub); m.submenu = sub; return m }
        }
        toolbarGroups = [
            Self.idBrand: ("Tenix-ChaeDiew", brand, { nil }),
            Self.idActions: (t("File"), actions, menuItem(t("File")) { [self] menu in
                for (title, action) in [(t("Copy image"), #selector(copyImage)), (t("Save"), #selector(saveImage)), (t("Upload"), #selector(uploadImage)), (t("Pin"), #selector(pinImage))] {
                    let m = NSMenuItem(title: title, action: action, keyEquivalent: ""); m.target = self; menu.addItem(m)
                }
            }),
            Self.idHistory: (t("Undo"), history, menuItem(t("Edit")) { [self] menu in
                for (title, action) in [(t("Undo"), #selector(undoAnnotation)), (t("Redo"), #selector(redoAnnotation))] {
                    let m = NSMenuItem(title: title, action: action, keyEquivalent: ""); m.target = self; menu.addItem(m)
                }
            }),
            Self.idTools: (t("Draw"), tools, menuItem(t("Draw")) { [self] menu in
                for entry in Self.toolMenuEntries {
                    let m = NSMenuItem(title: entry.title, action: #selector(selectToolFromMenu(_:)), keyEquivalent: ""); m.tag = entry.tag; m.target = self; menu.addItem(m)
                }
            }),
            Self.idExtras: (t("Image"), extras, menuItem(t("Image")) { [self] menu in
                for (title, action) in [(t("Hide PII"), #selector(hidePII)), (t("OCR"), #selector(runOCR)), (t("Add capture"), #selector(addCapture)), (t("Paste image"), #selector(pasteImage)),
                                        (t("Merge marks into image"), #selector(rasterize)), (t("Backdrop…"), #selector(showBackdropPanel)), (t("Before / after GIF"), #selector(exportBeforeAfterGIF))] {
                    let m = NSMenuItem(title: title, action: action, keyEquivalent: ""); m.target = self; menu.addItem(m)
                }
            }),
            Self.idReadout: (t("Colour"), readout, { nil }),
            Self.idInfo: (t("Zoom"), info, { nil }),
        ]
        let toolbar = NSToolbar(identifier: "ChaeDiewEditor")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.idBrand, Self.idActions, Self.idHistory, Self.idTools, Self.idExtras, .flexibleSpace, Self.idReadout, Self.idInfo]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let g = toolbarGroups[id] else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = g.label
        item.view = g.view
        item.menuFormRepresentation = g.menu()
        // Narrow window: the readout and zoom go first, then history and extras; tools and file actions stay longest.
        switch id {
        case Self.idReadout: item.visibilityPriority = .low
        case Self.idInfo, Self.idHistory, Self.idExtras: item.visibilityPriority = .standard
        default: item.visibilityPriority = .high
        }
        return item
    }

    @objc private func toolButtonClicked(_ sender: NSButton) { selectTool(Self.tools[sender.tag].kind) }

    @objc private func showImageMenu(_ sender: NSButton) {
        let menu = buildImageMenu()
        menu.removeItem(at: 0)  // the pull-down's own title row is not needed in a pop-up
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    private func buildInterface(in window: NSWindow, chrome: CGFloat) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Brand.ink
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        buildToolbar(for: window)

        let root = DropView()
        rootView = root
        root.onDropImage = { [weak self] image, scale in self?.onOpenImage?(image, scale) }
        window.contentView = root

        scroll.contentView = CenteringClipView()
        container = BackdropContainer(canvas: canvas)
        scroll.documentView = container
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.1
        scroll.maxMagnification = 16
        scroll.backgroundColor = NSColor(srgbRed: 0.063, green: 0.071, blue: 0.082, alpha: 1)  // a step darker than the chrome, so the picture leads
        scroll.drawsBackground = true
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveMagnifyNotification, object: scroll, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.updateInfo() } }

        root.addSubview(scroll)
        let panel = StylePanel(canvas: canvas)
        stylePanel = panel
        root.addSubview(panel)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            panel.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 14),
            panel.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -22),
        ])
        panel.topConstraint = root.constraints.first { ($0.firstItem === panel) && $0.firstAttribute == .top }
        panel.trailingConstraint = root.constraints.first { ($0.firstItem === panel) && $0.firstAttribute == .trailing }
    }

    /// Image ▾ : things that change the picture itself.
    private func buildImageMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: t("Image"), action: nil, keyEquivalent: "")  // the pull-down's own title
        func item(_ title: String, _ action: Selector, key: String = "", mods: NSEvent.ModifierFlags = []) -> NSMenuItem {
            let m = NSMenuItem(title: title, action: action, keyEquivalent: key)
            m.keyEquivalentModifierMask = mods
            m.target = self
            return m
        }
        menu.addItem(item(t("Add capture"), #selector(addCapture)))
        menu.addItem(item(t("Paste image"), #selector(pasteImage)))
        menu.addItem(item(t("Merge marks into image"), #selector(rasterize)))
        menu.addItem(.separator())
        let resize = NSMenuItem(title: t("Resize"), action: nil, keyEquivalent: "")
        resize.submenu = resizeMenu()
        menu.addItem(resize)
        menu.addItem(item(t("Backdrop…"), #selector(showBackdropPanel)))
        menu.addItem(item(t("Remove Backdrop"), #selector(removeBackdrop)))
        menu.addItem(item(t("Before / after GIF"), #selector(exportBeforeAfterGIF)))
        return menu
    }

    private func resizeMenu() -> NSMenu {
        let sub = NSMenu()
        for percent in [25, 50, 75, 125, 150, 200] {
            let m = NSMenuItem(title: "\(percent)%", action: #selector(resizeFromMenu(_:)), keyEquivalent: "")
            m.target = self
            m.tag = percent
            sub.addItem(m)
        }
        return sub
    }

    @objc private func resizeFromMenu(_ sender: NSMenuItem) { canvas.resize(by: CGFloat(sender.tag) / 100) }

    /// Image ▸ Backdrop…: opens the live backdrop editor (starting from the last one you used).
    @objc public func showBackdropPanel() {
        if backdropPanel != nil { return }
        if !backdrop.isOn { applyBackdrop(BackdropSpec.loadSaved()) }
        let panel = BackdropPanel(spec: backdrop)
        panel.onChange = { [weak self] spec in self?.applyBackdrop(spec, fit: false) }
        panel.onDone = { [weak self] in self?.closeBackdropPanel(); self?.zoomFit() }
        panel.onRemove = { [weak self] in self?.removeBackdrop() }
        backdropPanel = panel
        rootView?.addSubview(panel)
        let top = panel.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 12)
        let trailing = panel.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -22)
        NSLayoutConstraint.activate([top, trailing, panel.bottomAnchor.constraint(lessThanOrEqualTo: scroll.bottomAnchor, constant: -12)])
        panel.topConstraint = top
        panel.trailingConstraint = trailing
        stylePanel?.isHidden = true
    }

    private func closeBackdropPanel() {
        backdropPanel?.removeFromSuperview()
        backdropPanel = nil
        stylePanel?.reload()
    }

    @objc public func removeBackdrop() {
        closeBackdropPanel()
        applyBackdrop(.none)
    }

    public func setBackdrop(_ style: BackdropStyle) { applyBackdrop(style.spec) }

    private func applyBackdrop(_ spec: BackdropSpec, fit: Bool = true) {
        backdrop = spec
        if spec.isOn { spec.save() }
        container.spec = backdrop
        refresh()
        if fit { zoomFit() }
    }

    @objc private func showSizeMenu(_ sender: NSButton) {
        let menu = resizeMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func showZoomMenu(_ sender: NSButton) {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, key: String) {
            let m = NSMenuItem(title: title, action: action, keyEquivalent: key)
            m.target = self
            menu.addItem(m)
        }
        item(t("Fit to Window"), #selector(zoomFit), key: "1")
        item(t("Actual Size"), #selector(zoomActual), key: "0")
        item(t("Zoom In"), #selector(zoomIn), key: "+")
        item(t("Zoom Out"), #selector(zoomOut), key: "-")
        item(t("Zoom to Selection"), #selector(zoomToSelection), key: "2")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    private var lastReadout: (NSColor?, NSColor?) = (nil, nil)

    @objc private func toggleContrastMode() {
        useAPCA.toggle()
        UserDefaults.standard.set(useAPCA, forKey: "contrastAPCA")
        showReadout(lastReadout.0, text: lastReadout.1)
    }

    private func showReadout(_ color: NSColor?, text: NSColor? = nil) {
        lastReadout = (color, text)
        guard let c = color?.usingColorSpace(.sRGB) else {
            readoutSwatch.isHidden = true
            contrastButton.isHidden = true
            readoutLabel.stringValue = "—"
            return
        }
        // Contrast: text colour (darkest nearby pixel) on the colour under the pointer.
        func rgb(_ n: NSColor) -> (r: Int, g: Int, b: Int) {
            let s = n.usingColorSpace(.sRGB) ?? n
            return (Int((s.redComponent * 255).rounded()), Int((s.greenComponent * 255).rounded()), Int((s.blueComponent * 255).rounded()))
        }
        // Only where there is something text-like next to the pointer (a clear step in lightness): flat areas show nothing.
        if let tc = text?.usingColorSpace(.sRGB), ColorMath.wcagRatio(rgb(tc), rgb(c)) >= 1.6 {
            if useAPCA {
                setContrast(String(format: "Lc %.0f", abs(ColorMath.apca(text: rgb(tc), background: rgb(c)))), color: Brand.textMuted)
            } else {
                let ratio = ColorMath.wcagRatio(rgb(tc), rgb(c))
                let grade = ratio >= 7 ? "AAA" : ratio >= 4.5 ? "AA" : ratio >= 3 ? t("AA large text") : t("Low")
                setContrast(String(format: "%.1f:1 %@", ratio, grade), color: ratio >= 4.5 ? Brand.positive : ratio >= 3 ? Brand.textMuted : Brand.caution)
            }
            contrastButton.isHidden = false
        } else {
            contrastButton.isHidden = true
        }
        readoutSwatch.isHidden = false
        readoutSwatch.layer?.backgroundColor = c.cgColor
        readoutLabel.stringValue = ColorFormats.string(
            r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent), format: Settings.shared.colorFormat)
            + "  " + t("Tab to copy")
    }

    private func setContrast(_ text: String, color: NSColor) {
        contrastButton.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: color])
    }

    private func updateInfo() {
        let s = canvas.state.image
        sizeButton.setCaption("\(s.width)×\(s.height) px")
        zoomButton.setCaption("\(Int((scroll.magnification * 100).rounded()))%")
    }

    private func refresh() {
        let s = canvas.state.image
        window?.title = "Tenix-ChaeDiew — \(s.width) × \(s.height)" + (backdrop.isOn ? " — \(t("Backdrop"))" : "")
        undoButton.isEnabled = canvas.canUndo
        redoButton.isEnabled = canvas.canRedo
        updateInfo()
    }

    // MARK: Tool bar actions

    private func selectTool(_ kind: ToolKind) {
        guard let i = Self.tools.firstIndex(where: { $0.kind == kind }) else { return }
        canvas.tool = kind
        for (n, b) in toolButtons.enumerated() { b.isActive = n == i }
    }


    /// Draw ▸ Hand-drawn Style (⌘R): switches the selected mark, or the active tool, between clean and sketchy outlines.
    @objc public func toggleHandDrawn() {
        guard let target = canvas.styleTarget, [.rectangle, .ellipse, .line, .arrow].contains(target.kind) else {
            return Toast.show(t("Hand-drawn style works on rectangles, ovals, lines and arrows"))
        }
        let on = !target.sketchy
        canvas.updateStyle { $0.sketchy = on }
        stylePanel?.reload()
    }

    @objc public func toggleSnap() {
        Settings.shared.snapToObjects.toggle()
        Toast.show(Settings.shared.snapToObjects ? t("Snap to objects: on") : t("Snap to objects: off"), duration: 1.2)
    }

    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == Selector(("toggleSnap")) { item.state = Settings.shared.snapToObjects ? .on : .off }
        return true
    }

    /// Draw menu entries (tag = index in the tool list).
    @objc public func selectToolFromMenu(_ sender: NSMenuItem) {
        guard Self.tools.indices.contains(sender.tag) else { return }
        selectTool(Self.tools[sender.tag].kind)
    }

    public static var toolMenuEntries: [(title: String, tag: Int)] {
        tools.enumerated().map { (t($0.element.tip), $0.offset) }
    }

    // MARK: Zoom

    @objc public func zoomIn() { scroll.magnification = min(scroll.maxMagnification, scroll.magnification * 1.25); updateInfo() }
    @objc public func zoomOut() { scroll.magnification = max(scroll.minMagnification, scroll.magnification / 1.25); updateInfo() }
    @objc public func zoomActual() { scroll.magnification = 1; updateInfo() }
    @objc public func zoomFit() {
        let avail = scroll.contentSize
        let size = container.frame.size
        guard size.width > 0, size.height > 0 else { return }
        scroll.magnification = max(scroll.minMagnification, min(1, avail.width / size.width, avail.height / size.height))
        updateInfo()
    }
    private func zoomFitIfLarge() { zoomFit() }

    /// ⌘2 – fill the window with the selection.
    @objc public func zoomToSelection() {
        guard let r = canvas.selectionRect else { return Toast.show(t("Select an area first (drag on the image)")) }
        scroll.magnify(toFit: canvas.convert(r, to: container))
        updateInfo()
    }

    private func zoomAround(_ p: CGPoint, out: Bool) {
        let target = out ? max(scroll.minMagnification, scroll.magnification / 2) : min(scroll.maxMagnification, scroll.magnification * 2)
        scroll.setMagnification(target, centeredAt: canvas.convert(p, to: container))
        updateInfo()
    }

    private func zoomToArea(_ r: CGRect) {
        scroll.magnify(toFit: canvas.convert(r, to: container))
        updateInfo()
    }

    /// Q / W – zoom in on the selection's top-left / bottom-right corner for pixel-precise adjusting.
    private func zoomToCorner(topLeft: Bool) {
        guard let r = canvas.selectionRect else { return }
        let corner = canvas.convert(topLeft ? CGPoint(x: r.minX, y: r.minY) : CGPoint(x: r.maxX, y: r.maxY), to: container)
        scroll.setMagnification(max(6, scroll.magnification), centeredAt: corner)
        updateInfo()
    }

    // MARK: Commands (also reachable from the main menu through the responder chain)

    /// Hides this window, lets the user capture another area, and joins it to the image.
    @objc public func addCapture() { onRequestAddCapture?(self) }

    /// Called by the coordinator with the new capture.
    public func appendCapture(_ image: CGImage, scale: CGFloat) {
        canvas.appendImage(image)
        zoomFit()
        present()
        Toast.show(t("Capture added"))
    }

    /// Two-frame GIF that alternates the original and the edited image (saved, and its file copied for pasting into chats).
    @objc public func exportBeforeAfterGIF() {
        guard LicenseManager.shared.require(t("Copying, saving, uploading and printing need a license")) else { return }
        guard let after = finalImage() else { return }
        guard canvas.state.image !== canvas.originalImage || !canvas.state.annotations.isEmpty || backdrop.isOn else {
            return Toast.show(t("Nothing changed yet — edit the image first"))
        }
        let before = Backdrop.apply(to: canvas.originalImage, spec: backdrop, pixelScale: pixelScale)
        guard let data = GIFExport.beforeAfter(before: before, after: after) else { return Toast.show(t("Could not create the GIF")) }
        let url = Settings.shared.saveFolder.appendingPathComponent(Storage.fileName(ext: "gif").replacingOccurrences(of: "Tenix-ChaeDiew", with: "Tenix-ChaeDiew before-after"))
        do {
            try data.write(to: url, options: .atomic)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
            Toast.show("\(t("GIF saved and copied")): \(url.lastPathComponent)", duration: 3)
        } catch { showError(error) }
    }

    /// ⌘C: copies the selected mark if there is one, otherwise the image (⇧⌘C always copies the image).
    @objc public func copyCommand() {
        if window?.firstResponder is NSText { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil); return }
        if canvas.copySelectedMark() { Toast.show(t("Mark copied")); return }
        copyImage()
    }

    /// ⌘V: a copied mark if that is what was copied last, otherwise the clipboard picture.
    @objc public func pasteCommand() {
        if window?.firstResponder is NSText { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil); return }
        if canvas.pasteMark() { return }
        pasteImage()
    }

    /// Pastes the clipboard picture as an overlay; while typing text it pastes text as usual. becomes an overlay; while typing text it pastes text as usual.
    @objc public func pasteImage() {
        if window?.firstResponder is NSText {
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            return
        }
        guard let nsImage = NSImage(pasteboard: .general),
              let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return Toast.show(t("No image on the clipboard")) }
        canvas.addImageOverlay(cg, imageScale: max(1, CGFloat(cg.width) / max(nsImage.size.width, 1)))
    }

    /// Edit ▸ Rasterize: the marks become part of the picture.
    @objc public func rasterize() {
        Toast.show(canvas.rasterize() ? t("Marks merged into the image") : t("Nothing to merge"))
    }

    @objc public func undoAnnotation() { canvas.undo() }
    @objc public func redoAnnotation() { canvas.redo() }

    /// The edited image with the chosen backdrop applied.
    func finalImage() -> CGImage? {
        guard let edited = canvas.exportImage() else { return nil }
        return Backdrop.apply(to: edited, spec: backdrop, pixelScale: pixelScale)
    }

    @objc public func copyImage() {
        guard LicenseManager.shared.require(t("Copying, saving, uploading and printing need a license")) else { return }
        guard var image = finalImage() else { return }
        if let r = canvas.selectionPixelRect, let part = image.cropping(to: r) { image = part }  // copy just the selection
        let size = NSSize(width: CGFloat(image.width) / pixelScale, height: CGFloat(image.height) / pixelScale)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: size)])
        Toast.show(t("Copied to clipboard"))
    }

    @objc public func saveImage() { _ = save(announce: true) }

    @discardableResult
    private func save(announce: Bool) -> URL? {
        guard LicenseManager.shared.require(t("Copying, saving, uploading and printing need a license")) else { return nil }
        guard let edited = finalImage() else { return nil }
        let settings = Settings.shared
        let image = Storage.outputImage(edited, pixelScale: pixelScale, settings: settings)
        let format = Storage.resolveFormat(for: image, settings: settings)
        let url = Storage.uniqueURL(in: settings.saveFolder, ext: format.fileExtension)
        do {
            try Storage.save(image, to: url, quality: settings.jpegQuality, dpi: Storage.dpi(pixelScale: pixelScale, settings: settings))
            if announce { Toast.show("\(t("Saved")): \(url.lastPathComponent)") }
            return url
        } catch {
            showError(error)
            return nil
        }
    }

    @objc public func saveImageAs() {
        guard LicenseManager.shared.require(t("Copying, saving, uploading and printing need a license")) else { return }
        guard let edited = finalImage(), let window else { return }
        let image = Storage.outputImage(edited, pixelScale: pixelScale)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = Storage.fileName(ext: Storage.resolveFormat(for: image).fileExtension)
        panel.directoryURL = Settings.shared.saveFolder
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try Storage.save(image, to: url, quality: Settings.shared.jpegQuality, dpi: Storage.dpi(pixelScale: self?.pixelScale ?? 1)) } catch { self?.showError(error) }
        }
    }

    /// File ▸ Print: sends the edited image (or the selection) to the print dialog, scaled to fit the page.
    @objc public func printImage() {
        guard LicenseManager.shared.require(t("Copying, saving, uploading and printing need a license")) else { return }
        guard var image = finalImage(), let window else { return }
        if let r = canvas.selectionPixelRect, let part = image.cropping(to: r) { image = part }
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        let size = NSSize(width: CGFloat(image.width) / pixelScale, height: CGFloat(image.height) / pixelScale)
        let view = NSImageView(frame: NSRect(origin: .zero, size: size))
        view.image = NSImage(cgImage: image, size: size)
        view.imageScaling = .scaleProportionallyUpOrDown
        NSPrintOperation(view: view, printInfo: info).runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    @objc public func runOCR() {
        Toast.show(t("Reading text…"), duration: 1.2)
        let image = canvas.selectionImage() ?? canvas.state.image  // the selection, when there is one
        Task { @MainActor in
            do {
                let text = try await OCR.recognize(image)
                if text.isEmpty {
                    Toast.show(t("No text found"))
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    Toast.show(String(format: t("Copied %d characters"), text.count))
                }
            } catch {
                Toast.show("OCR: \(error.localizedDescription)")
            }
        }
    }

    /// Finds emails, IDs, card numbers, keys… with OCR and pixelates them.
    @objc public func hidePII() {
        let settings = Settings.shared
        let patterns = Redactor.patterns(enabledIDs: settings.enabledRedactionIDs, custom: settings.customRedactionPatterns)
        let image = canvas.state.image
        Toast.show(t("Reading text…"), duration: 1.2)
        Task { @MainActor in
            do {
                let rects = try await Redactor.regions(in: image, patterns: patterns)
                if rects.isEmpty {
                    Toast.show(t("Nothing to hide"))
                } else {
                    canvas.addPixelation(pixelRects: rects)
                    Toast.show(String(format: t("Hid %d item(s)"), rects.count))
                }
            } catch {
                Toast.show("OCR: \(error.localizedDescription)")
            }
        }
    }

    @objc public func pinImage() {
        guard LicenseManager.shared.require(t("Copying, saving, uploading and printing need a license")) else { return }
        guard let image = finalImage() else { return }
        PinRegistry.pin(image: image, pixelScale: pixelScale)
    }

    @objc public func uploadImage() {
        guard LicenseManager.shared.require(t("Copying, saving, uploading and printing need a license")) else { return }
        guard let edited = finalImage() else { return }
        let settings = Settings.shared
        let image = Storage.outputImage(edited, pixelScale: pixelScale, settings: settings)
        let format = Storage.resolveFormat(for: image, settings: settings)
        guard let data = Storage.encoded(image, format: format, quality: settings.jpegQuality, dpi: Storage.dpi(pixelScale: pixelScale, settings: settings)) else { return }
        Toast.show(t("Uploading…"), duration: 30)
        Task { @MainActor in
            do {
                let link = try await Uploader.upload(
                    data, fileName: Storage.fileName(ext: format.fileExtension),
                    contentType: format == .png ? "image/png" : "image/jpeg")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.absoluteString, forType: .string)
                UploadHistory.shared.add(url: link, name: Storage.fileName(ext: format.fileExtension))
                Toast.show("\(t("Link copied")): \(link.host ?? "")", duration: 3)
            } catch {
                Toast.show("\(t("Upload failed")): \(error.localizedDescription)", duration: 5)
                if case UploadError.notConfigured = error { onNeedsUploadSetup?() }
            }
        }
    }

    private func handleEscape() {
        switch Settings.shared.escBehavior {
        case "copyClose": copyImage()
        case "saveClose": save(announce: true)
        default: break
        }
        window?.close()
    }

    private func writeTemporaryFile() -> URL? {
        guard LicenseManager.shared.require(t("Copying, saving, uploading and printing need a license")) else { return nil }
        guard let edited = finalImage() else { return nil }
        let image = Storage.outputImage(edited, pixelScale: pixelScale)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Tenix-ChaeDiew-drag", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(Storage.fileName(ext: Storage.resolveFormat(for: image).fileExtension))
        return try? Storage.save(image, to: url, quality: Settings.shared.jpegQuality, dpi: Storage.dpi(pixelScale: pixelScale))
    }

    public func windowWillClose(_ notification: Notification) { onClose?(self) }

    private func showError(_ error: Error) {
        guard let window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }
}

/// The window's content view; accepts image files dragged onto the window.
private final class DropView: NSView {
    var onDropImage: ((CGImage, CGFloat) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func imageURLs(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { ["png", "jpg", "jpeg", "gif", "tiff", "tif", "heic", "bmp", "webp"].contains($0.pathExtension.lowercased()) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { imageURLs(sender).isEmpty ? [] : .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        var opened = false
        for url in imageURLs(sender) {
            guard let nsImage = NSImage(contentsOf: url), let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            onDropImage?(cg, max(1, CGFloat(cg.width) / max(nsImage.size.width, 1)))
            opened = true
        }
        return opened
    }
}

/// Holds the canvas and, when a backdrop is chosen, shows it live: background, padding, rounded corners and shadow.
private final class BackdropContainer: NSView {
    let canvas: CanvasView
    var spec: BackdropSpec = .none { didSet { relayout() } }
    override var isFlipped: Bool { true }

    init(canvas: CanvasView) {
        self.canvas = canvas
        super.init(frame: canvas.frame)
        addSubview(canvas)
        canvas.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: canvas, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func relayout() {
        let pad = CGFloat(spec.effectivePadding)
        let size = NSSize(width: canvas.frame.width + pad * 2, height: canvas.frame.height + pad * 2)
        if frame.size != size { setFrameSize(size) }
        if canvas.frame.origin != NSPoint(x: pad, y: pad) { canvas.setFrameOrigin(NSPoint(x: pad, y: pad)) }
        canvas.wantsLayer = spec.isOn
        canvas.layer?.cornerRadius = spec.isOn ? CGFloat(spec.innerRadius) : 0
        canvas.layer?.masksToBounds = spec.isOn
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard spec.isOn, let ctx = NSGraphicsContext.current?.cgContext else { return }
        // The shared drawing code expects a bottom-left origin; this view is flipped.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        let imageRect = CGRect(x: canvas.frame.minX, y: bounds.height - canvas.frame.maxY, width: canvas.frame.width, height: canvas.frame.height)
        Backdrop.drawFrame(spec, in: ctx, size: bounds.size, imageRect: imageRect, scale: 1)
        ctx.restoreGState()
    }
}

/// Keeps a document that is smaller than the window centred instead of pinned to a corner.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposed: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposed)
        if let doc = documentView {
            if rect.width > doc.frame.width { rect.origin.x = (doc.frame.width - rect.width) / 2 }
            if rect.height > doc.frame.height { rect.origin.y = (doc.frame.height - rect.height) / 2 }
        }
        return rect
    }
}

/// A small image well: dragging it starts a file drag of the current edit, to drop into Mail, Slack, Finder…
private final class DragHandle: NSImageView, NSDraggingSource {
    var provider: (() -> URL?)?
    private var hovered = false { didSet { contentTintColor = hovered ? Brand.text : Brand.textMuted; layer?.backgroundColor = (hovered ? Brand.inkHover : .clear).cgColor } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        image = NSImage(systemSymbolName: "square.and.arrow.up.on.square", accessibilityDescription: "Drag")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        imageScaling = .scaleNone
        contentTintColor = Brand.textMuted
        wantsLayer = true
        layer?.cornerRadius = 7
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 30).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setTip(_ text: String) { toolTip = text; setAccessibilityLabel(text) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func mouseDown(with event: NSEvent) {
        guard let url = provider?() else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

/// Keeps pin windows alive until they are closed.
@MainActor
public enum PinRegistry {
    private static var pins: [PinWindow] = []

    public static func pin(image: CGImage, pixelScale: CGFloat) {
        let pin = PinWindow(image: image, pixelScale: pixelScale)
        pin.center()
        pins.append(pin)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: pin, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                pins.removeAll { $0 === note.object as AnyObject }
            }
        }
        pin.makeKeyAndOrderFront(nil)
    }
}
