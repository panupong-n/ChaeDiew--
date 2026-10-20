import AppKit

public enum ToolKind: String, CaseIterable, Sendable {
    case select, crop
    case rectangle, ellipse, arrow, line, freehand
    case text, blur, counter, highlight, spotlight, ruler, magnifier
    /// A pasted picture laid over the screenshot.
    case image
    /// Not a mark: click text in the screenshot to retype it in the same typeface, size and colour.
    case editText
}

public enum FillStyle: Int, CaseIterable, Sendable { case outline, hatch, solid }
public enum ArrowHead: Int, CaseIterable, Sendable { case normal, hollow, thin, double }
/// `blur` mosaics the whole region; `erase` paints it with the surrounding colour; the `…Text` modes only touch text.
public enum BlurMode: Int, CaseIterable, Sendable { case blur, blurText, erase, eraseText }

/// A grab point on a selected mark.
public enum Handle: Hashable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    case start, end, bend, bubble, tail
}

/// One drawn mark. Coordinates are in image points with a top-left origin.
public struct Annotation {
    public var kind: ToolKind
    public var start: CGPoint
    public var end: CGPoint
    public var points: [CGPoint]
    public var color: NSColor
    public var lineWidth: CGFloat
    public var text: String
    public var number: Int
    public var fontSize: CGFloat
    /// Rectangle / ellipse interior.
    public var fill: FillStyle
    /// Rectangle corners.
    public var rounded: Bool
    public var arrowHead: ArrowHead
    /// Arrow: how far the middle of the shaft is pushed sideways (points). 0 = straight.
    public var bend: CGFloat
    public var blurMode: BlurMode
    /// Spotlight darkness 1…9 · blur strength 1…9 · magnifier zoom 2…4.
    public var level: Int
    /// Spotlight shape.
    public var oval: Bool
    /// Text drawn on a filled label.
    public var pill: Bool
    /// Magnifier: centre of the zoomed bubble. `nil` puts it to the right of the source circle.
    public var bubble: CGPoint?
    /// The picture of an `.image` mark.
    public var image: CGImage?
    /// Arrow: shaft thins towards the tail (Shottr's default look).
    public var tapered: Bool
    /// Colour of the lettering on a label or counter; nil picks black or white for contrast.
    public var textColor: NSColor?
    /// Counter text such as "1.2" or "A3"; empty means the plain `number`.
    public var label: String
    /// Order in which counters were placed (the next counter continues from the latest).
    public var serial: Int
    /// Typeface of a text label; nil is the system font. `fontBold` picks the bold or regular cut.
    public var fontName: String?
    public var fontBold: Bool
    /// Rectangle / ellipse / line / arrow drawn with a wobbly, pen-sketch outline.
    public var sketchy: Bool
    /// Highlight: a marker stroke along start→end instead of a box.
    public var marker: Bool
    /// Counter: direction its pointer tail points in (radians, y grows downwards). Default: down-left.
    public var angle: CGFloat

    public init(
        kind: ToolKind,
        start: CGPoint,
        end: CGPoint,
        points: [CGPoint] = [],
        color: NSColor = .systemRed,
        lineWidth: CGFloat = 3,
        text: String = "",
        number: Int = 0,
        fontSize: CGFloat = 18,
        fill: FillStyle = .outline,
        rounded: Bool = true,
        arrowHead: ArrowHead = .normal,
        bend: CGFloat = 0,
        blurMode: BlurMode = .blur,
        level: Int? = nil,
        oval: Bool = false,
        pill: Bool = false,
        bubble: CGPoint? = nil,
        image: CGImage? = nil,
        angle: CGFloat = .pi * 3 / 4,
        tapered: Bool = false,
        marker: Bool = false,
        sketchy: Bool = false,
        textColor: NSColor? = nil,
        label: String = "",
        serial: Int = 0,
        fontName: String? = nil,
        fontBold: Bool = true
    ) {
        self.kind = kind
        self.start = start
        self.end = end
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.number = number
        self.fontSize = fontSize
        self.fill = fill
        self.rounded = rounded
        self.arrowHead = arrowHead
        self.bend = bend
        self.blurMode = blurMode
        self.level = level ?? Self.defaultLevel(kind)
        self.oval = oval
        self.pill = pill
        self.bubble = bubble
        self.image = image
        self.angle = angle
        self.tapered = tapered
        self.marker = marker
        self.sketchy = sketchy
        self.textColor = textColor
        self.label = label
        self.serial = serial
        self.fontName = fontName
        self.fontBold = fontBold
    }

