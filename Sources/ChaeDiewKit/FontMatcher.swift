import AppKit

/// What it takes to retype a line of text in a screenshot so it looks like the original:
/// typeface, weight, size, ink colour, background colour and where the text box starts.
public struct TextStyleGuess {
    public var fontName: String?      // nil = the system font
    public var bold: Bool
    public var sizePoints: CGFloat
    public var ink: NSColor
    public var background: NSColor
    /// Top-left of the text box, in image pixels.
    public var originPixels: CGPoint
    /// 0…1 overlap between the original glyphs and the chosen font's rendering.
    public var score: Double
}

/// Finds the installed typeface that best reproduces a piece of text in an image, by rendering the recognised string
/// in each candidate at the size that matches the line's width and comparing the glyph shapes pixel by pixel.
public enum FontMatcher {
    struct Candidate { let name: String?; let bold: Bool }

    static func font(_ c: Candidate, size: CGFloat) -> NSFont? {
        guard let name = c.name else { return c.bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size) }
        guard let base = NSFont(name: name, size: size) else { return nil }
        return c.bold ? NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) : base
    }

    static let latin: [String?] = [nil, "Helvetica Neue", "Arial", "Verdana", "Trebuchet MS", "Georgia", "Times New Roman", "Menlo", "Courier New", "Tahoma", "Avenir Next", "Futura"]
    static let thai: [String?] = ["Thonburi", "Sukhumvit Set", "Ayuthaya", "Krungthep", "Silom", "Tahoma"]

    static func candidates(for text: String) -> [Candidate] {
        let hasThai = text.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) }
        let names = hasThai ? thai + [nil] : latin
        return names.flatMap { [Candidate(name: $0, bold: false), Candidate(name: $0, bold: true)] }
            .filter { font($0, size: 12) != nil }
    }

    /// A black-on-white mask (true = ink) of `text` set in `font`, with the text box's top-left at (pad, pad).
    private static func render(_ text: String, font: NSFont, ink: NSColor = .black, width: Int, height: Int, pad: Int) -> [Bool]? {
        var gray = [UInt8](repeating: 255, count: width * height)
        let ok: Bool = gray.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSString(string: text).draw(at: CGPoint(x: pad, y: pad), withAttributes: [.font: font, .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        return ok ? gray.map { $0 < 140 } : nil
    }

    private static func inkBounds(_ mask: [Bool], width: Int, height: Int) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
        var x0 = width, y0 = height, x1 = -1, y1 = -1
        for y in 0..<height { for x in 0..<width where mask[y * width + x] { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
        return x1 >= 0 ? (x0, y0, x1, y1) : nil
    }

    /// `lineRect` is the text's rectangle in image pixels (top-left origin), `pixelScale` converts the size to points.
    public static func guess(image: CGImage, lineRect: CGRect, text: String, pixelScale: CGFloat) -> TextStyleGuess? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropRect = lineRect.insetBy(dx: -4, dy: -4).integral.intersection(bounds)
        guard cropRect.width >= 6, cropRect.height >= 6, let buf = RegionEffects.buffer(of: image, rect: cropRect) else { return nil }
        let w = buf.width, h = buf.height
        let allPixels = Array(0..<(w * h))
        let bg = RegionEffects.dominantColor(buf.px, indices: allPixels)

        // How far each pixel is from the background; the farthest ones are the ink.
        var distance = [Int](repeating: 0, count: w * h)
        var maxDistance = 0
        for i in 0..<(w * h) {
            let d = max(abs(Int(buf.px[i * 4]) - Int(bg.r)), abs(Int(buf.px[i * 4 + 1]) - Int(bg.g)), abs(Int(buf.px[i * 4 + 2]) - Int(bg.b)))
            distance[i] = d
            maxDistance = max(maxDistance, d)
        }
        guard maxDistance >= 40 else { return nil }
        let strong = (0..<(w * h)).filter { distance[$0] >= Int(Double(maxDistance) * 0.85) }
        var sr = 0, sg = 0, sb = 0
        for i in strong { sr += Int(buf.px[i * 4]); sg += Int(buf.px[i * 4 + 1]); sb += Int(buf.px[i * 4 + 2]) }
        let n = max(1, strong.count)
        let inkColor = NSColor(srgbRed: CGFloat(sr / n) / 255, green: CGFloat(sg / n) / 255, blue: CGFloat(sb / n) / 255, alpha: 1)
        let bgColor = NSColor(srgbRed: CGFloat(bg.r) / 255, green: CGFloat(bg.g) / 255, blue: CGFloat(bg.b) / 255, alpha: 1)

        let original = distance.map { Double($0) >= Double(maxDistance) * 0.5 }
        guard let ob = inkBounds(original, width: w, height: h), ob.x1 - ob.x0 >= 4 else { return nil }
        let inkWidth = CGFloat(ob.x1 - ob.x0 + 1)
        let pad = 10
        var best: (candidate: Candidate, size: CGFloat, score: Double, origin: CGPoint)?

        for c in candidates(for: text) {
            // The size at which this face makes the same ink width as the original.
            guard let probe = font(c, size: 40) else { continue }
            let probeW = w + 2 * pad + Int(inkWidth) * 2
            guard let probeMask = render(text, font: probe, width: probeW, height: Int(probe.pointSize * 2.4) + 2 * pad, pad: pad),
                  let pb = inkBounds(probeMask, width: probeW, height: Int(probe.pointSize * 2.4) + 2 * pad) else { continue }
            let probeInk = CGFloat(pb.x1 - pb.x0 + 1)
            let size = (40 * inkWidth / max(1, probeInk)).rounded(.toNearestOrEven)
            guard size >= 5, size <= 600, let f = font(c, size: size) else { continue }

            let rw = w + 2 * pad, rh = h + 2 * pad
            guard let big = render(text, font: f, width: max(rw, Int(inkWidth) + 4 * pad), height: max(rh, Int(size * 2.4) + 2 * pad), pad: pad) else { continue }
            let bigW = max(rw, Int(inkWidth) + 4 * pad), bigH = max(rh, Int(size * 2.4) + 2 * pad)
            guard let rb = inkBounds(big, width: bigW, height: bigH) else { continue }
            // Text-box origin (in crop coordinates) that puts the rendered ink's top-left on the original's.
            let baseX = ob.x0 - (rb.x0 - pad), baseY = ob.y0 - (rb.y0 - pad)

            var bestHere: (score: Double, origin: CGPoint)?
            for dy in -3...3 {
                for dx in -2...2 {
                    let ox = baseX + dx, oy = baseY + dy
                    var inter = 0, union = 0
                    for y in 0..<h {
                        let by = y - oy + pad
                        for x in 0..<w {
                            let bx = x - ox + pad
                            let r = bx >= 0 && by >= 0 && bx < bigW && by < bigH && big[by * bigW + bx]
                            let o = original[y * w + x]
                            if r && o { inter += 1 }
                            if r || o { union += 1 }
                        }
                    }
                    let score = union > 0 ? Double(inter) / Double(union) : 0
                    if bestHere == nil || score > bestHere!.score { bestHere = (score, CGPoint(x: ox, y: oy)) }
                }
            }
            if let bh = bestHere, best == nil || bh.score > best!.score { best = (c, size, bh.score, bh.origin) }
        }
        guard let b = best else { return nil }
        return TextStyleGuess(
            fontName: b.candidate.name, bold: b.candidate.bold, sizePoints: b.size / pixelScale, ink: inkColor, background: bgColor,
            originPixels: CGPoint(x: cropRect.minX + b.origin.x, y: cropRect.minY + b.origin.y), score: b.score)
    }
}
