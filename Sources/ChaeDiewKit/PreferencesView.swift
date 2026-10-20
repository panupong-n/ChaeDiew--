import AppKit
import Carbon
import ServiceManagement
import SwiftUI

@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Toast.show("Launch at login: \(error.localizedDescription)", duration: 4)
        }
    }
}

struct PreferencesView: View {
    /// Which tab opens first (0 General … 4 Upload); the UI tour uses it to photograph every tab.
    nonisolated(unsafe) static var initialTab = 0
    @StateObject private var tab = Box(PreferencesView.initialTab)

    var body: some View {
        TabView(selection: $tab.value) {
            GeneralTab().tabItem { Label(t("General"), systemImage: "gearshape") }.tag(0)
            HotkeysTab().tabItem { Label(t("Hotkeys"), systemImage: "keyboard") }.tag(1)
            CaptureTab().tabItem { Label(t("Capture"), systemImage: "viewfinder") }.tag(2)
            PrivacyTab().tabItem { Label(t("Privacy"), systemImage: "hand.raised") }.tag(3)
            UploadTab().tabItem { Label(t("Upload"), systemImage: "icloud.and.arrow.up") }.tag(4)
            LicenseTab().tabItem { Label(t("License"), systemImage: "checkmark.seal") }.tag(5)
        }
        .frame(width: 600, height: 600)
        .tint(Color(nsColor: Brand.accent))
    }
}

// MARK: - General

private struct GeneralTab: View {
    @AppStorage(Settings.Key.language) private var language = "en"
    @AppStorage(Settings.Key.imageFormat) private var format = "png"
    @AppStorage(Settings.Key.jpegQuality) private var quality = 0.9
    @AppStorage(Settings.Key.afterCapture) private var afterCapture = "editor"
    @AppStorage(Settings.Key.escBehavior) private var esc = "close"
    @AppStorage(Settings.Key.libraryEnabled) private var libraryEnabled = true
    @AppStorage(Settings.Key.libraryRetentionDays) private var retention = 30
    @AppStorage(Settings.Key.saveFolder) private var saveFolder = ""
    @AppStorage(Settings.Key.autoFormat) private var autoFormat = false
    @AppStorage(Settings.Key.downscaleRetina) private var downscale = false
    @AppStorage(Settings.Key.urlSchemeEnabled) private var urlScheme = false
    @AppStorage(Settings.Key.hideMenuBarIcon) private var hideIcon = false
    @StateObject private var launch = Box(LaunchAtLogin.isEnabled)