    public static func defaultLevel(_ kind: ToolKind) -> Int {
        switch kind {
        case .spotlight: return 6
        case .blur: return 5
        case .magnifier: return 2
        case .image: return 10     // opacity in tenths
        case .ruler: return 1      // 1 = labels in points, 0 = physical pixels
        case .freehand: return 2   // smoothing passes
        default: return 0
        }
    }

    public var rect: CGRect { Geometry.normalizedRect(from: start, to: end) }

    public static let counterDiameter: CGFloat = 28
    public static let pillPadding = CGSize(width: 8, height: 4)

    /// Counter bubbles scale with their font size (18 pt → 28 pt).
    public var counterDiameter: CGFloat { Self.counterDiameter * fontSize / 18 }

    /// What a counter shows: its custom label ("1.2") or its number.
    public var counterText: String { label.isEmpty ? String(number) : label }

    /// Counters widen into a capsule when the text does not fit a circle.
    public var counterWidth: CGFloat {
        let d = counterDiameter
        let w = NSString(string: counterText).size(withAttributes: [.font: NSFont.boldSystemFont(ofSize: d * 0.54)]).width
        return max(d, w + d * 0.55)
    }

    /// Where a counter's pointer ends, and the grab point just beyond it.
    public var counterTail: CGPoint {
        let d = counterDiameter, w = counterWidth
        return CGPoint(x: start.x + (w / 2 + d * 0.3) * cos(angle), y: start.y + (d / 2 + d * 0.3) * sin(angle))
    }

    public var counterTailHandle: CGPoint {
        let d = counterDiameter, w = counterWidth
        return CGPoint(x: start.x + (w / 2 + d * 0.62) * cos(angle), y: start.y + (d / 2 + d * 0.62) * sin(angle))
    }

    /// Lettering colour of a label or counter: the chosen one, or black/white for contrast with the fill.
    public var labelTextColor: NSColor { textColor ?? ColorMath.readableText(on: color) }

