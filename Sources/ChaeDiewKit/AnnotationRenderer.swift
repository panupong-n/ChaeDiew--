import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Draws an image plus annotations. The context must already use a top-left origin
/// in image points (an `isFlipped` view, or the transform set up by `export`).
public enum AnnotationRenderer {
    private static let ciContext = CIContext()

    public static func draw(
        image: CGImage, pointSize: CGSize, annotations: [Annotation], in ctx: CGContext
    ) {
        let full = CGRect(origin: .zero, size: pointSize)
        drawImage(image, in: full, ctx: ctx)

        let pixelScale = CGFloat(image.width) / pointSize.width
        for a in annotations {
            switch a.kind {
            case .rectangle, .ellipse:
                drawShape(a, ctx: ctx)
            case .line:
                if a.sketchy {
                    sketchStroke(a, [a.start, a.end], closed: false, ctx: ctx)
                } else {
                    stroke(ctx, a) { c in
                        c.move(to: a.start)
                        c.addLine(to: a.end)
                        c.strokePath()
                    }
                }
            case .freehand:
                stroke(ctx, a) { c in
                    let pts = Geometry.smoothed(a.points, iterations: a.level)
                    guard let first = pts.first else { return }
                    c.move(to: first)
                    for p in pts.dropFirst() { c.addLine(to: p) }
                    if pts.count == 1 { c.addLine(to: first) }
                    c.strokePath()
                }
            case .arrow:
                drawArrow(a, ctx: ctx)
            case .highlight:
                ctx.saveGState()
                if a.marker {
                    // A real highlighter: multiplies with the page, so dark text stays readable.
                    ctx.setBlendMode(.multiply)
                    ctx.setStrokeColor(a.color.withAlphaComponent(0.9).cgColor)
                    ctx.setLineWidth(a.markerWidth)
                    ctx.setLineCap(a.rounded ? .round : .butt)
                    ctx.move(to: a.start)
                    ctx.addLine(to: a.end)
                    ctx.strokePath()
                } else {
                    ctx.setFillColor(a.color.withAlphaComponent(0.35).cgColor)
                    ctx.fill(a.rect)
                }
                ctx.restoreGState()
            case .spotlight:
                drawSpotlight(a, full: full, ctx: ctx)
            case .blur:
                drawBlur(a, image: image, pixelScale: pixelScale, ctx: ctx)
            case .counter:
                drawCounter(a, ctx: ctx)
            case .text:
                drawText(a, ctx: ctx)
            case .ruler:
                drawRuler(a, pixelScale: pixelScale, ctx: ctx)
            case .magnifier:
                drawMagnifier(a, image: image, full: full, ctx: ctx)
            case .image:
                if let picture = a.image, a.rect.width > 0, a.rect.height > 0 {
                    ctx.saveGState()
                    ctx.setAlpha(CGFloat(min(10, max(1, a.level))) / 10)
                    drawImage(picture, in: a.rect, ctx: ctx)
                    ctx.restoreGState()
                }
            case .select, .crop, .editText:
                break
            }
        }
    }

