import AppKit
import SwiftUI

public struct UploadRecord: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var url: String
    public var name: String
    public var date: Date
}

/// Links of everything uploaded from this app, newest first (stored locally, capped at 200).
public final class UploadHistory {
    public static let shared = UploadHistory(defaults: .standard)
    private let defaults: UserDefaults
    private let key = "uploadHistory"

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public var records: [UploadRecord] {
        guard let data = defaults.data(forKey: key), let list = try? JSONDecoder().decode([UploadRecord].self, from: data) else { return [] }
        return list
    }

    private func store(_ list: [UploadRecord]) {
        if let data = try? JSONEncoder().encode(Array(list.prefix(200))) { defaults.set(data, forKey: key) }
    }

    public func add(url: URL, name: String, date: Date = Date()) {
        store([UploadRecord(url: url.absoluteString, name: name, date: date)] + records)
    }

    /// Dates follow the app language (Buddhist year in Thai, Gregorian in English), never the system calendar by accident.
    static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        let thai = Settings.shared.language == .th
        f.locale = Locale(identifier: thai ? "th_TH" : "en_US")
        f.calendar = thai ? Calendar(identifier: .buddhist) : Calendar(identifier: .gregorian)
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    public func remove(_ id: UUID) { store(records.filter { $0.id != id }) }
    public func removeAll() { defaults.removeObject(forKey: key) }
}

private struct UploadsView: View {
    @StateObject private var list = Box(UploadHistory.shared.records)

    var body: some View {
        VStack(spacing: 0) {
            if list.value.isEmpty {
                Text(t("No uploads yet")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(list.value) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.name).lineLimit(1)
                            Text(record.url).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            Text(UploadHistory.dateText(record.date)).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button(t("Copy link")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(record.url, forType: .string)
                            Toast.show(t("Link copied"), duration: 1.5)
                        }
                        Button(t("Open")) { if let url = URL(string: record.url) { NSWorkspace.shared.open(url) } }
                        Button(role: .destructive) {
                            UploadHistory.shared.remove(record.id)
                            list.value = UploadHistory.shared.records
                        } label: { Image(systemName: "trash") }
                        .help(t("Remove from this list (the file stays on the server)"))
                    }
                }
            }
            Divider()
            HStack {
                Text(t("Links come from your own storage. Presigned links stop working when they expire."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(t("Clear list")) { UploadHistory.shared.removeAll(); list.value = [] }.disabled(list.value.isEmpty)
            }
            .padding(10)
        }
        .frame(minWidth: 640, minHeight: 360)
        .tint(Color(nsColor: Brand.accent))
    }
}

@MainActor
public final class UploadsWindowController {
    public static let shared = UploadsWindowController()
    private var window: NSWindow?

    public func show() {
        window?.close()  // rebuilt every time so the list is fresh
        let w = NSWindow(contentViewController: NSHostingController(rootView: UploadsView()))
        w.title = "Tenix-ChaeDiew — " + t("Uploaded Screenshots")
        w.styleMask = [.titled, .closable, .resizable]
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = Brand.ink
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    public func reset() { window?.close(); window = nil }
}
