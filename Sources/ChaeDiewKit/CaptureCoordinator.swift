import AppKit
import ImageIO

@MainActor
public final class CaptureCoordinator {
    public enum Mode { case area, fullscreen, window, ocr, qr, scrolling, repeatLast }

    public var onOpenPreferences: (() -> Void)?

    private let selector = RegionSelector()
    private var editors: [EditorWindowController] = []
    private var scrollSession: ScrollCaptureSession?
    private var busy = false
    /// When set, the next finished capture is joined to this editor instead of opening a new one.
    private var appendTarget: EditorWindowController?
    /// Overrides the "after capture" setting for the capture in progress (from a `chaediew://` URL).
    private var pendingThen: [ThenAction]?
    private var lastArea: (displayID: CGDirectDisplayID, rect: CGRect)?

    public init() {}

    // MARK: Entry points

    public func start(_ mode: Mode, delay: Int = 0, then: [ThenAction]? = nil) {
        guard !busy else { return }
        busy = true
        pendingThen = then
        Task { @MainActor in
            if delay > 0 {
                for remaining in stride(from: delay, to: 0, by: -1) {
                    Toast.show(String(format: t("Captures in %d…"), remaining), duration: 1.1)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                Toast.dismiss()
                try? await Task.sleep(nanoseconds: 200_000_000)  // let the window server drop the toast
            }
            await run(mode)
        }
    }

    /// Runs a command received through the `chaediew://` URL scheme.
    public func perform(_ command: URLCommand) {
        switch command {
        case .grab(let mode, let delay, let then): start(mode, delay: delay, then: then)
        case .addCapture:
            guard let target = editors.last else { return Toast.show(t("Open an image in the editor first")) }
            target.addCapture()
        case .ocr: start(.ocr)
        case .qr: start(.qr)
        case .pickColor: pickColor()
        case .loadClipboard: openClipboardImage()
        case .loadFile(let url):
            guard let nsImage = NSImage(contentsOf: url), let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            openEditor(image: cg, scale: max(1, CGFloat(cg.width) / max(nsImage.size.width, 1)))
        case .showLibrary: LibraryWindowController.shared.show { [weak self] item in self?.openLibraryItem(item) }
        case .settings: onOpenPreferences?()
        }
    }

    public func pickColor() {
        NSColorSampler().show { color in
            guard let rgb = color?.usingColorSpace(.sRGB) else { return }
            let text = ColorFormats.string(
                r: Double(rgb.redComponent), g: Double(rgb.greenComponent), b: Double(rgb.blueComponent),
                format: Settings.shared.colorFormat)
            Task { @MainActor in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                Toast.show(String(format: t("Copied: %@"), text), duration: 2.5)
            }
        }
    }

    public func openClipboardImage() {
        guard let nsImage = NSImage(pasteboard: .general),
              let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return Toast.show(t("No image on the clipboard")) }
        openEditor(image: cg, scale: max(1, CGFloat(cg.width) / max(nsImage.size.width, 1)))
    }