    /// The font a text label is set in.
    public var textFont: NSFont {
        if let name = fontName, !name.isEmpty {
            let base = NSFont(name: name, size: fontSize) ?? .systemFont(ofSize: fontSize)
            if fontBold, let bold = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) as NSFont? { return bold }
            return base
        }
        return fontBold ? .boldSystemFont(ofSize: fontSize) : .systemFont(ofSize: fontSize)
    }

    public var isRectLike: Bool {
        switch kind {
        case .highlight: return !marker
        case .rectangle, .ellipse, .blur, .spotlight, .image: return true
        default: return false
        }
    }

    /// Thickness of a marker stroke.
    public var markerWidth: CGFloat { max(6, lineWidth * 4) }

    // MARK: Arrow geometry

    private var shaftMid: CGPoint { CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2) }

    private var shaftNormal: CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y, len = hypot(dx, dy)
        return len > 0 ? CGPoint(x: -dy / len, y: dx / len) : .zero
    }

    /// Quadratic Bézier control point; the curve passes through `bendHandle` at its middle.
    public var arrowControl: CGPoint {
        let m = shaftMid, n = shaftNormal
        return CGPoint(x: m.x + n.x * bend * 2, y: m.y + n.y * bend * 2)
    }

    public var bendHandle: CGPoint {
        let m = shaftMid, n = shaftNormal
        return CGPoint(x: m.x + n.x * bend, y: m.y + n.y * bend)
    }

    /// The shaft as a polyline (two points when straight).
    public func curvePoints(segments: Int = 24) -> [CGPoint] {
        guard bend != 0 else { return [start, end] }
        let c = arrowControl
        return (0...segments).map { i in
            let t = CGFloat(i) / CGFloat(segments), u = 1 - t
            return CGPoint(x: u * u * start.x + 2 * u * t * c.x + t * t * end.x,
                           y: u * u * start.y + 2 * u * t * c.y + t * t * end.y)
        }
    }

    // MARK: Magnifier geometry

    public var sourceRadius: CGFloat { hypot(end.x - start.x, end.y - start.y) }
    public var bubbleRadius: CGFloat { sourceRadius * CGFloat(max(2, level)) }
    public var bubbleCenter: CGPoint {
        bubble ?? CGPoint(x: start.x + sourceRadius + bubbleRadius + 10, y: start.y)
    }

    /// Axis-aligned bounds used for selection outlines and hit testing.
    public var bounds: CGRect {
        switch kind {
        case .freehand:
            guard let first = points.first else { return CGRect(origin: start, size: .zero) }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for p in points {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .counter:
            let d = counterDiameter, w = counterWidth
            return CGRect(x: start.x - w / 2, y: start.y - d / 2, width: w, height: d)
        case .text:
            let size = NSString(string: text).size(withAttributes: [.font: textFont])
            guard pill else { return CGRect(origin: start, size: size) }
            return CGRect(origin: start, size: CGSize(width: size.width + Self.pillPadding.width * 2,
                                                       height: size.height + Self.pillPadding.height * 2))
        case .magnifier:
            let r = sourceRadius, c = bubbleCenter, br = bubbleRadius
            let source = CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2)
            return source.union(CGRect(x: c.x - br, y: c.y - br, width: br * 2, height: br * 2))
        case .arrow where bend != 0:
            return Self.boundingBox(curvePoints())
        case .highlight where marker:
            return Self.boundingBox([start, end]).insetBy(dx: -markerWidth / 2, dy: -markerWidth / 2)
        default:
            return rect
        }
    }

    static func boundingBox(_ pts: [CGPoint]) -> CGRect {
        guard let first = pts.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in pts { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func hitTest(_ p: CGPoint, tolerance: CGFloat = 6) -> Bool {
        switch kind {
        case .line, .ruler:
            return Geometry.distance(from: p, toSegment: start, end) <= tolerance + lineWidth / 2
        case .highlight where marker:
            return Geometry.distance(from: p, toSegment: start, end) <= markerWidth / 2 + tolerance / 2
        case .arrow:
            let pts = curvePoints()
            for i in 1..<pts.count where Geometry.distance(from: p, toSegment: pts[i - 1], pts[i]) <= tolerance + lineWidth / 2 {
                return true
            }
            return false
        case .freehand:
            guard points.count > 1 else { return points.first.map { hypot($0.x - p.x, $0.y - p.y) <= tolerance } ?? false }
            for i in 1..<points.count where Geometry.distance(from: p, toSegment: points[i - 1], points[i]) <= tolerance + lineWidth / 2 {
                return true
            }
            return false
        case .rectangle:
            let r = rect
            let inner = r.insetBy(dx: tolerance, dy: tolerance)
            return r.insetBy(dx: -tolerance, dy: -tolerance).contains(p) && (fill != .outline || !inner.contains(p))
        case .ellipse:
            let r = rect
            guard r.width > 0, r.height > 0 else { return false }
            let a = r.width / 2, b = r.height / 2
            let v = hypot((p.x - r.midX) / a, (p.y - r.midY) / b)
            return fill == .outline ? abs(v - 1) * min(a, b) <= tolerance : (v - 1) * min(a, b) <= tolerance
        case .magnifier:
            let c = bubbleCenter
            return hypot(p.x - start.x, p.y - start.y) <= sourceRadius + tolerance
                || hypot(p.x - c.x, p.y - c.y) <= bubbleRadius + tolerance
        default:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        }
    }

    // MARK: Handles

    /// Grab points for resizing the mark, in image points.
    public func handles() -> [(handle: Handle, point: CGPoint)] {
        switch kind {
        case _ where isRectLike:
            let r = rect
            return [
                (.topLeft, CGPoint(x: r.minX, y: r.minY)), (.top, CGPoint(x: r.midX, y: r.minY)),
                (.topRight, CGPoint(x: r.maxX, y: r.minY)), (.right, CGPoint(x: r.maxX, y: r.midY)),
                (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)), (.bottom, CGPoint(x: r.midX, y: r.maxY)),
                (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)), (.left, CGPoint(x: r.minX, y: r.midY)),
            ]
        case .line, .ruler:
            return [(.start, start), (.end, end)]
        case .highlight where marker:
            return [(.start, start), (.end, end)]
        case .arrow:
            return [(.start, start), (.end, end), (.bend, bendHandle)]
        case .magnifier:
            return [(.end, end), (.bubble, bubbleCenter)]
        case .counter:
            return [(.tail, counterTailHandle)]
        default:
            return []
        }
    }

    /// This mark after dragging `handle` to `p`.
    public func moving(_ handle: Handle, to p: CGPoint) -> Annotation {
        var a = self
        switch handle {
        case .start: a.start = p
        case .end: a.end = p
        case .bubble: a.bubble = p
        case .tail: a.angle = atan2(p.y - start.y, p.x - start.x)
        case .bend:
            let n = shaftNormal, m = shaftMid
            a.bend = (p.x - m.x) * n.x + (p.y - m.y) * n.y
            if abs(a.bend) < 3 { a.bend = 0 }  // snaps back to straight
        default:
            let r = rect
            var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
            switch handle {
            case .topLeft: minX = p.x; minY = p.y
            case .top: minY = p.y
            case .topRight: maxX = p.x; minY = p.y
            case .right: maxX = p.x
            case .bottomRight: maxX = p.x; maxY = p.y
            case .bottom: maxY = p.y
            case .bottomLeft: minX = p.x; maxY = p.y
            case .left: minX = p.x
            default: break
            }
            a.start = CGPoint(x: min(minX, maxX), y: min(minY, maxY))
            a.end = CGPoint(x: max(minX, maxX), y: max(minY, maxY))
        }
        return a
    }

    public func translated(by d: CGPoint) -> Annotation {
        var a = self
        a.start = CGPoint(x: start.x + d.x, y: start.y + d.y)
        a.end = CGPoint(x: end.x + d.x, y: end.y + d.y)
        a.points = points.map { CGPoint(x: $0.x + d.x, y: $0.y + d.y) }
        a.bubble = bubble.map { CGPoint(x: $0.x + d.x, y: $0.y + d.y) }
        return a
    }

    public func scaled(by f: CGFloat) -> Annotation {
        var a = self
        a.start = CGPoint(x: start.x * f, y: start.y * f)
        a.end = CGPoint(x: end.x * f, y: end.y * f)
        a.points = points.map { CGPoint(x: $0.x * f, y: $0.y * f) }
        a.bubble = bubble.map { CGPoint(x: $0.x * f, y: $0.y * f) }
        a.bend = bend * f
        return a
    }
}

