import AppKit

/// Developer aid (`Tenix-ChaeDiew --ui-tour <dir> [th]`): opens the real editor on a sample page, performs every tool and
/// panel through the window's own event dispatch (so hit-testing, handles, panels and key handling are all exercised),
/// photographs each step and logs what it expected. Needs no Screen Recording permission: it only photographs its own windows.
@MainActor
public enum UITour {
    private static func log(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }

    public static func run(outputDir: URL, language: Lang) {
        Settings.languageOverride = language
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let editor = EditorWindowController(image: UISmoke.samplePage(), pixelScale: 2)
        editor.present()
        Task { @MainActor in
            await OCR.warmUp()
            await tour(editor, outputDir)
            log("tour finished")
            NSApp.terminate(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 240) { NSApp.terminate(nil) }  // safety net
    }

    // MARK: Event helpers

    @MainActor
    private final class Driver {
        let editor: EditorWindowController
        let canvas: CanvasView
        let window: NSWindow
        let out: URL
        var index = 0

        init(_ editor: EditorWindowController, _ out: URL) {
            self.editor = editor
            canvas = editor.canvas
            window = editor.window!
            self.out = out
        }

        func wait(_ s: Double = 0.35) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

        func snap(_ name: String, of target: NSWindow? = nil) async {
            await wait(0.45)
            index += 1
            UISmoke.snapshot(target ?? window, to: out.appendingPathComponent(String(format: "%02d-%@.png", index, name)))
        }

        func mouse(_ type: NSEvent.EventType, _ p: CGPoint, flags: NSEvent.ModifierFlags = [], clicks: Int = 1) {
            let e = NSEvent.mouseEvent(with: type, location: canvas.convert(p, to: nil), modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
            window.sendEvent(e)
        }

        func drag(_ a: CGPoint, _ b: CGPoint, flags: NSEvent.ModifierFlags = []) {
            mouse(.leftMouseDown, a, flags: flags)
            for i in 1...8 { let t = CGFloat(i) / 8; mouse(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), flags: flags) }
            mouse(.leftMouseUp, b, flags: flags)
        }

        func click(_ p: CGPoint, flags: NSEvent.ModifierFlags = [], clicks: Int = 1) {
            mouse(.leftMouseDown, p, flags: flags, clicks: clicks)
            mouse(.leftMouseUp, p, flags: flags, clicks: clicks)
        }

        /// Pointer moved without a button. (Plain mouse-moved events only reach a view through the window server's
        /// tracking areas, so the canvas is called directly.)
        func hover(_ p: CGPoint) {
            let e = NSEvent.mouseEvent(with: .mouseMoved, location: canvas.convert(p, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            canvas.mouseMoved(with: e)
        }

        func key(_ chars: String, code: UInt16 = 0, flags: NSEvent.ModifierFlags = [], up: Bool = false) {
            let e = NSEvent.keyEvent(with: up ? .keyUp : .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                     isARepeat: false, keyCode: code)!
            window.sendEvent(e)
        }

        /// Letter shortcut as typed on a keyboard (also released).
        func press(_ chars: String, code: UInt16 = 0, flags: NSEvent.ModifierFlags = []) {
            key(chars, code: code, flags: flags)
            key(chars, code: code, flags: flags, up: true)
        }

        var last: Annotation? { canvas.state.annotations.last }
        var count: Int { canvas.state.annotations.count }
    }

    private static func check(_ name: String, _ ok: Bool) { log((ok ? "OK    " : "FAIL  ") + name) }

    // MARK: The tour

    private static func tour(_ editor: EditorWindowController, _ out: URL) async {
        UserDefaults.standard.removeObject(forKey: "backdropSpec")   // start every tour from the default backdrop
        let d = Driver(editor, out)
        await d.wait(1.0)
        await d.snap("opened")

        // Rectangle
        d.press("r", code: 15)
        d.drag(CGPoint(x: 40, y: 120), CGPoint(x: 330, y: 168))
        check("rectangle drawn by dragging", d.last?.kind == .rectangle)
        await d.snap("rectangle-with-style-panel")

        // The style panel can be dragged out of the way by its background
        if let panel = editor.stylePanel, !panel.isHidden {
            let before = panel.frame
            let start = CGPoint(x: before.minX + 8, y: before.maxY - 8)
            for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, CGPoint(x: start.x - 120, y: start.y - 20)), (.leftMouseDragged, CGPoint(x: start.x - 300, y: start.y - 60)), (.leftMouseUp, CGPoint(x: start.x - 300, y: start.y - 60))] {
                let e = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: d.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                d.window.sendEvent(e)
            }
            d.window.contentView?.layoutSubtreeIfNeeded()
            check("the style panel moved when dragged by its background", panel.frame.minX < before.minX - 200 && panel.frame.minY < before.minY - 30)
            await d.snap("style-panel-dragged")
            panel.topConstraint?.constant = 12; panel.trailingConstraint?.constant = -22   // put it back for the following steps
            d.window.contentView?.layoutSubtreeIfNeeded()
        }

        // Hand-drawn oval (the marker-loop look)
        d.press("o", code: 31)
        d.drag(CGPoint(x: 350, y: 95), CGPoint(x: 560, y: 160))
        d.canvas.updateStyle { $0.sketchy = true }
        await d.snap("oval-hand-drawn")

        // Arrow, then bend it with its middle handle
        d.press("a", code: 0)
        d.drag(CGPoint(x: 590, y: 210), CGPoint(x: 440, y: 300))
        if let arrow = d.last, let mid = arrow.handles().first(where: { $0.handle == .bend })?.point {
            d.drag(mid, CGPoint(x: mid.x + 35, y: mid.y + 20))
            check("arrow bent by dragging its middle handle", (d.last?.bend ?? 0) != 0)
        }
        await d.snap("arrow-bent")

        // Line and pen
        d.press("l", code: 37)
        d.drag(CGPoint(x: 40, y: 200), CGPoint(x: 200, y: 200), flags: [.shift])
        d.press("p", code: 35)
        d.mouse(.leftMouseDown, CGPoint(x: 40, y: 290))
        for i in 1...40 { d.mouse(.leftMouseDragged, CGPoint(x: 40 + CGFloat(i) * 5, y: 290 + 14 * sin(CGFloat(i) / 3))) }
        d.mouse(.leftMouseUp, CGPoint(x: 240, y: 290))
        check("pen stroke recorded", d.last?.kind == .freehand && (d.last?.points.count ?? 0) > 20)
        await d.snap("line-and-pen")

        // Text
        d.press("t", code: 17)
        d.click(CGPoint(x: 420, y: 300))
        for ch in "Hello Tenix" { d.key(String(ch)); d.key(String(ch), up: true) }
        d.key("\r", code: 36)
        check("text label committed", d.last?.kind == .text && d.last?.text == "Hello Tenix")
        await d.snap("text-label")

        // Blur / erase modes on the sample's text lines
        d.press("b", code: 11)
        let lines: [(BlurMode, CGRect)] = [
            (.blur, CGRect(x: 80, y: 139, width: 250, height: 24)), (.blurText, CGRect(x: 80, y: 179, width: 250, height: 24)),
            (.erase, CGRect(x: 80, y: 219, width: 180, height: 24)), (.eraseText, CGRect(x: 80, y: 259, width: 190, height: 24)),
        ]
        for (mode, r) in lines {
            d.canvas.select(nil)
            d.canvas.updateStyle { $0.blurMode = mode }
            d.drag(CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY))
        }
        await d.snap("blur-modes-blur-blurtext-erase-erasetext")

        // Counters: place three, then move the first one (the bug the user reported) and rotate a pointer
        d.press("n", code: 45)
        d.canvas.select(nil)
        let spots = [CGPoint(x: 600, y: 270), CGPoint(x: 640, y: 270), CGPoint(x: 680, y: 270)]
        spots.forEach { d.click($0) }
        let numbers = d.canvas.state.annotations.filter { $0.kind == .counter }.map(\.number)
        check("three counters numbered 1, 2, 3", numbers == [1, 2, 3])
        d.drag(spots[0], CGPoint(x: 560, y: 340))
        let first = d.canvas.state.annotations.first { $0.kind == .counter && $0.number == 1 }
        check("an old counter can be moved with the counter tool still active", first.map { abs($0.start.x - 560) < 6 && abs($0.start.y - 340) < 6 } ?? false)
        check("…and no extra counter was added by that drag", d.canvas.state.annotations.filter { $0.kind == .counter }.count == 3)
        if let handle = d.last?.handles().first(where: { $0.handle == .tail })?.point ?? first?.handles().first?.point {
            d.canvas.select(d.canvas.state.annotations.lastIndex { $0.kind == .counter && $0.number == 1 })
            if let h = d.canvas.selectedAnnotation?.handles().first?.point { d.drag(h, CGPoint(x: h.x + 40, y: h.y - 30)) }
            _ = handle
        }
        await d.snap("counters-moved-and-rotated")

        // Highlighter
        d.press("h", code: 4)
        d.canvas.select(nil)
        d.drag(CGPoint(x: 40, y: 94), CGPoint(x: 250, y: 94))
        await d.snap("marker-highlight")

        // Spotlight with level 7
        d.press("s", code: 1)
        d.canvas.select(nil)
        d.drag(CGPoint(x: 30, y: 312), CGPoint(x: 190, y: 365))
        d.key("7", code: 26); d.key("7", code: 26, up: true)
        await d.snap("spotlight-level-7")
        d.canvas.undo(); d.canvas.undo()   // the spotlight and its level change are two undo steps

        // Ruler measures by itself
        d.press("m", code: 46)
        d.hover(CGPoint(x: 50, y: 335))
        log("hover point after moving to (80,335): \(String(describing: d.canvas.hoverPoint)); marks: \(d.canvas.measureMarks(at: CGPoint(x: 80, y: 335), horizontal: true, vertical: true).map { "\($0.start)->\($0.end)" })")
        await d.snap("ruler-automatic")
        d.key("1", code: 18); d.hover(CGPoint(x: 52, y: 335))
        await d.snap("ruler-holding-1-height-only")
        d.key("1", code: 18, up: true)
        let before = d.count
        d.click(CGPoint(x: 52, y: 335))
        check("ruler click keeps the measurement(s)", d.count > before)
        d.key("s", code: 1, flags: [.option]); d.hover(CGPoint(x: 300, y: 200))
        await d.snap("ruler-guide-option-s")
        d.key("s", code: 1, flags: [.option], up: true)

        // Magnifier
        d.press("g", code: 5)
        d.canvas.select(nil)
        d.drag(CGPoint(x: 100, y: 338), CGPoint(x: 125, y: 338))
        await d.snap("magnifier")

        // Selection, smart adjust, crop
        d.press("v", code: 9)
        d.canvas.select(nil)
        d.drag(CGPoint(x: 430, y: 175), CGPoint(x: 660, y: 245))
        check("a drag on empty space makes a selection", d.canvas.selectionRect != nil)
        await d.snap("selection")
        d.key("\r", code: 36)
        check("Enter crops to the selection", d.canvas.state.image.width < 1400)
        await d.snap("after-crop")
        d.canvas.undo()

        // Resize a mark with its corner handle, and edit text by double-click
        d.press("v", code: 9)
        d.canvas.select(d.canvas.state.annotations.firstIndex { $0.kind == .rectangle })
        if let corner = d.canvas.selectedAnnotation?.handles().first(where: { $0.handle == .bottomRight })?.point {
            let before = d.canvas.selectedAnnotation!.rect
            d.drag(corner, CGPoint(x: corner.x + 40, y: corner.y + 30))
            check("dragging a corner handle resizes the rectangle", (d.canvas.selectedAnnotation?.rect.width ?? 0) > before.width + 30)
        }
        await d.snap("rectangle-resized-by-handle")
        if let text = d.canvas.state.annotations.first(where: { $0.kind == .text }) {
            d.click(CGPoint(x: text.bounds.midX, y: text.bounds.midY), clicks: 2)
            for ch in "!" { d.key(String(ch)); d.key(String(ch), up: true) }
            d.key("\r", code: 36)
            check("double-clicking a label edits its text", d.canvas.state.annotations.contains { $0.kind == .text && $0.text.hasSuffix("!") })
        }

        // Hide PII (OCR + redaction)
        editor.hidePII()
        await d.wait(3.5)
        await d.snap("hide-pii-after-ocr")
        d.canvas.undo()

        // Paste an overlay picture
        let sticker = ImageOps.padded(UISmoke.samplePage().cropping(to: CGRect(x: 0, y: 0, width: 420, height: 200))!, left: 0, top: 0, right: 0, bottom: 0, fill: (255, 255, 255))!
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: sticker, size: NSSize(width: 210, height: 100))])
        editor.pasteCommand()
        d.key("5", code: 23); d.key("5", code: 23, up: true)
        check("pasted picture becomes a half-opaque overlay", d.last?.kind == .image && d.last?.level == 5)
        await d.snap("pasted-overlay-50-percent")

        // Backdrop panel
        d.canvas.select(nil)
        editor.showBackdropPanel()
        await d.snap("backdrop-panel-linear")
        if let panel = editor.backdropPanel {
            panel.spec.gradient = .mesh; panel.onChange?(panel.spec); panel.rebuild()
            await d.snap("backdrop-panel-mesh")
            var solid = BackdropSpec.solid(RGBColor(38, 40, 46)); solid.padding = 90; solid.outerRadius = 28; solid.innerRadius = 18; solid.shadow = 0.6
            panel.spec = solid; panel.onChange?(panel.spec); panel.rebuild()
            await d.snap("backdrop-panel-solid-rounded")
            panel.onDone?()
        }
        if let exported = editor.finalImage() {
            try? Storage.pngData(from: exported)?.write(to: out.appendingPathComponent("export-final.png"))
            log("exported \(exported.width)x\(exported.height)")
        }
        editor.removeBackdrop()

        // Other windows
        LicenseWindowController.shared.show(reason: t("Copying, saving, uploading and printing need a license"))
        await d.wait(0.6)
        if let w = NSApp.windows.first(where: { $0.title.contains(t("License")) }) { await d.snap("license-window", of: w) }
        LicenseWindowController.shared.reset()
        AboutWindowController.shared.show()
        await d.wait(0.6)
        if let w = NSApp.windows.first(where: { $0.title.contains(t("About Tenix-ChaeDiew")) }) { await d.snap("about-window", of: w) }

        for (i, name) in ["general", "hotkeys", "capture", "privacy", "upload", "license"].enumerated() {
            PreferencesView.initialTab = i
            PreferencesWindowController.shared.reset()
            PreferencesWindowController.shared.show()
            await d.wait(0.6)
            if let w = NSApp.windows.first(where: { $0.title.contains(t("Preferences…").replacingOccurrences(of: "…", with: "")) }) {
                await d.snap("preferences-\(name)", of: w)
            }
        }
        PreferencesWindowController.shared.reset()

        let store = LibraryStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("chaediew-tour-\(UUID().uuidString)"))
        for (i, text) in ["Invoice 2026 total 4,500 baht", "Error: connection refused 10.0.0.12"].enumerated() {
            if let item = store.add(image: UISmoke.samplePage(), pixelScale: 2, date: Date().addingTimeInterval(Double(-i) * 86_400)) { store.setOCRText(text, for: item.id) }
        }
        LibraryWindowController.shared.show(store: store) { _ in }
        await d.wait(0.6)
        if let w = NSApp.windows.first(where: { $0.title.contains(t("Library")) }) { await d.snap("library", of: w) }

        let history = UploadHistory.shared
        let backup = history.records
        history.add(url: URL(string: "https://files.example.com/x7Hq2/screenshot.png")!, name: "Tenix-ChaeDiew 2026-10-19 at 14.31.20.png")
        UploadsWindowController.shared.show()
        await d.wait(0.6)
        if let w = NSApp.windows.first(where: { $0.title.contains(t("Uploaded Screenshots")) }) { await d.snap("uploaded-list", of: w) }
        history.removeAll()
        backup.reversed().forEach { if let u = URL(string: $0.url) { history.add(url: u, name: $0.name, date: $0.date) } }

        ShortcutsWindowController.shared.show()
        await d.wait(0.6)
        if let w = NSApp.windows.first(where: { $0.title.contains(t("Keyboard Shortcuts")) }) { await d.snap("shortcuts-sheet", of: w) }

        ThumbnailPanel.show(image: UISmoke.samplePage(), pixelScale: 2, onEdit: {}, onCopy: {}, onSave: {}, duration: 30)
        await d.wait(0.6)
        if let w = NSApp.windows.first(where: { $0 is ThumbnailPanel }) { await d.snap("thumbnail-panel", of: w) }

        let pin = PinWindow(image: UISmoke.samplePage().cropping(to: CGRect(x: 0, y: 0, width: 800, height: 500))!, pixelScale: 2, near: NSPoint(x: 300, y: 300))
        pin.orderFrontRegardless()
        await d.wait(0.6)
        await d.snap("pin-window", of: pin)
        pin.close()

        Toast.show(t("Copied to clipboard"), duration: 30)
        await d.wait(0.6)
        if let w = NSApp.windows.first(where: { String(describing: type(of: $0)).contains("Toast") }) { await d.snap("toast", of: w) }
        Toast.dismiss()

        // The capture overlay (area selection) over the sample page
        let selector = RegionSelector()
        if let screen = NSScreen.main {
            let frame = ImageOps.scaled(UISmoke.samplePage(), width: Int(screen.frame.width), height: Int(screen.frame.height)) ?? UISmoke.samplePage()
            selector.select(on: screen, image: frame, windows: [], startInWindowMode: false) { _ in }
            await d.wait(0.6)
            if let w = NSApp.windows.first(where: { $0.level == .screenSaver }) {
                let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil,
                                           characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
                await d.snap("capture-overlay", of: w)
                w.sendEvent(key)
            }
        }
    }
}
