import CoreGraphics
import Foundation

/// Pixel-level redaction effects for the Blur / Blur Text / Erase / Erase Text modes. All of them
/// replace the original pixels in the output, so nothing underneath can be recovered from an export.
public enum RegionEffects {
    struct Buffer {
        var width: Int
        var height: Int
        var px: [UInt8]  // RGBA, row 0 is the top row
    }

    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    static func buffer(of image: CGImage, rect: CGRect) -> Buffer? {
        guard let crop = image.cropping(to: rect) else { return nil }
        let w = crop.width, h = crop.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? Buffer(width: w, height: h, px: px) : nil
    }

    static func image(from b: Buffer) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(b.px) as CFData) else { return nil }
        return CGImage(
            width: b.width, height: b.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: b.width * 4,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Most common colour among `indices` (pixel indices into `px`), found in 4-bit-per-channel buckets
    /// and then averaged, so anti-aliased noise doesn't shift it.
    static func dominantColor(_ px: [UInt8], indices: [Int]) -> (r: UInt8, g: UInt8, b: UInt8) {
        guard !indices.isEmpty else { return (255, 255, 255) }
        var counts = [Int](repeating: 0, count: 4096)
        var sr = [Int](repeating: 0, count: 4096), sg = sr, sb = sr
        for i in indices {
            let r = Int(px[i * 4]), g = Int(px[i * 4 + 1]), b = Int(px[i * 4 + 2])
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            counts[key] += 1; sr[key] += r; sg[key] += g; sb[key] += b
        }
        var best = 0
        for k in 1..<4096 where counts[k] > counts[best] { best = k }
        let n = counts[best]
        return (UInt8(sr[best] / n), UInt8(sg[best] / n), UInt8(sb[best] / n))
    }

    /// Pixels that differ from `bg`, grown by `grow` pixels so anti-aliased glyph edges are covered too.
    static func textMask(_ b: Buffer, bg: (r: UInt8, g: UInt8, b: UInt8), threshold: Int = 24, grow: Int) -> [Bool] {
        let w = b.width, h = b.height
        var mask = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) {
            let d = max(abs(Int(b.px[i * 4]) - Int(bg.r)), abs(Int(b.px[i * 4 + 1]) - Int(bg.g)), abs(Int(b.px[i * 4 + 2]) - Int(bg.b)))
            mask[i] = d > threshold
        }
        guard grow > 0 else { return mask }
        var horizontal = mask
        for y in 0..<h {
            for x in 0..<w where mask[y * w + x] {
                for dx in -grow...grow where (0..<w).contains(x + dx) { horizontal[y * w + x + dx] = true }
            }
        }
        var out = horizontal
        for y in 0..<h {
            for x in 0..<w where horizontal[y * w + x] {
                for dy in -grow...grow where (0..<h).contains(y + dy) { out[(y + dy) * w + x] = true }
            }
        }
        return out
    }

    private static func fill(_ b: inout Buffer, at i: Int, _ c: (r: UInt8, g: UInt8, b: UInt8)) {
        b.px[i * 4] = c.r; b.px[i * 4 + 1] = c.g; b.px[i * 4 + 2] = c.b; b.px[i * 4 + 3] = 255
    }

    /// Colour of the pixels just outside `pixelRect` (falls back to the region itself when it fills the image).
    public static func surroundingColor(of image: CGImage, pixelRect: CGRect) -> (r: UInt8, g: UInt8, b: UInt8) {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let inner = pixelRect.integral.intersection(bounds)
        let outer = inner.insetBy(dx: -4, dy: -4).intersection(bounds).integral
        if let b = buffer(of: image, rect: outer) {
            var ring: [Int] = []
            let ox = Int(inner.minX - outer.minX), oy = Int(inner.minY - outer.minY)
            for y in 0..<b.height {
                for x in 0..<b.width where !(x >= ox && x < ox + Int(inner.width) && y >= oy && y < oy + Int(inner.height)) {
                    ring.append(y * b.width + x)
                }
            }
            if !ring.isEmpty { return dominantColor(b.px, indices: ring) }
            return dominantColor(b.px, indices: Array(0..<(b.width * b.height)))
        }
        return (255, 255, 255)
    }

    /// Erase: the whole region painted with the colour around it.
    public static func erased(_ image: CGImage, pixelRect: CGRect) -> CGImage? {
        guard var b = buffer(of: image, rect: pixelRect) else { return nil }
        let c = surroundingColor(of: image, pixelRect: pixelRect)
        for i in 0..<(b.width * b.height) { fill(&b, at: i, c) }
        return Self.image(from: b)
    }

    /// Erase Text: only pixels that differ from the region's background are replaced by it.
    public static func erasedText(_ image: CGImage, pixelRect: CGRect) -> CGImage? {
        guard var b = buffer(of: image, rect: pixelRect) else { return nil }
        let bg = dominantColor(b.px, indices: Array(0..<(b.width * b.height)))
        let mask = textMask(b, bg: bg, grow: 2)
        for i in 0..<mask.count where mask[i] { fill(&b, at: i, bg) }
        return Self.image(from: b)
    }

    /// Blur Text: every `block`×`block` cell that contains text becomes one flat colour; empty cells are untouched.
    /// Whole cells (not glyph silhouettes) are replaced, so letter shapes cannot be read back from the result.
    public static func blurredText(_ image: CGImage, pixelRect: CGRect, block: Int) -> CGImage? {
        guard var b = buffer(of: image, rect: pixelRect) else { return nil }
        let size = max(2, block)
        let bg = dominantColor(b.px, indices: Array(0..<(b.width * b.height)))
        let mask = textMask(b, bg: bg, grow: 1)
        var by = 0
        while by < b.height {
            var bx = 0
            while bx < b.width {
                let xs = bx..<min(bx + size, b.width), ys = by..<min(by + size, b.height)
                var hasText = false
                var r = 0, g = 0, bl = 0, n = 0
                for y in ys { for x in xs {
                    let i = y * b.width + x
                    if mask[i] { hasText = true }
                    r += Int(b.px[i * 4]); g += Int(b.px[i * 4 + 1]); bl += Int(b.px[i * 4 + 2]); n += 1
                } }
                if hasText {
                    let c = (r: UInt8(r / n), g: UInt8(g / n), b: UInt8(bl / n))
                    for y in ys { for x in xs { fill(&b, at: y * b.width + x, c) } }
                }
                bx += size
            }
            by += size
        }
        return Self.image(from: b)
    }
}
