import AppKit
import Carbon

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let coordinator = CaptureCoordinator()
    private var observers: [NSObjectProtocol] = []

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = Settings.shared  // registers defaults before any preference view reads them
        LibraryStore.shared.purge(olderThanDays: settings.libraryRetentionDays)
        coordinator.onOpenPreferences = { PreferencesWindowController.shared.show() }

        buildMainMenu()
        buildStatusItem()
        registerHotKeys()
        Task.detached(priority: .utility) { await OCR.warmUp() }
        requestScreenRecordingOnFirstLaunch()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .chaeDiewHotKeysChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerHotKeys(); self?.buildStatusItem() }
        })
        observers.append(center.addObserver(forName: .chaeDiewLanguageChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.buildMainMenu()
                self?.buildStatusItem()
                PreferencesWindowController.shared.reset()
                ShortcutsWindowController.shared.reset()
                UploadsWindowController.shared.reset()
                LicenseWindowController.shared.reset()
            }
        })
    }

    /// Launching the app again (Finder, Spotlight) while its icon is hidden opens Preferences, the way back in.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { PreferencesWindowController.shared.show() }
        return true
    }

    /// `chaediew://…` links. Off unless enabled in Preferences, because any web page could otherwise start a capture.
    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = URLCommand.parse(url) else { continue }
            guard Settings.shared.urlSchemeEnabled else {
                Toast.show(t("The URL scheme is off — enable it in Preferences"), duration: 4)
                continue
            }
            coordinator.perform(command)
        }
    }

    /// macOS lists an app under Screen Recording only after it has asked. Ask once at first launch so
    /// Tenix-ChaeDiew appears there ready to switch on (later requests come from the capture flow itself).
    private func requestScreenRecordingOnFirstLaunch() {
        let key = "askedScreenRecording"
        guard !CGPreflightScreenCaptureAccess(), !Settings.shared.defaults.bool(forKey: key) else { return }
        Settings.shared.defaults.set(true, forKey: key)
        _ = CGRequestScreenCaptureAccess()
    }

    // MARK: Hotkeys

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .area: coordinator.start(.area)
        case .fullscreen: coordinator.start(.fullscreen)
        case .window: coordinator.start(.window)
        case .scrolling: coordinator.start(.scrolling)
        case .ocr: coordinator.start(.ocr)
        case .qr: coordinator.start(.qr)
        case .repeatLast: coordinator.start(.repeatLast)
        case .colorPicker: coordinator.pickColor()
        case .library: showLibrary()
        }
    }

    private func registerHotKeys() {
        let center = HotKeyCenter.shared
        center.unregisterAll()
        var allRegistered = true
        for action in HotKeyAction.allCases {
            guard let spec = Settings.shared.hotKey(for: action) else { continue }
            if !center.register(keyCode: spec.keyCode, modifiers: spec.modifiers, handler: { [weak self] in
                MainActor.assumeIsolated { self?.perform(action) }
            }) { allRegistered = false }
        }
        if !allRegistered {
            Toast.show(t("Some hotkeys are taken by another app — change them in Preferences"), duration: 5)
        }
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = !Settings.shared.hideMenuBarIcon
        item.button?.image = Brand.menuBarIcon()
        item.button?.image?.accessibilityDescription = "Tenix-ChaeDiew"
        let menu = NSMenu()
        for action in HotKeyAction.allCases where action != .library {
            menu.addItem(menuItem(for: action))
        }
        let delayed = NSMenu()
        for seconds in [3, 5, 10] {
            let entry = NSMenuItem(title: "\(seconds) s", action: #selector(delayedCapture(_:)), keyEquivalent: "")
            entry.tag = seconds
            entry.target = self
            delayed.addItem(entry)
        }
        let delayedItem = NSMenuItem(title: t("Delayed Capture"), action: nil, keyEquivalent: "")
        delayedItem.submenu = delayed
        menu.addItem(delayedItem)

        menu.addItem(.separator())
        menu.addItem(menuItem(for: .library))
        menu.addItem(plain(t("Uploaded Screenshots…"), #selector(showUploads)))
        menu.addItem(plain(t("Open Image…"), #selector(openFile)))
        menu.addItem(plain(t("Open From Clipboard"), #selector(openClipboard)))
        menu.addItem(plain(t("Show Saved Screenshots"), #selector(revealFolder)))
        menu.addItem(.separator())
        menu.addItem(plain(t("Preferences…"), #selector(showPreferences), key: ","))
        menu.addItem(plain(t("License…"), #selector(showLicense)))
        menu.addItem(plain(t("About Tenix-ChaeDiew"), #selector(showAbout)))
        menu.addItem(withTitle: t("Quit Tenix-ChaeDiew"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func menuItem(for action: HotKeyAction) -> NSMenuItem {
        let hint = Settings.shared.hotKey(for: action)?.display
        let entry = NSMenuItem(title: hint.map { "\(action.title)    \($0)" } ?? action.title,
                               action: #selector(menuAction(_:)), keyEquivalent: "")
        entry.representedObject = action.rawValue
        entry.target = self
        return entry
    }

    private func plain(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let action = HotKeyAction(rawValue: raw) { perform(action) }
    }

    @objc private func delayedCapture(_ sender: NSMenuItem) { coordinator.start(.area, delay: sender.tag) }
    @objc private func openFile() { coordinator.openFile() }
    @objc private func openClipboard() { coordinator.openClipboardImage() }
    @objc private func revealFolder() { NSWorkspace.shared.open(Settings.shared.saveFolder) }
    @objc private func showPreferences() { PreferencesWindowController.shared.show() }

    private func showLibrary() {
        LibraryWindowController.shared.show { [weak self] item in self?.coordinator.openLibraryItem(item) }
    }

    /// Accessory apps show no menu bar, but key equivalents still route through here.
    /// nil targets send each command to the focused editor window.
    private func buildMainMenu() {
        let main = NSMenu()

        func item(_ title: String, _ action: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
            let m = NSMenuItem(title: title, action: action, keyEquivalent: key)
            m.keyEquivalentModifierMask = key.isEmpty ? [] : mods
            m.target = target
            return m
        }
        let shift: NSEvent.ModifierFlags = [.command, .shift]

        let appMenu = NSMenu()
        appMenu.addItem(item(t("About Tenix-ChaeDiew"), #selector(showAbout), target: self))
        appMenu.addItem(item(t("License…"), #selector(showLicense), target: self))
        appMenu.addItem(item(t("Preferences…"), #selector(showPreferences), ",", target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item(t("Quit Tenix-ChaeDiew"), #selector(NSApplication.terminate(_:)), "q"))

        let file = NSMenu(title: t("File"))
        file.addItem(item(t("Open Image…"), #selector(openFile), "o", shift, target: self))
        file.addItem(item(t("Open From Clipboard"), #selector(openClipboard), "v", shift, target: self))
        file.addItem(item(t("Uploaded Screenshots…"), #selector(showUploads), "u", shift, target: self))
        file.addItem(.separator())
        file.addItem(item(t("Save"), Selector(("saveImage")), "s"))
        file.addItem(item(t("Save As…"), Selector(("saveImageAs")), "s", shift))
        file.addItem(item(t("Upload"), Selector(("uploadImage")), "e"))
        file.addItem(item(t("Pin"), Selector(("pinImage")), "p"))
        file.addItem(item(t("Print…"), Selector(("printImage")), "p", shift))
        file.addItem(.separator())
        file.addItem(item(t("Close"), #selector(NSWindow.performClose(_:)), "w"))

        let edit = NSMenu(title: t("Edit"))
        edit.addItem(item(t("Undo"), Selector(("undoAnnotation")), "z"))
        edit.addItem(item(t("Redo"), Selector(("redoAnnotation")), "z", shift))
        edit.addItem(.separator())
        edit.addItem(item(t("Copy"), Selector(("copyCommand")), "c"))
        edit.addItem(item(t("Copy image"), Selector(("copyImage")), "c", shift))
        edit.addItem(item(t("Paste"), Selector(("pasteCommand")), "v"))
        edit.addItem(item(t("Select All"), #selector(NSText.selectAll(_:)), "a"))
        edit.addItem(.separator())
        edit.addItem(item(t("Hide PII"), Selector(("hidePII")), "h", shift))
        edit.addItem(item(t("Recognize text (OCR)"), Selector(("runOCR")), "t", shift))
        edit.addItem(item(t("Merge marks into image"), Selector(("rasterize")), "r", shift))
        edit.addItem(item(t("Add capture"), Selector(("addCapture")), "a", [.command, .option]))

        let draw = NSMenu(title: t("Draw"))
        for entry in EditorWindowController.toolMenuEntries {
            let m = NSMenuItem(title: entry.title, action: Selector(("selectToolFromMenu:")), keyEquivalent: "")
            m.tag = entry.tag
            draw.addItem(m)
        }
        draw.addItem(.separator())
        draw.addItem(item(t("Hand-drawn Style"), Selector(("toggleHandDrawn")), "r"))
        draw.addItem(item(t("Snap to Objects"), Selector(("toggleSnap")), "s", [.command, .option]))

        let zoom = NSMenu(title: t("Zoom"))
        zoom.addItem(item(t("Zoom In"), Selector(("zoomIn")), "+"))
        zoom.addItem(item(t("Zoom Out"), Selector(("zoomOut")), "-"))
        zoom.addItem(item(t("Fit to Window"), Selector(("zoomFit")), "1"))
        zoom.addItem(item(t("Actual Size"), Selector(("zoomActual")), "0"))
        zoom.addItem(item(t("Zoom to Selection"), Selector(("zoomToSelection")), "2"))

        let windowMenu = NSMenu(title: t("Window"))
        windowMenu.addItem(item(t("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        windowMenu.addItem(item(t("Zoom"), #selector(NSWindow.performZoom(_:))))

        let help = NSMenu(title: t("Help"))
        help.addItem(item(t("Keyboard Shortcuts"), #selector(showShortcuts), "/", [.command, .shift], target: self))

        for submenu in [appMenu, file, edit, draw, zoom, windowMenu, help] {
            let holder = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            holder.submenu = submenu
            main.addItem(holder)
        }
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = help
    }

    @objc private func showAbout() { AboutWindowController.shared.show() }
    @objc private func showLicense() { LicenseWindowController.shared.show() }
    @objc private func showUploads() { UploadsWindowController.shared.show() }
    @objc private func showShortcuts() { ShortcutsWindowController.shared.show() }

    private func shifted(_ item: NSMenuItem) -> NSMenuItem {
        item.keyEquivalentModifierMask = [.command, .shift]
        return item
    }
}
