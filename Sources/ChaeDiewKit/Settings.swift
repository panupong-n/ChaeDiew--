import AppKit
import Carbon

public extension Notification.Name {
    static let chaeDiewHotKeysChanged = Notification.Name("ChaeDiewHotKeysChanged")
    static let chaeDiewLanguageChanged = Notification.Name("Tenix-ChaeDiewLanguageChanged")
}

public enum Lang: String, CaseIterable {
    case en, th
}

public enum AfterCapture: String, CaseIterable {
    case editor, copy, save, copySave, thumbnail
}

/// What sits behind a window screenshot (its corners and shadow are transparent by default).
public enum WindowBackground: String, CaseIterable {
    case transparent, white, black, lightGray, darkGray, wallpaper
    public var rgb: (r: UInt8, g: UInt8, b: UInt8)? {
        switch self {
        case .transparent, .wallpaper: return nil
        case .white: return (255, 255, 255)
        case .black: return (0, 0, 0)
        case .lightGray: return (232, 232, 232)
        case .darkGray: return (52, 52, 54)
        }
    }
}

public enum ImageFormat: String, CaseIterable {
    case png, jpeg
    public var fileExtension: String { self == .png ? "png" : "jpg" }
}

// MARK: - Hotkeys

public struct HotKeySpec: Equatable {
    public var keyCode: Int
    /// Carbon modifier mask (controlKey | shiftKey | optionKey | cmdKey).
    public var modifiers: Int

    public init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init?(stored: String) {
        let parts = stored.split(separator: ",").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        self.init(keyCode: parts[0], modifiers: parts[1])
    }

    public var stored: String { "\(keyCode),\(modifiers)" }

    public var display: String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + (Self.keyNames[keyCode] ?? "key\(keyCode)")
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.command) { m |= cmdKey }
        return m
    }

    static let keyNames: [Int: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C",
        0x09: "V", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T",
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9", 0x1A: "7",
        0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
        0x24: "↩", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/",
        0x2D: "N", 0x2E: "M", 0x2F: ".", 0x30: "⇥", 0x31: "Space", 0x32: "`", 0x33: "⌫",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
    ]
}

public enum HotKeyAction: String, CaseIterable {
    case area, fullscreen, window, scrolling, ocr, qr, repeatLast, colorPicker, library

    public var title: String {
        switch self {
        case .area: return t("Capture Area")
        case .fullscreen: return t("Capture Full Screen")
        case .window: return t("Capture Window")
        case .scrolling: return t("Scrolling Capture")
        case .ocr: return t("OCR Area → Clipboard")
        case .qr: return t("Scan QR / Barcode")
        case .repeatLast: return t("Repeat Last Area")
        case .colorPicker: return t("Pick Color")
        case .library: return t("Open Library")
        }
    }

    public var defaultSpec: HotKeySpec {
        let m = controlKey | shiftKey
        switch self {
        case .area: return HotKeySpec(keyCode: kVK_ANSI_4, modifiers: m)
        case .fullscreen: return HotKeySpec(keyCode: kVK_ANSI_3, modifiers: m)
        case .window: return HotKeySpec(keyCode: kVK_ANSI_5, modifiers: m)
        case .scrolling: return HotKeySpec(keyCode: kVK_ANSI_6, modifiers: m)
        case .ocr: return HotKeySpec(keyCode: kVK_ANSI_2, modifiers: m)
        case .qr: return HotKeySpec(keyCode: kVK_ANSI_8, modifiers: m)
        case .repeatLast: return HotKeySpec(keyCode: kVK_ANSI_7, modifiers: m)
        case .colorPicker: return HotKeySpec(keyCode: kVK_ANSI_1, modifiers: m)
        case .library: return HotKeySpec(keyCode: kVK_ANSI_9, modifiers: m)
        }
    }
}

// MARK: - Settings

public final class Settings {
    public static let shared = Settings(defaults: .standard)

    public let defaults: UserDefaults

    public enum Key {
        public static let language = "language"
        public static let saveFolder = "saveFolder"
        public static let imageFormat = "imageFormat"
        public static let jpegQuality = "jpegQuality"
        public static let afterCapture = "afterCapture"
        public static let libraryEnabled = "libraryEnabled"
        public static let libraryRetentionDays = "libraryRetentionDays"
        public static let ocrLanguages = "ocrLanguages"
        public static let ocrRemoveBreaks = "ocrRemoveBreaks"
        public static let colorFormat = "colorFormat"
        public static let scrollMode = "scrollMode"
        public static let windowShadow = "windowShadow"
        public static let redactIDs = "redactIDs"
        public static let redactCustom = "redactCustom"
        public static let uploadMode = "uploadMode"
        public static let s3Endpoint = "s3Endpoint"
        public static let s3Region = "s3Region"
        public static let s3Bucket = "s3Bucket"
        public static let s3Prefix = "s3Prefix"
        public static let s3AccessKey = "s3AccessKey"
        public static let s3PublicBase = "s3PublicBase"
        public static let s3ExpirySeconds = "s3ExpirySeconds"
        public static let httpURL = "httpURL"
        public static let escBehavior = "escBehavior"
        public static let autoFormat = "autoFormat"
        public static let downscaleRetina = "downscaleRetina"
        public static let windowBackground = "windowBackground"
        public static let scrollMaxHeight = "scrollMaxHeight"
        public static let scrollSpeed = "scrollSpeed"
        public static let scrollReverse = "scrollReverse"
        public static let urlSchemeEnabled = "urlSchemeEnabled"
        public static let snapToObjects = "snapToObjects"
        public static let hideMenuBarIcon = "hideMenuBarIcon"
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        let systemThai = Locale.preferredLanguages.first?.hasPrefix("th") == true
        defaults.register(defaults: [
            Key.language: systemThai ? "th" : "en",
            Key.imageFormat: "png",
            Key.jpegQuality: 0.9,
            Key.afterCapture: "editor",
            Key.libraryEnabled: true,
            Key.libraryRetentionDays: 30,
            Key.ocrLanguages: "auto",
            Key.ocrRemoveBreaks: false,
            Key.colorFormat: "hex",
            Key.scrollMode: "auto",
            Key.windowShadow: false,
            Key.redactIDs: Redactor.builtins.map(\.id).joined(separator: ","),
            Key.redactCustom: "",
            Key.uploadMode: "none",
            Key.s3Region: "us-east-1",
            Key.s3ExpirySeconds: 3600,
            Key.escBehavior: "close",
            Key.autoFormat: false,
            Key.downscaleRetina: false,
            Key.windowBackground: "transparent",
            Key.scrollMaxHeight: 20_000,
            Key.scrollSpeed: 1.0,
            Key.scrollReverse: false,
            Key.urlSchemeEnabled: false,
            Key.snapToObjects: true,
            Key.hideMenuBarIcon: false,
        ])
    }

