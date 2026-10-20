import CoreGraphics

/// Hand-drawn look: outlines are redrawn as slightly wobbly strokes, twice over, like a quick pen sketch.
/// The wobble is seeded from the mark's own coordinates, so it never shimmers between redraws.
public enum Sketch {
    struct RNG {
        var state: UInt64
        mutating func next() -> CGFloat {  // -1 … 1
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 33) & 0xFFFF) / 32768 - 1
        }
    }

    public static func seed(_ a: Annotation) -> UInt64 {
        func q(_ v: CGFloat) -> UInt64 { UInt64(bitPattern: Int64((v * 4).rounded())) }
        return q(a.start.x) &* 73856093 ^ q(a.start.y) &* 19349663 ^ q(a.end.x) &* 83492791 ^ q(a.end.y) &* 2654435761
    }

    /// Points along `pts` every `step`, each pushed sideways by up to `amplitude`; ends overshoot a little.
    static func polyline(_ pts: [CGPoint], closed: Bool, seed: UInt64, amplitude: CGFloat, step: CGFloat = 14) -> [CGPoint] {
        guard pts.count > 1 else { return pts }
        var rng = RNG(state: seed | 1)
        var out: [CGPoint] = []
        let n = closed ? pts.count : pts.count - 1
        for i in 0..<n {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            let len = hypot(b.x - a.x, b.y - a.y)
            guard len > 0 else { continue }
            let ux = (b.x - a.x) / len, uy = (b.y - a.y) / len
            let pieces = max(1, Int(len / step))
            let over = amplitude * 1.5
            for k in 0...pieces {
                let t = CGFloat(k) / CGFloat(pieces)
                var x = a.x + (b.x - a.x) * t + (-uy) * rng.next() * amplitude
                var y = a.y + (b.y - a.y) * t + ux * rng.next() * amplitude
                if k == 0 { x -= ux * over * abs(rng.next()); y -= uy * over * abs(rng.next()) }
                if k == pieces { x += ux * over * abs(rng.next()); y += uy * over * abs(rng.next()) }
                out.append(CGPoint(x: x, y: y))
            }
        }
        return out
    }

    static func rectPoints(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    /// A hand-drawn circle: one continuous stroke that starts a little inside, spirals out, overshoots its own
    /// start so the ends cross, and wobbles in radius like a marker loop around something.
    public static func loopPoints(_ r: CGRect, seed: UInt64, count: Int = 110) -> [CGPoint] {
        var rng = RNG(state: seed | 1)
        let turns = 1.1 + 0.08 * abs(rng.next())
        let start = -CGFloat.pi * 0.6 + 0.5 * rng.next()
        let phase = rng.next() * .pi
        let direction: CGFloat = rng.next() > 0 ? 1 : -1
        return (0...count).map { i in
            let u = CGFloat(i) / CGFloat(count)
            let t = start + direction * u * turns * 2 * .pi
            let drift = 0.92 + 0.13 * u                                   // spirals outwards
            let wobble = 1 + 0.035 * sin(2 * t + phase) + 0.02 * sin(3 * t + 2 * phase) + 0.008 * rng.next()
            return CGPoint(x: r.midX + r.width / 2 * drift * wobble * cos(t), y: r.midY + r.height / 2 * drift * wobble * sin(t))
        }
    }

    static func ellipsePoints(_ r: CGRect, count: Int = 40) -> [CGPoint] {
        (0..<count).map { i in
            let t = CGFloat(i) / CGFloat(count) * 2 * .pi
            return CGPoint(x: r.midX + r.width / 2 * cos(t), y: r.midY + r.height / 2 * sin(t))
        }
    }
}