    /// Renders the image and annotations at the image's native pixel size.
    public static func export(image: CGImage, pixelScale: CGFloat, annotations: [Annotation]) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(image.height))
        ctx.scaleBy(x: pixelScale, y: -pixelScale)
        let size = CGSize(width: CGFloat(image.width) / pixelScale, height: CGFloat(image.height) / pixelScale)
        draw(image: image, pointSize: size, annotations: annotations, in: ctx)
        return ctx.makeImage()
    }

    // MARK: - Pieces

    private static func drawImage(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    private static func stroke(_ ctx: CGContext, _ a: Annotation, _ body: (CGContext) -> Void) {
        ctx.saveGState()
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setLineWidth(a.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        body(ctx)
        ctx.restoreGState()
    }

    /// Rectangle or ellipse with its outline / hatch / solid interior.
    private static func drawShape(_ a: Annotation, ctx: CGContext) {
        let r = a.rect
        guard r.width > 0, r.height > 0 else { return }
        let path: CGPath
        if a.kind == .ellipse {
            path = CGPath(ellipseIn: r, transform: nil)
        } else if a.rounded {
            let radius = min(10, r.width / 2, r.height / 2)
            path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        } else {
            path = CGPath(rect: r, transform: nil)
        }
        ctx.saveGState()
        switch a.fill {
        case .outline:
            break
        case .solid:
            ctx.setFillColor(a.color.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        case .hatch:
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.setStrokeColor(a.color.withAlphaComponent(0.75).cgColor)
            ctx.setLineWidth(max(1, a.lineWidth / 2))
            let gap = max(6, a.lineWidth * 2.5)
            var k = -r.height
            while k < r.width {
                ctx.move(to: CGPoint(x: r.minX + k, y: r.maxY))
                ctx.addLine(to: CGPoint(x: r.minX + k + r.height, y: r.minY))
                k += gap
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
        if a.sketchy {
            ctx.restoreGState()
            if a.kind == .ellipse {
                // One loose marker loop whose ends cross, like drawing a circle round something by hand.
                let loop = Sketch.loopPoints(r, seed: Sketch.seed(a))
                ctx.saveGState()
                ctx.setStrokeColor(a.color.cgColor)
                ctx.setLineWidth(max(2, a.lineWidth * 1.3))
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                if let first = loop.first {
                    ctx.move(to: first)
                    for p in loop.dropFirst() { ctx.addLine(to: p) }
                    ctx.strokePath()
                }
                ctx.restoreGState()
            } else {
                sketchStroke(a, Sketch.rectPoints(r), closed: true, ctx: ctx)
            }
            return
        }
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setLineWidth(a.lineWidth)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Two slightly different wobbly passes over the same outline.
    private static func sketchStroke(_ a: Annotation, _ pts: [CGPoint], closed: Bool, ctx: CGContext) {
        let amplitude = 0.8 + a.lineWidth * 0.18
        for pass in 0..<2 {
            let wobbly = Sketch.polyline(pts, closed: closed, seed: Sketch.seed(a) ^ UInt64(pass + 1) &* 0x9E3779B97F4A7C15, amplitude: amplitude)
            guard let first = wobbly.first else { continue }
            ctx.saveGState()
            ctx.setStrokeColor(a.color.cgColor)
            ctx.setLineWidth(max(1, a.lineWidth * 0.8))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: first)
            for p in wobbly.dropFirst() { ctx.addLine(to: p) }
            if closed { ctx.closePath() }
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    private static func drawArrow(_ a: Annotation, ctx: CGContext) {
        let headLength = max(12, a.lineWidth * 4)
        let spread = CGFloat.pi / 7
        let curved = a.bend != 0
        let control = a.arrowControl
        let endFrom = curved ? control : a.start   // the head at `end` points along this direction
        let startFrom = curved ? control : a.end
        let closedHead = a.arrowHead != .thin
        let short = hypot(a.end.x - a.start.x, a.end.y - a.start.y) < headLength * 1.5

        /// Where the shaft meets the back of a closed head, so the stroke doesn't poke through it.
        func base(of tip: CGPoint, from: CGPoint) -> CGPoint {
            let theta = atan2(tip.y - from.y, tip.x - from.x), d = headLength * cos(spread)
            return CGPoint(x: tip.x - d * cos(theta), y: tip.y - d * sin(theta))
        }
        let shaftEnd = closedHead && !short ? base(of: a.end, from: endFrom) : a.end
        let shaftStart = closedHead && !short && a.arrowHead == .double ? base(of: a.start, from: startFrom) : a.start

        ctx.saveGState()
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setFillColor(a.color.cgColor)
        ctx.setLineWidth(a.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if a.tapered && a.arrowHead != .double {
            // Thin at the tail, heavier towards the head.
            let steps = 28
            var left: [CGPoint] = [], right: [CGPoint] = []
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps), u = 1 - t
                let pt: CGPoint, tangent: CGPoint
                if curved {
                    pt = CGPoint(x: u * u * shaftStart.x + 2 * u * t * control.x + t * t * shaftEnd.x,
                                 y: u * u * shaftStart.y + 2 * u * t * control.y + t * t * shaftEnd.y)
                    tangent = CGPoint(x: 2 * u * (control.x - shaftStart.x) + 2 * t * (shaftEnd.x - control.x),
                                      y: 2 * u * (control.y - shaftStart.y) + 2 * t * (shaftEnd.y - control.y))
                } else {
                    pt = CGPoint(x: shaftStart.x + (shaftEnd.x - shaftStart.x) * t, y: shaftStart.y + (shaftEnd.y - shaftStart.y) * t)
                    tangent = CGPoint(x: shaftEnd.x - shaftStart.x, y: shaftEnd.y - shaftStart.y)
                }
                let len = max(0.0001, hypot(tangent.x, tangent.y))
                let half = a.lineWidth * (0.15 + 0.75 * t) * 1.2
                let nx = -tangent.y / len * half, ny = tangent.x / len * half
                left.append(CGPoint(x: pt.x + nx, y: pt.y + ny))
                right.append(CGPoint(x: pt.x - nx, y: pt.y - ny))
            }
            ctx.move(to: left[0])
            for p in left.dropFirst() { ctx.addLine(to: p) }
            for p in right.reversed() { ctx.addLine(to: p) }
            ctx.closePath()
            ctx.fillPath()
        } else if a.sketchy {
            ctx.restoreGState()
            ctx.saveGState()
            sketchStroke(a, curved ? Geometry.quadPoints(shaftStart, control, shaftEnd) : [shaftStart, shaftEnd], closed: false, ctx: ctx)
            ctx.setStrokeColor(a.color.cgColor)
            ctx.setFillColor(a.color.cgColor)
            ctx.setLineWidth(a.lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
        } else {
            ctx.move(to: shaftStart)
            if curved { ctx.addQuadCurve(to: shaftEnd, control: control) } else { ctx.addLine(to: shaftEnd) }
            ctx.strokePath()
        }

        func head(at tip: CGPoint, from: CGPoint) {
            let (p1, p2) = Geometry.arrowHead(from: from, to: tip, length: headLength, spread: spread)
            switch a.arrowHead {
            case .normal, .double:
                ctx.move(to: tip); ctx.addLine(to: p1); ctx.addLine(to: p2); ctx.closePath(); ctx.fillPath()
            case .hollow:
                ctx.move(to: tip); ctx.addLine(to: p1); ctx.addLine(to: p2); ctx.closePath(); ctx.strokePath()
            case .thin:
                ctx.move(to: p1); ctx.addLine(to: tip); ctx.addLine(to: p2); ctx.strokePath()
            }
        }
        head(at: a.end, from: endFrom)
        if a.arrowHead == .double { head(at: a.start, from: startFrom) }
        ctx.restoreGState()
    }

    private static func drawSpotlight(_ a: Annotation, full: CGRect, ctx: CGContext) {
        let r = a.rect
        guard r.width > 0, r.height > 0 else { return }
        let hole: CGPath = a.oval ? CGPath(ellipseIn: r, transform: nil)
            : CGPath(roundedRect: r, cornerWidth: min(6, r.width / 2), cornerHeight: min(6, r.height / 2), transform: nil)
        ctx.saveGState()
        let path = CGMutablePath()
        path.addRect(full)
        path.addPath(hole)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.withAlphaComponent(CGFloat(min(9, max(1, a.level))) / 10).cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setLineWidth(max(1.5, a.lineWidth / 2))
        ctx.addPath(hole)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Speech-bubble numeral: a filled circle with a small tail pointing down-left.
    private static func drawCounter(_ a: Annotation, ctx: CGContext) {
        let body = a.bounds
        let d = body.height, w = body.width, centre = CGPoint(x: body.midX, y: body.midY)
        let tailAngle = a.angle  // y grows downwards here; the default points down and to the left
        let spread: CGFloat = 0.55
        // A circle for short text, a capsule for "1.2.3"; the pointer leaves from the matching outline.
        func onCircle(_ angle: CGFloat) -> CGPoint { CGPoint(x: centre.x + w / 2 * cos(angle), y: centre.y + d / 2 * sin(angle)) }
        let tip = a.counterTail
        ctx.saveGState()
        ctx.setFillColor(a.color.cgColor)
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: d / 2, cornerHeight: d / 2, transform: nil))
        ctx.fillPath()
        ctx.move(to: onCircle(tailAngle - spread))
        ctx.addLine(to: tip)
        ctx.addLine(to: onCircle(tailAngle + spread))
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: d * 0.54), .foregroundColor: a.labelTextColor,
        ]
        let label = NSString(string: a.counterText)
        let size = label.size(withAttributes: attrs)
        withFlippedGraphics(ctx) {
            label.draw(at: CGPoint(x: centre.x - size.width / 2, y: centre.y - size.height / 2), withAttributes: attrs)
        }
    }

    private static func drawText(_ a: Annotation, ctx: CGContext) {
        if a.pill {
            let box = a.bounds
            ctx.saveGState()
            ctx.setFillColor(a.color.cgColor)
            let radius = min(box.height / 2, 10)
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: a.textFont, .foregroundColor: a.labelTextColor,
            ]
            withFlippedGraphics(ctx) {
                NSString(string: a.text).draw(
                    at: CGPoint(x: box.minX + Annotation.pillPadding.width, y: box.minY + Annotation.pillPadding.height),
                    withAttributes: attrs)
            }
            return
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: a.textFont, .foregroundColor: a.color,
        ]
        withFlippedGraphics(ctx) {
            NSString(string: a.text).draw(at: a.start, withAttributes: attrs)
        }
    }

    /// Measurement line with end ticks and a pixel-length label.
    private static func drawRuler(_ a: Annotation, pixelScale: CGFloat, ctx: CGContext) {
        let dx = a.end.x - a.start.x, dy = a.end.y - a.start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return }
        let nx = -dy / length * 5, ny = dx / length * 5  // half-tick normal
        stroke(ctx, a) { c in
            c.setLineWidth(max(1.5, a.lineWidth / 2))
            c.move(to: a.start); c.addLine(to: a.end)
            c.move(to: CGPoint(x: a.start.x - nx, y: a.start.y - ny)); c.addLine(to: CGPoint(x: a.start.x + nx, y: a.start.y + ny))
            c.move(to: CGPoint(x: a.end.x - nx, y: a.end.y - ny)); c.addLine(to: CGPoint(x: a.end.x + nx, y: a.end.y + ny))
            c.strokePath()
        }
        let inPoints = a.level == 1
        let label = NSString(string: "\(Int((length * (inPoints ? 1 : pixelScale)).rounded())) \(inPoints ? "pt" : "px")")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: a.labelTextColor,
        ]
        let size = label.size(withAttributes: attrs)
        let mid = CGPoint(x: (a.start.x + a.end.x) / 2, y: (a.start.y + a.end.y) / 2)
        let pill = CGRect(x: mid.x - size.width / 2 - 6, y: mid.y - size.height / 2 - 6 - 14,
                          width: size.width + 12, height: size.height + 4)
        ctx.saveGState()
        ctx.setFillColor(a.color.cgColor)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
        withFlippedGraphics(ctx) {
            label.draw(at: CGPoint(x: pill.minX + 6, y: pill.minY + 2), withAttributes: attrs)
        }
    }

    /// A ring around the source area, a connector, and a larger bubble showing that area magnified.
    private static func drawMagnifier(_ a: Annotation, image: CGImage, full: CGRect, ctx: CGContext) {
        let r = a.sourceRadius
        guard r > 4 else { return }
        let bc = a.bubbleCenter, br = a.bubbleRadius
        let zoom = br / r
        let ringWidth = max(2, a.lineWidth)

        // Connector between the two circles, along the line through their centres.
        let dist = hypot(bc.x - a.start.x, bc.y - a.start.y)
        if dist > r + br {
            let ux = (bc.x - a.start.x) / dist, uy = (bc.y - a.start.y) / dist
            ctx.saveGState()
            ctx.setStrokeColor(a.color.cgColor)
            ctx.setLineWidth(ringWidth)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            ctx.move(to: CGPoint(x: a.start.x + ux * r, y: a.start.y + uy * r))
            ctx.addLine(to: CGPoint(x: bc.x - ux * br, y: bc.y - uy * br))
            ctx.strokePath()
            ctx.restoreGState()
        }

        let bubble = CGRect(x: bc.x - br, y: bc.y - br, width: br * 2, height: br * 2)
        ctx.saveGState()
        ctx.addEllipse(in: bubble)
        ctx.clip()
        ctx.translateBy(x: bc.x, y: bc.y)
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.translateBy(x: -a.start.x, y: -a.start.y)
        drawImage(image, in: full, ctx: ctx)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setLineWidth(ringWidth)
        ctx.strokeEllipse(in: bubble)
        ctx.strokeEllipse(in: CGRect(x: a.start.x - r, y: a.start.y - r, width: r * 2, height: r * 2))
        ctx.restoreGState()
    }

    private static func withFlippedGraphics(_ ctx: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Blur / erase

    private static func drawBlur(_ a: Annotation, image: CGImage, pixelScale: CGFloat, ctx: CGContext) {
        let rect = a.rect
        guard rect.width >= 1, rect.height >= 1 else { return }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let pixelRect = CGRect(
            x: rect.minX * pixelScale, y: rect.minY * pixelScale,
            width: rect.width * pixelScale, height: rect.height * pixelScale
        ).integral.intersection(bounds)
        guard !pixelRect.isEmpty else { return }
        // Chunkier blocks for larger regions so text can't stay legible; the strength slider scales them.
        let strength = CGFloat(min(9, max(1, a.level))) / 5
        let block = max(4, max(8, 10 * pixelScale, min(pixelRect.width, pixelRect.height) / 4) * strength)

        let out: CGImage?
        switch a.blurMode {
        case .blur: out = pixelated(image, pixelRect: pixelRect, block: block)
        case .blurText: out = RegionEffects.blurredText(image, pixelRect: pixelRect, block: Int(block.rounded()))
        case .erase: out = RegionEffects.erased(image, pixelRect: pixelRect)
        case .eraseText: out = RegionEffects.erasedText(image, pixelRect: pixelRect)
        }
        guard let out else { return }
        let target = CGRect(
            x: pixelRect.minX / pixelScale, y: pixelRect.minY / pixelScale,
            width: pixelRect.width / pixelScale, height: pixelRect.height / pixelScale)
        drawImage(out, in: target, ctx: ctx)
    }

    /// Mosaic of `pixelRect` (pixel coordinates, top-left origin). Irreversible by construction:
    /// the original pixels are replaced, not overlaid.
    public static func pixelated(_ image: CGImage, pixelRect: CGRect, block: CGFloat) -> CGImage? {
        guard let crop = image.cropping(to: pixelRect) else { return nil }
        let input = CIImage(cgImage: crop)
        let filter = CIFilter.pixellate()
        filter.inputImage = input
        filter.scale = Float(block)
        filter.center = .zero
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return ciContext.createCGImage(output, from: input.extent)
    }
}