    private func string(_ key: String) -> String { defaults.string(forKey: key) ?? "" }

    /// In-memory override (used by the UI smoke run) so previews never touch saved preferences.
    public static var languageOverride: Lang?

    public var language: Lang {
        get { Self.languageOverride ?? Lang(rawValue: string(Key.language)) ?? .en }
        set { defaults.set(newValue.rawValue, forKey: Key.language) }
    }

    public var saveFolder: URL {
        get {
            let path = string(Key.saveFolder)
            return path.isEmpty ? Storage.defaultFolder() : URL(fileURLWithPath: path, isDirectory: true)
        }
        set { defaults.set(newValue.path, forKey: Key.saveFolder) }
    }

    public var imageFormat: ImageFormat { ImageFormat(rawValue: string(Key.imageFormat)) ?? .png }
    public var jpegQuality: Double { min(1, max(0.1, defaults.double(forKey: Key.jpegQuality))) }
    public var afterCapture: AfterCapture { AfterCapture(rawValue: string(Key.afterCapture)) ?? .editor }
    public var libraryEnabled: Bool { defaults.bool(forKey: Key.libraryEnabled) }
    public var libraryRetentionDays: Int { defaults.integer(forKey: Key.libraryRetentionDays) }
    public var ocrRemoveBreaks: Bool { defaults.bool(forKey: Key.ocrRemoveBreaks) }
    public var colorFormat: ColorFormat { ColorFormat(rawValue: string(Key.colorFormat)) ?? .hex }
    public var autoScroll: Bool { string(Key.scrollMode) != "manual" }
    public var windowShadow: Bool { defaults.bool(forKey: Key.windowShadow) }
    public var escBehavior: String { string(Key.escBehavior) }
    /// Pick PNG for interface screenshots and JPEG for photographic ones when saving.
    public var autoFormat: Bool { defaults.bool(forKey: Key.autoFormat) }
    /// Scale Retina screenshots down to 1× when saving or uploading.
    public var downscaleRetina: Bool { defaults.bool(forKey: Key.downscaleRetina) }
    public var windowBackground: WindowBackground { WindowBackground(rawValue: string(Key.windowBackground)) ?? .transparent }
    public var scrollMaxHeight: Int { min(200_000, max(1_000, defaults.integer(forKey: Key.scrollMaxHeight))) }
    /// 0.5…2: scales the scroll step and shortens/lengthens the wait between steps.
    public var scrollSpeed: Double { min(2, max(0.5, defaults.double(forKey: Key.scrollSpeed))) }
    public var scrollReverse: Bool { defaults.bool(forKey: Key.scrollReverse) }
    public var snapToObjects: Bool {
        get { defaults.bool(forKey: Key.snapToObjects) }
        set { defaults.set(newValue, forKey: Key.snapToObjects) }
    }
    public var hideMenuBarIcon: Bool { defaults.bool(forKey: Key.hideMenuBarIcon) }
    public var urlSchemeEnabled: Bool { defaults.bool(forKey: Key.urlSchemeEnabled) }

    /// BCP-47 codes for Vision; empty means automatic detection.
    public var ocrLanguageList: [String] {
        let value = string(Key.ocrLanguages)
        return value == "auto" || value.isEmpty ? [] : value.split(separator: ",").map(String.init)
    }

    public var enabledRedactionIDs: Set<String> {
        Set(string(Key.redactIDs).split(separator: ",").map(String.init))
    }

    public var customRedactionPatterns: [String] {
        string(Key.redactCustom).split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public func hotKey(for action: HotKeyAction) -> HotKeySpec? {
        let stored = defaults.string(forKey: "hotkey.\(action.rawValue)")
        if stored == "off" { return nil }
        return stored.flatMap(HotKeySpec.init(stored:)) ?? action.defaultSpec
    }

    public func setHotKey(_ spec: HotKeySpec?, for action: HotKeyAction) {
        defaults.set(spec?.stored ?? "off", forKey: "hotkey.\(action.rawValue)")
        NotificationCenter.default.post(name: .chaeDiewHotKeysChanged, object: nil)
    }

    public func resetHotKey(for action: HotKeyAction) {
        defaults.removeObject(forKey: "hotkey.\(action.rawValue)")
        NotificationCenter.default.post(name: .chaeDiewHotKeysChanged, object: nil)
    }
}