    public func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let nsImage = NSImage(contentsOf: url),
              let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        openEditor(image: cg, scale: max(1, CGFloat(cg.width) / max(nsImage.size.width, 1)))
    }

    public func openLibraryItem(_ item: LibraryItem) {
        let url = LibraryStore.shared.url(for: item)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        openEditor(image: image, scale: CGFloat(item.pixelScale))
    }

    // MARK: Running a capture

    private func run(_ mode: Mode) async {
        do {
            if mode == .repeatLast {
                guard let last = lastArea, let screen = ScreenGrabber.screen(withDisplayID: last.displayID) else {
                    busy = false
                    return Toast.show(t("No previous area yet"))
                }
                let context = try await ScreenGrabber.context(for: screen)
                let frame = try await ScreenGrabber.capture(context)
                busy = false
                if let crop = crop(frame, to: last.rect, scale: context.pixelScale) { deliver(crop, scale: context.pixelScale) }
                return
            }

            guard let screen = ScreenGrabber.screenUnderMouse() else { throw CaptureError.displayNotFound }
            let context = try await ScreenGrabber.context(for: screen)
            let frame = try await ScreenGrabber.capture(context)

            if mode == .fullscreen {
                busy = false
                deliver(frame, scale: context.pixelScale)
                return
            }

            selector.select(on: screen, image: frame, windows: WindowList.onScreen(), startInWindowMode: mode == .window) { [self] selection in
                guard let selection else { busy = false; cancelAppend(); return }
                Task { @MainActor in await handle(selection, mode: mode, screen: screen, context: context, frame: frame) }
            }
        } catch CaptureError.permissionDenied {
            busy = false
            cancelAppend()
            requestPermission()
        } catch {
            busy = false
            cancelAppend()
            Toast.show("\(t("Capture failed")): \(error.localizedDescription)")
        }
    }

    private func handle(_ selection: Selection, mode: Mode, screen: NSScreen, context: GrabContext, frame: CGImage) async {
        switch selection {
        case .window(let info) where mode == .window || mode == .area:
            // The window on its own, even where other windows overlap it.
            do {
                let background = Settings.shared.windowBackground
                let shot = try await ScreenGrabber.captureWindow(id: info.id, includeShadow: Settings.shared.windowShadow || background == .wallpaper)
                busy = false
                var image = shot.image
                if let fill = background.rgb, let flat = ImageOps.flattened(image, onto: fill) { image = flat }
                if background == .wallpaper, let wall = Self.wallpaper(for: screen),
                   let framed = ImageOps.over(image, background: wall, margin: Int(48 * shot.pixelScale)) { image = framed }
                deliver(image, scale: shot.pixelScale)
            } catch {
                busy = false
                Toast.show("\(t("Capture failed")): \(error.localizedDescription)")
            }
        case .window(let info):
            await finish(mode, rect: WindowList.localFrame(of: info.frame, on: screen), screen: screen, context: context, frame: frame)
        case .rect(let rect):
            await finish(mode, rect: rect, screen: screen, context: context, frame: frame)
        }
    }

    private func finish(_ mode: Mode, rect: CGRect, screen: NSScreen, context: GrabContext, frame: CGImage) async {
        let scale = context.pixelScale
        if mode != .fullscreen, let id = ScreenGrabber.displayID(of: screen) { lastArea = (id, rect) }

        if mode == .scrolling {
            let session = ScrollCaptureSession(
                screen: screen, context: context, region: rect, auto: Settings.shared.autoScroll
            ) { [self] image, scale in
                busy = false
                scrollSession = nil
                if let image { deliver(image, scale: scale) }
            }
            scrollSession = session
            session.start()
            return
        }

        busy = false
        guard let crop = crop(frame, to: rect, scale: scale) else { return Toast.show(t("Could not crop the selection")) }
        switch mode {
        case .ocr: recognize(crop)
        case .qr: scanCodes(crop)
        default: deliver(crop, scale: scale)
        }
    }

    /// The desktop picture of `screen`, if macOS gives us a readable file.
    private static func wallpaper(for screen: NSScreen) -> CGImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// A cancelled or failed "Add Capture": bring the editor back.
    private func cancelAppend() {
        guard let target = appendTarget else { return }
        appendTarget = nil
        target.present()
    }

    private func crop(_ frame: CGImage, to rect: CGRect, scale: CGFloat) -> CGImage? {
        let pixelRect = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                               width: rect.width * scale, height: rect.height * scale).integral
        return frame.cropping(to: pixelRect)
    }

    // MARK: After the capture

    private func deliver(_ image: CGImage, scale: CGFloat) {
        if let target = appendTarget {
            appendTarget = nil
            target.appendCapture(image, scale: scale)
            return
        }
        let settings = Settings.shared
        if settings.libraryEnabled { addToLibrary(image, scale: scale) }
        var actions: [ThenAction]
        if let then = pendingThen, !then.isEmpty {
            actions = then
        } else {
            switch settings.afterCapture {
            case .editor: actions = [.edit]
            case .copy: actions = [.copy]
            case .save: actions = [.save]
            case .copySave: actions = [.copy, .save]
            case .thumbnail: actions = [.thumbnail]
            }
        }
        pendingThen = nil
        // Copying, saving and pinning need a licence once the trial is over; the capture itself is never lost: it opens in the editor.
        if actions.contains(where: { [ThenAction.copy, .save, .pin].contains($0) }), !LicenseManager.shared.require(t("Copying, saving, uploading and printing need a license")) {
            actions = [.edit]
        }
        for action in actions {
            switch action {
            case .edit: openEditor(image: image, scale: scale)
            case .copy:
                copyToPasteboard(image, scale: scale)
                if !actions.contains(.save) { Toast.show(t("Copied to clipboard")) }
            case .save: saveToDisk(image, scale: scale)
            case .pin: PinRegistry.pin(image: image, pixelScale: scale)
            case .thumbnail:
                ThumbnailPanel.show(
                    image: image, pixelScale: scale,
                    onEdit: { [weak self] in self?.openEditor(image: image, scale: scale) },
                    onCopy: { [weak self] in self?.copyToPasteboard(image, scale: scale); Toast.show(t("Copied to clipboard")) },
                    onSave: { [weak self] in self?.saveToDisk(image, scale: scale) })
            }
        }
    }

    private func addToLibrary(_ image: CGImage, scale: CGFloat) {
        guard let item = LibraryStore.shared.add(image: image, pixelScale: scale) else { return }
        Task { @MainActor in  // index the text in the background so the library is searchable by content
            if let text = try? await OCR.recognize(image), !text.isEmpty {
                LibraryStore.shared.setOCRText(text, for: item.id)
            }
        }
    }

    private func copyToPasteboard(_ image: CGImage, scale: CGFloat) {
        let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: size)])
    }

    private func saveToDisk(_ image: CGImage, scale: CGFloat) {
        let settings = Settings.shared
        let output = Storage.outputImage(image, pixelScale: scale, settings: settings)
        let format = Storage.resolveFormat(for: output, settings: settings)
        let url = Storage.uniqueURL(in: settings.saveFolder, ext: format.fileExtension)
        do {
            try Storage.save(output, to: url, quality: settings.jpegQuality, dpi: Storage.dpi(pixelScale: scale, settings: settings))
            Toast.show("\(t("Saved")): \(url.lastPathComponent)")
        } catch {
            Toast.show("\(t("Capture failed")): \(error.localizedDescription)")
        }
    }

    private func recognize(_ image: CGImage) {
        Toast.show(t("Reading text…"), duration: 1.2)
        Task { @MainActor in
            do {
                let text = try await OCR.recognize(image)
                guard !text.isEmpty else { return Toast.show(t("No text found")) }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                Toast.show(String(format: t("Copied %d characters"), text.count))
            } catch {
                Toast.show("OCR: \(error.localizedDescription)")
            }
        }
    }

    private func scanCodes(_ image: CGImage) {
        Task { @MainActor in
            let codes = (try? await Barcode.detect(in: image)) ?? []
            guard !codes.isEmpty else { return Toast.show(t("No QR code or barcode found")) }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(codes.joined(separator: "\n"), forType: .string)
            Toast.show(String(format: t("Copied: %@"), String(codes[0].prefix(80))), duration: 3)
        }
    }

    private func openEditor(image: CGImage, scale: CGFloat) {
        let editor = EditorWindowController(image: image, pixelScale: scale)
        editor.onClose = { [weak self] closed in self?.editors.removeAll { $0 === closed } }
        editor.onOpenImage = { [weak self] image, scale in self?.openEditor(image: image, scale: scale) }
        editor.onNeedsUploadSetup = { [weak self] in self?.onOpenPreferences?() }
        editor.onRequestAddCapture = { [weak self] target in
            guard let self, !self.busy else { return }
            self.appendTarget = target
            self.start(.area)
        }
        editors.append(editor)
        editor.present()
    }

    private func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
        let alert = NSAlert()
        alert.messageText = t("Screen Recording permission needed")
        alert.informativeText = t("Allow Tenix-ChaeDiew in System Settings › Privacy & Security › Screen Recording, then quit and reopen Tenix-ChaeDiew.")
        alert.addButton(withTitle: t("Open System Settings"))
        alert.addButton(withTitle: t("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