public enum Geometry {
    /// A quadratic Bézier as a polyline.
    public static func quadPoints(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, segments: Int = 20) -> [CGPoint] {
        (0...segments).map { i in
            let t = CGFloat(i) / CGFloat(segments), u = 1 - t
            return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
        }
    }

    /// Chaikin corner cutting: rounds a hand-drawn polyline. The end points stay put.
    public static func smoothed(_ points: [CGPoint], iterations: Int) -> [CGPoint] {
        var pts = points
        guard pts.count > 2, iterations > 0 else { return pts }
        for _ in 0..<min(iterations, 4) where pts.count < 6000 {
            var out = [pts[0]]
            for i in 0..<(pts.count - 1) {
                let a = pts[i], b = pts[i + 1]
                out.append(CGPoint(x: 0.75 * a.x + 0.25 * b.x, y: 0.75 * a.y + 0.25 * b.y))
                out.append(CGPoint(x: 0.25 * a.x + 0.75 * b.x, y: 0.25 * a.y + 0.75 * b.y))
            }
            out.append(pts[pts.count - 1])
            pts = out
        }
        return pts
    }

    public static func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// The two back-points of an arrow head whose tip is `to`.
    public static func arrowHead(
        from: CGPoint, to: CGPoint, length: CGFloat, spread: CGFloat = .pi / 7
    ) -> (CGPoint, CGPoint) {
        let theta = atan2(to.y - from.y, to.x - from.x)
        let p1 = CGPoint(x: to.x - length * cos(theta - spread), y: to.y - length * sin(theta - spread))
        let p2 = CGPoint(x: to.x - length * cos(theta + spread), y: to.y - length * sin(theta + spread))
        return (p1, p2)
    }

    public static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

/// Counter text arithmetic: "1.1" → "1.2", "3.6" → "3.7", "A9" → "A10", "7" → "8".
public enum CounterText {
    /// The text with its last run of digits changed by `delta` (never below 0). Text without digits becomes "1".
    public static func step(_ text: String, by delta: Int) -> String {
        let chars = Array(text)
        guard let end = chars.lastIndex(where: { $0.isNumber && $0.isASCII }) else { return delta >= 0 ? "1" : "0" }
        var start = end
        while start > 0, chars[start - 1].isNumber, chars[start - 1].isASCII { start -= 1 }
        let digits = String(chars[start...end])
        let value = max(0, (Int(digits) ?? 0) + delta)
        // Keep leading zeros ("007" → "008").
        let padded = String(format: "%0\(digits.count)d", value)
        return String(chars[..<start]) + padded + String(chars[(end + 1)...])
    }

    public static func next(_ text: String) -> String { step(text, by: 1) }
}
