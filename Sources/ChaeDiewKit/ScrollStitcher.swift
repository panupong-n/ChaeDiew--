import CoreGraphics
import Foundation

/// Joins successive frames of a scrolling region into one tall image.
/// Pure image processing: no screen access, so it is fully unit-testable.
public final class ScrollStitcher {
    public enum Shift: Equatable {
        case none            // frame identical to the previous one
        case scrolled(Int)   // content moved up by n rows (n < 0: moved down)
        case unknown         // no confident alignment (mid-animation, too fast, unrelated)
    }

    public enum AddResult: Equatable {
        case first
        case appended(rows: Int)
        case prepended(rows: Int)
        case noChange
        case unmatched
        case limitReached
    }

    private var strips: [CGImage] = []
    private var previousHashes: [UInt64] = []
    private var frameSize: (width: Int, height: Int)?
    private let maxHeight: Int
    public private(set) var totalHeight = 0

    public init(maxHeight: Int = 40_000) { self.maxHeight = maxHeight }

    public var isEmpty: Bool { strips.isEmpty }

    @discardableResult
    public func add(_ frame: CGImage) -> AddResult {
        let hashes = Self.rowHashes(frame)
        guard !hashes.isEmpty else { return .unmatched }

        guard let size = frameSize else {
            frameSize = (frame.width, frame.height)
            strips = [frame]
            totalHeight = frame.height
            previousHashes = hashes
            return .first
        }
        guard frame.width == size.width, frame.height == size.height else { return .unmatched }

        switch Self.detectShift(previous: previousHashes, next: hashes) {
        case .none:
            return .noChange
        case .unknown:
            return .unmatched
        case .scrolled(let s) where s > 0:
            guard totalHeight + s <= maxHeight else { return .limitReached }
            guard let strip = frame.cropping(to: CGRect(x: 0, y: frame.height - s, width: frame.width, height: s)) else { return .unmatched }
            strips.append(strip)
            totalHeight += s
            previousHashes = hashes
            return .appended(rows: s)
        case .scrolled(let s):
            let rows = -s
            guard totalHeight + rows <= maxHeight else { return .limitReached }
            guard let strip = frame.cropping(to: CGRect(x: 0, y: 0, width: frame.width, height: rows)) else { return .unmatched }
            strips.insert(strip, at: 0)
            totalHeight += rows
            previousHashes = hashes
            return .prepended(rows: rows)
        }
    }

    public func finish() -> CGImage? {
        guard let first = strips.first else { return nil }
        guard let ctx = CGContext(
            data: nil, width: first.width, height: totalHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        var top = 0
        for strip in strips {
            // CGContext origin is bottom-left; strips are stacked from the top.
            ctx.draw(strip, in: CGRect(x: 0, y: totalHeight - top - strip.height, width: strip.width, height: strip.height))
            top += strip.height
        }
        return ctx.makeImage()
    }

    // MARK: Alignment

    /// FNV-1a hash of each pixel row (every other pixel, for speed).
    public static func rowHashes(_ image: CGImage) -> [UInt64] {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return [] }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return [] }
        var hashes = [UInt64](repeating: 0, count: h)
        bytes.withUnsafeBufferPointer { buf in
            for y in 0..<h {
                var hash: UInt64 = 0xcbf2_9ce4_8422_2325
                var x = 0
                while x < w {
                    let i = (y * w + x) * 4
                    for k in 0..<4 { hash = (hash ^ UInt64(buf[i + k])) &* 0x100_0000_01b3 }
                    x += 2
                }
                // A bitmap context's first memory row is the image's top row.
                hashes[y] = hash
            }
        }
        return hashes
    }

    /// Finds how far `next` scrolled relative to `previous`, by matching row hashes.
    /// Rows equal to the dominant background row are ignored so blank areas can't vote.
    public static func detectShift(previous: [UInt64], next: [UInt64]) -> Shift {
        let h = previous.count
        guard h == next.count, h >= 16 else { return .unknown }
        if previous == next { return .none }

        var counts: [UInt64: Int] = [:]
        for v in previous { counts[v, default: 0] += 1 }
        for v in next { counts[v, default: 0] += 1 }
        let background = counts.max { $0.value < $1.value }?.key ?? 0

        func score(_ s: Int) -> (matches: Int, mismatches: Int) {
            var matches = 0, mismatches = 0
            for i in max(0, -s)..<min(h, h - s) {
                let a = next[i], b = previous[i + s]
                if a == background && b == background { continue }
                if a == b { matches += 1 } else { mismatches += 1 }
            }
            return (matches, mismatches)
        }

        let minMatches = max(6, h / 50)
        let zero = score(0)
        if zero.matches + zero.mismatches > 0,
           Double(zero.matches) / Double(zero.matches + zero.mismatches) >= 0.98 { return .none }

        let minOverlap = max(8, h / 10)
        var best: (shift: Int, value: Int, ratio: Double)?
        for s in -(h - minOverlap)...(h - minOverlap) where s != 0 {
            let (m, x) = score(s)
            guard m >= minMatches else { continue }
            let ratio = Double(m) / Double(m + x)
            guard ratio >= 0.8 else { continue }
            let value = m - 3 * x
            if best == nil || value > best!.value { best = (s, value, ratio) }
        }
        return best.map { .scrolled($0.shift) } ?? .unknown
    }
}
