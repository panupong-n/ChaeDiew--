import Combine
import Foundation
import ImageIO

public struct LibraryItem: Codable, Identifiable, Equatable {
    public var id: UUID
    public var fileName: String
    public var date: Date
    public var width: Int
    public var height: Int
    public var pixelScale: Double
    /// Text found by OCR, so screenshots can be searched by what they show.
    public var ocrText: String
}

/// History of captures with full-text search. Stored under Application Support, not in the user's
/// visible folders, and purged after a configurable retention period.
public final class LibraryStore: ObservableObject {
    public static let shared = LibraryStore(folder: LibraryStore.defaultFolder)

    @Published public private(set) var items: [LibraryItem] = []
    public let folder: URL
    private var indexURL: URL { folder.appendingPathComponent("index.json") }

    public static var defaultFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Tenix-ChaeDiew/Library", isDirectory: true)
    }

    public init(folder: URL) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder.library.decode([LibraryItem].self, from: data) {
            items = decoded.sorted { $0.date > $1.date }
        }
    }

    public func url(for item: LibraryItem) -> URL { folder.appendingPathComponent(item.fileName) }

    @discardableResult
    public func add(image: CGImage, pixelScale: CGFloat, date: Date = Date()) -> LibraryItem? {
        guard let png = Storage.pngData(from: image) else { return nil }
        let id = UUID()
        let item = LibraryItem(
            id: id, fileName: "\(id.uuidString).png", date: date, width: image.width, height: image.height,
            pixelScale: Double(pixelScale), ocrText: "")
        do { try png.write(to: url(for: item), options: .atomic) } catch { return nil }
        items.insert(item, at: 0)
        persist()
        return item
    }

    public func setOCRText(_ text: String, for id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].ocrText = text
        persist()
    }

    public func remove(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: url(for: items[i]))
        items.remove(at: i)
        persist()
    }

    public func removeAll() {
        for item in items { try? FileManager.default.removeItem(at: url(for: item)) }
        items = []
        persist()
    }

    /// Deletes items older than `days` (0 keeps everything). Returns how many were removed.
    @discardableResult
    public func purge(olderThanDays days: Int, now: Date = Date()) -> Int {
        guard days > 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let old = items.filter { $0.date < cutoff }
        old.forEach { remove($0.id) }
        return old.count
    }

    /// Every whitespace-separated term must appear in the OCR text, file name or date (yyyy-MM-dd).
    public func search(_ query: String) -> [LibraryItem] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return items }
        return items.filter { item in
            let haystack = (item.ocrText + " " + item.fileName + " " + Self.day(item.date)).lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func persist() {
        guard let data = try? JSONEncoder.library.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    public static func thumbnail(at url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

private extension JSONEncoder {
    static var library: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

private extension JSONDecoder {
    static var library: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
