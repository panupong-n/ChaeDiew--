import CoreGraphics

/// Read-only access to the pixels of an image, for the live colour readout and the edge-measuring ruler.
/// Coordinates are image pixels with a top-left origin.
public struct PixelProbe {
    public typealias RGB = (r: Int, g: Int, b: Int)
    private let buffer: RegionEffects.Buffer
    public var width: Int { buffer.width }
    public var height: Int { buffer.height }

    public init?(image: CGImage) {
        guard let b = RegionEffects.buffer(of: image, rect: CGRect(x: 0, y: 0, width: image.width, height: image.height)) else { return nil }
        buffer = b
    }

    public func color(x: Int, y: Int) -> RGB? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let i = (y * width + x) * 4
        return (Int(buffer.px[i]), Int(buffer.px[i + 1]), Int(buffer.px[i + 2]))
    }

    private func clamped(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
        let a = max(0, min(x0, x1)), b = max(0, min(y0, y1)), c = min(width - 1, max(x0, x1)), d = min(height - 1, max(y0, y1))
        return a <= c && b <= d ? (a, b, c, d) : nil
    }

    /// The darkest pixel in a square of `radius` around (x, y): the colour of text on a light background.
    public func darkest(x: Int, y: Int, radius: Int = 10) -> RGB? {
        guard let r = clamped(x - radius, y - radius, x + radius, y + radius) else { return nil }
        var best: RGB?
        var bestSum = Int.max
        for yy in r.y0...r.y1 {
            for xx in r.x0...r.x1 {
                guard let c = color(x: xx, y: yy) else { continue }
                let lum = c.r * 3 + c.g * 6 + c.b  // cheap luma
                if lum < bestSum { bestSum = lum; best = c }
            }
        }
        return best
    }

    /// Mean colour of an inclusive pixel rectangle.
    public func average(x0: Int, y0: Int, x1: Int, y1: Int) -> RGB? {
        guard let r = clamped(x0, y0, x1, y1) else { return nil }
        var sr = 0, sg = 0, sb = 0, n = 0
        for yy in r.y0...r.y1 {
            for xx in r.x0...r.x1 {
                guard let c = color(x: xx, y: yy) else { continue }
                sr += c.r; sg += c.g; sb += c.b; n += 1
            }
        }
        return n > 0 ? (sr / n, sg / n, sb / n) : nil
    }

    /// Extent of the flat-coloured run through (x, y) along one axis, as inclusive pixel indices.
    /// A neighbour belongs to the run while it stays within `tolerance` of the pixel under the cursor.
    /// With `maxGap` > 0 the run may cross up to that many different pixels (text, an icon) as long as the
    /// colour resumes afterwards: the "outer size" of a button that has a label on it.
    public func run(x: Int, y: Int, horizontal: Bool, tolerance: Int = 12, maxGap: Int = 0) -> ClosedRange<Int>? {
        guard let seed = color(x: x, y: y) else { return nil }
        func same(_ c: RGB) -> Bool { max(abs(c.r - seed.r), abs(c.g - seed.g), abs(c.b - seed.b)) <= tolerance }
        let start = horizontal ? x : y
        let limit = horizontal ? width : height
        func at(_ i: Int) -> RGB? { horizontal ? color(x: i, y: y) : color(x: x, y: i) }
        func extent(step: Int) -> Int {
            var pos = start, lastGood = start, gap = 0
            while pos + step >= 0, pos + step < limit, let c = at(pos + step) {
                pos += step
                if same(c) { lastGood = pos; gap = 0 } else { gap += 1; if gap > maxGap { break } }
            }
            return lastGood
        }
        return extent(step: -1)...extent(step: 1)
    }

    /// Bounding box (inclusive pixel coordinates) of the connected area around (x, y) whose colour stays within
    /// `tolerance` of the pixel at (x, y): what "⌘-click a flat object" selects.
    public func floodBounds(x: Int, y: Int, tolerance: Int = 10, maxPixels: Int = 6_000_000) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
        guard let seed = color(x: x, y: y) else { return nil }
        var visited = [Bool](repeating: false, count: width * height)
        var stack = [y * width + x]
        visited[y * width + x] = true
        var x0 = x, x1 = x, y0 = y, y1 = y, count = 0
        while let i = stack.popLast() {
            count += 1
            if count > maxPixels { break }
            let cx = i % width, cy = i / width
            x0 = min(x0, cx); x1 = max(x1, cx); y0 = min(y0, cy); y1 = max(y1, cy)
            for (nx, ny) in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)] where nx >= 0 && ny >= 0 && nx < width && ny < height {
                let j = ny * width + nx
                if visited[j] { continue }
                visited[j] = true
                let k = j * 4
                if max(abs(Int(buffer.px[k]) - seed.r), abs(Int(buffer.px[k + 1]) - seed.g), abs(Int(buffer.px[k + 2]) - seed.b)) <= tolerance {
                    stack.append(j)
                }
            }
        }
        return (x0, y0, x1, y1)
    }

    /// Tight box around everything inside the rectangle that differs from the colour along the rectangle's own frame.
    public func contentBounds(x0: Int, y0: Int, x1: Int, y1: Int, tolerance: Int = 16) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
        guard let r = clamped(x0, y0, x1, y1) else { return nil }
        var frame: [Int] = []
        for yy in r.y0...r.y1 {
            for xx in r.x0...r.x1 where xx == r.x0 || xx == r.x1 || yy == r.y0 || yy == r.y1 { frame.append(yy * width + xx) }
        }
        let bg = RegionEffects.dominantColor(buffer.px, indices: frame)
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for yy in r.y0...r.y1 {
            for xx in r.x0...r.x1 {
                let k = (yy * width + xx) * 4
                if max(abs(Int(buffer.px[k]) - Int(bg.r)), abs(Int(buffer.px[k + 1]) - Int(bg.g)), abs(Int(buffer.px[k + 2]) - Int(bg.b))) > tolerance {
                    minX = min(minX, xx); maxX = max(maxX, xx); minY = min(minY, yy); maxY = max(maxY, yy)
                }
            }
        }
        return maxX >= 0 ? (minX, minY, maxX, maxY) : nil
    }
}