    var body: some View {
        Form {
            Picker(t("Language"), selection: $language) {
                Text("English").tag("en")
                Text("ไทย").tag("th")
            }
            .onChange(of: language) { _, _ in NotificationCenter.default.post(name: .chaeDiewLanguageChanged, object: nil) }

            HStack {
                Text(t("Save folder"))
                Spacer()
                Text(saveFolder.isEmpty ? Settings.shared.saveFolder.path : saveFolder)
                    .lineLimit(1).truncationMode(.head).foregroundStyle(.secondary)
                Button(t("Choose…")) { chooseFolder() }
            }
            Picker(t("Format"), selection: $format) {
                Text("PNG").tag("png")
                Text("JPEG").tag("jpeg")
            }
            .disabled(autoFormat)
            Toggle(t("Pick PNG or JPEG automatically"), isOn: $autoFormat)
            Toggle(t("Scale Retina screenshots down to 1× when saving"), isOn: $downscale)
            if format == "jpeg" || autoFormat {
                HStack {
                    Text(t("JPEG quality"))
                    Slider(value: $quality, in: 0.3...1)
                    Text("\(Int(quality * 100))%").monospacedDigit().frame(width: 44)
                }
            }
            Picker(t("After capture"), selection: $afterCapture) {
                Text(t("Open editor")).tag("editor")
                Text(t("Copy to clipboard")).tag("copy")
                Text(t("Save to file")).tag("save")
                Text(t("Copy and save")).tag("copySave")
                Text(t("Show thumbnail")).tag("thumbnail")
            }
            Picker(t("Esc in editor"), selection: $esc) {
                Text(t("Just close")).tag("close")
                Text(t("Copy, then close")).tag("copyClose")
                Text(t("Save, then close")).tag("saveClose")
            }
            Toggle(t("Enable the chaediew:// URL scheme"), isOn: $urlScheme)
            if urlScheme {
                Text("chaediew://grab/area?then=copy,save · grab/fullscreen · grab/window · grab/scrolling · grab/delayed=5 · ocr · load/clipboard · show · settings")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle(t("Hide the menu-bar icon"), isOn: $hideIcon)
                .onChange(of: hideIcon) { _, _ in NotificationCenter.default.post(name: .chaeDiewHotKeysChanged, object: nil) }
            if hideIcon {
                Text(t("Hotkeys still work. Open Tenix-ChaeDiew again from Finder or Spotlight to get back to Preferences."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle(t("Launch at login"), isOn: $launch.value)
                .onChange(of: launch.value) { _, on in LaunchAtLogin.set(on) }

            Section(t("Library")) {
                Toggle(t("Keep capture history"), isOn: $libraryEnabled)
                Stepper(value: $retention, in: 0...365) {
                    Text("\(t("Delete history after (days, 0 = never)")): \(retention)")
                }
                Button(t("Clear history now")) { LibraryStore.shared.removeAll() }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { saveFolder = url.path }
    }
}

// MARK: - Hotkeys

private struct HotkeysTab: View {
    var body: some View {
        Form {
            Section {
                ForEach(HotKeyAction.allCases, id: \.rawValue) { HotKeyRow(action: $0) }
            } footer: {
                Text(t("Click a shortcut, then press the new keys. Include ⌃, ⌥ or ⌘."))
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
private final class HotKeyRowModel: ObservableObject {
    let action: HotKeyAction
    @Published var spec: HotKeySpec?
    @Published var recording = false
    private var monitor: Any?

    init(action: HotKeyAction) {
        self.action = action
        self.spec = Settings.shared.hotKey(for: action)
    }

    func reset() {
        Settings.shared.resetHotKey(for: action)
        spec = Settings.shared.hotKey(for: action)
    }

    func toggle() {
        if recording { stop(); return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handle(event) }
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { stop(); return nil }  // Esc cancels
        let mods = HotKeySpec.carbonModifiers(from: event.modifierFlags)
        guard mods & (controlKey | optionKey | cmdKey) != 0 else { NSSound.beep(); return nil }
        let new = HotKeySpec(keyCode: Int(event.keyCode), modifiers: mods)
        Settings.shared.setHotKey(new, for: action)
        spec = new
        stop()
        return nil
    }

    func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct HotKeyRow: View {
    @StateObject private var model: HotKeyRowModel

    init(action: HotKeyAction) { _model = StateObject(wrappedValue: HotKeyRowModel(action: action)) }

    var body: some View {
        HStack {
            Text(model.action.title)
            Spacer()
            Button(model.recording ? t("Press keys…") : (model.spec?.display ?? t("None"))) { model.toggle() }
                .frame(minWidth: 120)
            Button(t("Reset")) { model.reset() }
        }
        .onDisappear { model.stop() }
    }
}

// MARK: - Capture

private struct CaptureTab: View {
    @AppStorage(Settings.Key.scrollMode) private var scrollMode = "auto"
    @AppStorage(Settings.Key.windowShadow) private var shadow = false
    @AppStorage(Settings.Key.ocrLanguages) private var ocrLanguages = "auto"
    @AppStorage(Settings.Key.ocrRemoveBreaks) private var removeBreaks = false
    @AppStorage(Settings.Key.colorFormat) private var colorFormat = "hex"
    @AppStorage(Settings.Key.scrollMaxHeight) private var scrollMax = 20_000
    @AppStorage(Settings.Key.scrollSpeed) private var scrollSpeed = 1.0
    @AppStorage(Settings.Key.scrollReverse) private var scrollReverse = false
    @AppStorage(Settings.Key.windowBackground) private var windowBackground = "transparent"

    var body: some View {
        Form {
            Section(t("Scrolling capture")) {
                Picker(t("Scrolling capture"), selection: $scrollMode) {
                    Text(t("Auto-scroll")).tag("auto")
                    Text(t("Manual")).tag("manual")
                }
                Stepper(value: $scrollMax, in: 1_000...200_000, step: 1_000) {
                    Text("\(t("Maximum height (px)")): \(scrollMax)")
                }
                HStack {
                    Text(t("Scroll speed"))
                    Slider(value: $scrollSpeed, in: 0.5...2)
                    Text(String(format: "%.1f×", scrollSpeed)).monospacedDigit().frame(width: 44)
                }
                Toggle(t("Reverse scroll direction"), isOn: $scrollReverse)
            }
            Section(t("Window screenshots")) {
                Toggle(t("Include window shadow"), isOn: $shadow)
                Picker(t("Background"), selection: $windowBackground) {
                    Text(t("Transparent")).tag("transparent")
                    Text(t("White")).tag("white")
                    Text(t("Black")).tag("black")
                    Text(t("Light gray")).tag("lightGray")
                    Text(t("Dark gray")).tag("darkGray")
                    Text(t("Desktop wallpaper")).tag("wallpaper")
                }
            }
            Section("OCR") {
                Picker(t("Text recognition language"), selection: $ocrLanguages) {
                    Text(t("Automatic")).tag("auto")
                    Text(t("English")).tag("en-US")
                    Text(t("Thai")).tag("th-TH")
                    Text(t("Thai + English")).tag("th-TH,en-US")
                }
                Toggle(t("Join lines when copying OCR text"), isOn: $removeBreaks)
            }
            Section(t("Pick Color")) {
                Picker(t("Color format"), selection: $colorFormat) {
                    Text("HEX  #FF8000").tag("hex")
                    Text("RGB  rgb(255, 128, 0)").tag("rgb")
                    Text("HSL  hsl(30, 100%, 50%)").tag("hsl")
                    Text("OKLCH  oklch(75.1% 0.172 59.7)").tag("oklch")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Privacy

private struct PrivacyTab: View {
    @AppStorage(Settings.Key.redactIDs) private var enabled = ""
    @AppStorage(Settings.Key.redactCustom) private var custom = ""

    var body: some View {
        Form {
            Section(t("Hide PII automatically")) {
                ForEach(Redactor.builtins, id: \.id) { pattern in
                    Toggle(t(pattern.name), isOn: binding(for: pattern.id))
                }
            }
            Section(t("Extra patterns (regular expressions, one per line)")) {
                TextEditor(text: $custom)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 80)
            }
            Section {
                Text(t("Everything runs on this Mac. Tenix-ChaeDiew sends nothing anywhere except uploads you configure yourself."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { Set(enabled.split(separator: ",").map(String.init)).contains(id) },
            set: { on in
                var ids = Set(enabled.split(separator: ",").map(String.init))
                if on { ids.insert(id) } else { ids.remove(id) }
                enabled = Redactor.builtins.map(\.id).filter { ids.contains($0) }.joined(separator: ",")
            })
    }
}

// MARK: - Upload

private struct UploadTab: View {
    @AppStorage(Settings.Key.uploadMode) private var mode = "none"
    @AppStorage(Settings.Key.s3Endpoint) private var endpoint = ""
    @AppStorage(Settings.Key.s3Region) private var region = "us-east-1"
    @AppStorage(Settings.Key.s3Bucket) private var bucket = ""
    @AppStorage(Settings.Key.s3Prefix) private var prefix = ""
    @AppStorage(Settings.Key.s3AccessKey) private var accessKey = ""
    @AppStorage(Settings.Key.s3PublicBase) private var publicBase = ""
    @AppStorage(Settings.Key.s3ExpirySeconds) private var expiry = 3600
    @AppStorage(Settings.Key.httpURL) private var httpURL = ""
    @StateObject private var secret = Box("")
    @StateObject private var token = Box("")
    @StateObject private var result = Box("")
    @StateObject private var testing = Box(false)

    var body: some View {
        Form {
            Picker(t("Upload method"), selection: $mode) {
                Text(t("Off")).tag("none")
                Text(t("S3-compatible storage")).tag("s3")
                Text(t("Custom HTTP endpoint")).tag("http")
            }
            if mode == "s3" {
                TextField(t("Endpoint (blank = AWS)"), text: $endpoint, prompt: Text("https://minio.example.com:9000"))
                TextField(t("Region"), text: $region)
                TextField(t("Bucket"), text: $bucket)
                TextField(t("Folder prefix"), text: $prefix)
                TextField(t("Access key"), text: $accessKey)
                SecureField(t("Secret key (stored in Keychain)"), text: $secret.value)
                    .onChange(of: secret.value) { _, v in Keychain.set(v, account: Keychain.s3SecretAccount) }
                TextField(t("Public base URL (optional)"), text: $publicBase)
                Stepper(value: $expiry, in: 60...604_800, step: 600) { Text("\(t("Link lifetime (seconds)")): \(expiry)") }
            }
            if mode == "http" {
                TextField(t("URL"), text: $httpURL, prompt: Text("https://files.example.com/upload"))
                SecureField(t("Bearer token (stored in Keychain)"), text: $token.value)
                    .onChange(of: token.value) { _, v in Keychain.set(v, account: Keychain.httpTokenAccount) }
                Text("POST multipart/form-data, field “file”. Reply: JSON {\"url\": …} or the URL as plain text.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if mode != "none" {
                HStack {
                    Button(t("Test upload")) { test() }.disabled(testing.value)
                    Text(result.value).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            secret.value = Keychain.get(account: Keychain.s3SecretAccount) ?? ""
            token.value = Keychain.get(account: Keychain.httpTokenAccount) ?? ""
        }
    }

    private func test() {
        testing.value = true
        result.value = t("Uploading…")
        let pixel = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)?.makeImage()
        guard let image = pixel, let data = Storage.pngData(from: image) else { testing.value = false; return }
        Task { @MainActor in
            defer { testing.value = false }
            do {
                let link = try await Uploader.upload(data, fileName: "chaediew-test.png", contentType: "image/png")
                result.value = String(format: t("Upload works: %@"), link.absoluteString)
            } catch {
                result.value = "\(t("Upload failed")): \(error.localizedDescription)"
            }
        }
    }
}

@MainActor
public final class PreferencesWindowController {
    public static let shared = PreferencesWindowController()
    private var window: NSWindow?

    public func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView()))
            w.title = "Tenix-ChaeDiew — \(t("Preferences…").replacingOccurrences(of: "…", with: ""))"
            w.styleMask = [.titled, .closable]
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = Brand.ink
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Rebuilds the window so a language change takes effect immediately.
    public func reset() {
        let wasVisible = window?.isVisible == true
        window?.close()
        window = nil
        if wasVisible { show() }
    }
}
