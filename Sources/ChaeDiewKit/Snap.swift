import CoreGraphics

/// "Snap to Objects": while a mark is dragged, its edges and centre stick to the edges and centres of the other
/// marks and of the image, so things line up without effort.
public enum Snap {
    public struct Result: Equatable {
        public var dx: CGFloat = 0
        public var dy: CGFloat = 0
        /// Image x / y positions of the lines it snapped to (for drawing guides).
        public var guideXs: [CGFloat] = []
        public var guideYs: [CGFloat] = []
    }

    private static func axis(_ moving: [CGFloat], _ targets: [CGFloat], threshold: CGFloat) -> (delta: CGFloat, line: CGFloat)? {
        var best: (delta: CGFloat, line: CGFloat)?
        for m in moving {
            for t in targets {
                let d = t - m
                if abs(d) <= threshold, best == nil || abs(d) < abs(best!.delta) { best = (d, t) }
            }
        }
        return best
    }

    /// How far to shift `moving` so it lines up with something in `targets`, if anything is within `threshold`.
    public static func adjust(moving: CGRect, targets: [CGRect], threshold: CGFloat) -> Result {
        var xs: [CGFloat] = [], ys: [CGFloat] = []
        for r in targets { xs += [r.minX, r.midX, r.maxX]; ys += [r.minY, r.midY, r.maxY] }
        var result = Result()
        if let x = axis([moving.minX, moving.midX, moving.maxX], xs, threshold: threshold) { result.dx = x.delta; result.guideXs = [x.line] }
        if let y = axis([moving.minY, moving.midY, moving.maxY], ys, threshold: threshold) { result.dy = y.delta; result.guideYs = [y.line] }
        return result
    }
}
