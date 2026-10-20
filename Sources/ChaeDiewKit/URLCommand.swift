import Foundation

/// What to do with a finished capture, in order. Used by `chaediew://grab/…?then=copy,save`.
public enum ThenAction: String, CaseIterable {
    case copy, save, edit, pin, thumbnail
}

/// A command received through the `chaediew://` URL scheme (only honoured when enabled in Preferences).
public enum URLCommand: Equatable {
    case grab(CaptureCoordinator.Mode, delay: Int, then: [ThenAction])
    case addCapture
    case ocr
    case qr
    case pickColor
    case loadClipboard
    case loadFile(URL)
    case showLibrary
    case settings

    /// Parses `chaediew://<command>/<sub>?then=a,b`. Returns nil for anything unrecognised.
    public static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == "chaediew" else { return nil }
        var parts = [url.host ?? ""] + url.path.split(separator: "/").map(String.init)
        parts = parts.filter { !$0.isEmpty }.map { $0.lowercased() }
        guard let command = parts.first else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let then = (value("then") ?? "").split(separator: ",").compactMap { ThenAction(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }
        let sub = parts.count > 1 ? parts[1] : ""

        switch command {
        case "grab":
            if sub.hasPrefix("delayed") {
                let seconds = sub.split(separator: "=").last.flatMap { Int($0) } ?? 5
                return .grab(.area, delay: min(60, max(1, seconds)), then: then)
            }
            switch sub {
            case "area": return .grab(.area, delay: 0, then: then)
            case "fullscreen": return .grab(.fullscreen, delay: 0, then: then)
            case "window": return .grab(.window, delay: 0, then: then)
            case "repeat": return .grab(.repeatLast, delay: 0, then: then)
            case "scrolling": return .grab(.scrolling, delay: 0, then: then)
            case "append": return .addCapture
            default: return nil
            }
        case "ocr": return .ocr
        case "qr": return .qr
        case "color", "colour": return .pickColor
        case "load":
            if sub == "clipboard" { return .loadClipboard }
            if sub == "file", let path = value("path") ?? value("file"), path.hasPrefix("/") {
                return .loadFile(URL(fileURLWithPath: path))
            }
            return nil
        case "show", "library": return .showLibrary
        case "settings", "preferences": return .settings
        default: return nil
        }
    }
}
