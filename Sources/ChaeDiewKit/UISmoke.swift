import AppKit

/// Builds the real windows with sample data and renders them to PNG files, so layout, localisation and
/// the editor's tools can be inspected without screen-recording permission. Run: `Tenix-ChaeDiew --ui-smoke <dir> [th]`.
@MainActor
public enum UISmoke {
    public static func run(outputDir: URL, language: Lang) {
        Settings.languageOverride = language
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        func log(_ m: String) { FileHandle.standardError.write(Data((m + "\n").utf8)) }

        let editor = EditorWindowController(image: samplePage(), pixelScale: 2)
        editor.present()
        let marks: [Annotation] = [
            Annotation(kind: .rectangle, start: CGPoint(x: 40, y: 120), end: CGPoint(x: 330, y: 168), lineWidth: 3),
            Annotation(kind: .arrow, start: CGPoint(x: 420, y: 60), end: CGPoint(x: 350, y: 140), lineWidth: 5, tapered: true),
            Annotation(kind: .counter, start: CGPoint(x: 28, y: 144), end: CGPoint(x: 28, y: 144), number: 1),
            Annotation(kind: .text, start: CGPoint(x: 430, y: 40), end: CGPoint(x: 430, y: 40), color: .systemYellow,
                       text: language == .th ? "ตรวจสอบช่องนี้" : "Check this field"),
            Annotation(kind: .ruler, start: CGPoint(x: 40, y: 330), end: CGPoint(x: 300, y: 330), color: .systemPurple),
            Annotation(kind: .magnifier, start: CGPoint(x: 105, y: 338), end: CGPoint(x: 127, y: 338), color: .systemOrange,
                       bubble: CGPoint(x: 250, y: 330)),
            Annotation(kind: .rectangle, start: CGPoint(x: 420, y: 230), end: CGPoint(x: 540, y: 290), color: .systemBlue, lineWidth: 3, fill: .hatch, sketchy: true),
            Annotation(kind: .ellipse, start: CGPoint(x: 560, y: 230), end: CGPoint(x: 660, y: 290), color: .systemGreen, fill: .solid),
            Annotation(kind: .arrow, start: CGPoint(x: 400, y: 340), end: CGPoint(x: 560, y: 330), color: .systemPurple, lineWidth: 4, arrowHead: .double, bend: 30, sketchy: true),
            Annotation(kind: .counter, start: CGPoint(x: 40, y: 200), end: CGPoint(x: 40, y: 200), color: .systemBlue, number: 2, fontSize: 22, angle: -0.6),
            Annotation(kind: .highlight, start: CGPoint(x: 40, y: 220), end: CGPoint(x: 250, y: 220), color: .systemYellow, lineWidth: 4, marker: true),
            Annotation(kind: .blur, start: CGPoint(x: 150, y: 92), end: CGPoint(x: 350, y: 126), blurMode: .blurText),
        ]
        marks.forEach(editor.addAnnotation)

        let store = LibraryStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("chaediew-smoke-\(UUID().uuidString)"))
        for (i, text) in ["Invoice 2026 total 4,500 baht", "Meeting notes Bangkok office", "Error: connection refused 10.0.0.12"].enumerated() {
            if let item = store.add(image: samplePage(), pixelScale: 2, date: Date().addingTimeInterval(Double(-i) * 86_400 * 3)) {
                store.setOCRText(text, for: item.id)
            }
        }
        LibraryWindowController.shared.show(store: store) { _ in }
        PreferencesWindowController.shared.show()

        var finished = false
        func finishAndQuit() {
            guard !finished else { return }
            finished = true
            snapshot(editor.window, to: outputDir.appendingPathComponent("editor.png"))
            snapshot(NSApp.windows.first { $0.title.contains(t("Library")) }, to: outputDir.appendingPathComponent("library.png"))
            snapshot(NSApp.windows.first { $0.title.contains(t("Preferences…").replacingOccurrences(of: "…", with: "")) },
                     to: outputDir.appendingPathComponent("preferences.png"))
            print("UI smoke finished")
            NSApp.terminate(nil)
        }

