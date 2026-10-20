import AppKit
import SwiftUI

struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    var open: (LibraryItem) -> Void
    @StateObject private var query = Box("")
    private let columns = [GridItem(.adaptive(minimum: 190), spacing: 14)]

    var body: some View {
        let shown = store.search(query.value)
        VStack(spacing: 0) {
            TextField(t("Search screenshots by text, date…"), text: $query.value)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            Divider()
            if shown.isEmpty {
                Spacer()
                Text(store.items.isEmpty ? t("No screenshots yet") : t("No matches")).foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(shown) { item in LibraryTile(item: item, store: store, open: open) }
                    }
                    .padding(14)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 460)
    }
}

private struct LibraryTile: View {
    let item: LibraryItem
    let store: LibraryStore
    var open: (LibraryItem) -> Void
    @StateObject private var thumb = Box<NSImage?>(nil)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12))
                if let image = thumb.value { Image(nsImage: image).resizable().scaledToFit().padding(4) }
            }
            .frame(height: 130)
            Text(Self.dateText(item.date)).font(.caption).foregroundStyle(.secondary)
            if !item.ocrText.isEmpty {
                Text(item.ocrText.replacingOccurrences(of: "\n", with: " "))
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open(item) }
        .contextMenu {
            Button(t("Open in editor")) { open(item) }
            Button(t("Copy")) { copy() }
            Button(t("Reveal in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([store.url(for: item)]) }
            Divider()
            Button(t("Delete"), role: .destructive) { store.remove(item.id) }
        }
        .task {
            let url = store.url(for: item)
            let image = await Task.detached { LibraryStore.thumbnail(at: url, maxPixel: 420) }.value
            if let image { thumb.value = NSImage(cgImage: image, size: NSSize(width: image.width / 2, height: image.height / 2)) }
        }
    }

    static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        let thai = Settings.shared.language == .th
        f.locale = Locale(identifier: thai ? "th_TH" : "en_US")
        f.calendar = thai ? Calendar(identifier: .buddhist) : Calendar(identifier: .gregorian)
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func copy() {
        guard let image = NSImage(contentsOf: store.url(for: item)) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}

@MainActor
public final class LibraryWindowController {
    public static let shared = LibraryWindowController()
    private var window: NSWindow?

    public func show(store: LibraryStore = .shared, open: @escaping (LibraryItem) -> Void) {
        if window == nil {
            let controller = NSHostingController(rootView: LibraryView(store: store, open: open))
            let w = NSWindow(contentViewController: controller)
            w.title = "Tenix-ChaeDiew — \(t("Library"))"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = Brand.ink
            w.setContentSize(NSSize(width: 820, height: 560))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