        // Same order as a real launch: warm Vision up, then Hide PII (OCR + pixelate) should be quick.
        Task { @MainActor in
            let t0 = Date()
            await OCR.warmUp()
            log("smoke: Vision warm-up took \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
            let t1 = Date()
            editor.hidePII()
            let patterns = Redactor.patterns(enabledIDs: Settings.shared.enabledRedactionIDs, custom: [])
            let found = try? await Redactor.regions(in: samplePage(), patterns: patterns)
            log("smoke: redaction found \(found?.count ?? -1) regions in \(String(format: "%.1f", Date().timeIntervalSince(t1)))s")
            try? await Task.sleep(nanoseconds: 2_500_000_000)  // let the editor's own Hide PII repaint
            // One shot per kind of selection, to see the floating style panel for each.
            for (name, index) in [("rect", 6), ("arrow", 8), ("blur", 10), ("counter", 9), ("text", 3), ("magnifier", 5)] {
                editor.selectAnnotation(index)
                try? await Task.sleep(nanoseconds: 700_000_000)
                snapshot(editor.window, to: outputDir.appendingPathComponent("editor-\(name).png"))
            }
            editor.selectAnnotation(nil)
            editor.setSelection(CGRect(x: 120, y: 60, width: 300, height: 120))
            try? await Task.sleep(nanoseconds: 700_000_000)
            snapshot(editor.window, to: outputDir.appendingPathComponent("editor-selection.png"))
            editor.setSelection(nil)
            editor.setBackdrop(.ocean)
            try? await Task.sleep(nanoseconds: 700_000_000)
            snapshot(editor.window, to: outputDir.appendingPathComponent("editor-backdrop.png"))
            editor.setBackdrop(.none)
            ShortcutsWindowController.shared.show()
            try? await Task.sleep(nanoseconds: 700_000_000)
            snapshot(NSApp.windows.first { $0.title.contains(t("Keyboard Shortcuts")) }, to: outputDir.appendingPathComponent("shortcuts.png"))
            finishAndQuit()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { finishAndQuit() }  // safety net
    }

    static func snapshot(_ window: NSWindow?, to url: URL) {
        guard let window else { return print("missing window for \(url.lastPathComponent)") }
        // Ask the window server for this window's real pixels (controls, glass, SwiftUI included).
        if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]),
           cg.width > 10 {
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("wrote \(url.lastPathComponent) (window server) \(cg.width)×\(cg.height)")
            return
        }
        guard let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.lastPathComponent) \(Int(view.bounds.width))×\(Int(view.bounds.height))")
    }

    /// A fake web form containing an email and a Thai ID, so auto-redact has something to find.
    static func samplePage() -> CGImage {
        let w = 1400, h = 800
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.97, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.12, green: 0.33, blue: 0.85, alpha: 1)); ctx.fill(CGRect(x: 0, y: h - 110, width: w, height: 110))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        func draw(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: NSColor = .black, bold: Bool = false) {
            NSString(string: s).draw(at: CGPoint(x: x, y: y), withAttributes: [
                .font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size), .foregroundColor: color])
        }
        draw("Customer profile", 60, CGFloat(h) - 85, 44, .white, bold: true)
        draw("Name: Somchai Jaidee", 60, CGFloat(h) - 240, 36)
        draw("Email: somchai.jaidee@example.com", 60, CGFloat(h) - 320, 36)
        draw("National ID: 1-2345-67890-12-1", 60, CGFloat(h) - 400, 36)
        draw("Phone: 081-234-5678", 60, CGFloat(h) - 480, 36)
        draw("Server: 192.168.10.25", 60, CGFloat(h) - 560, 36)
        ctx.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 60, y: 80, width: 300, height: 90))
        draw("Save", 150, 105, 40, .white, bold: true)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }
}
