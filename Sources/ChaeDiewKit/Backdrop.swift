import AppKit

/// An sRGB colour that can be stored in preferences.
public struct RGBColor: Codable, Equatable {
    public var r: Double, g: Double, b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    public init(_ r: Int, _ g: Int, _ b: Int) { self.init(r: Double(r) / 255, g: Double(g) / 255, b: Double(b) / 255) }
    public init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .black
        self.init(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }
    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    public var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

/// Everything about the frame put around a screenshot (padding, background, shadow, rounded corners).
public struct BackdropSpec: Codable, Equatable {
    public enum Kind: String, Codable { case none, solid, gradient, image }
    public enum GradientStyle: String, Codable, CaseIterable { case linear, radial, mesh }

    public var kind: Kind = .none
    public var colors: [RGBColor] = [RGBColor(56, 189, 248), RGBColor(37, 99, 235), RGBColor(6, 182, 212), RGBColor(30, 64, 175)]
    public var gradient: GradientStyle = .linear
    /// Linear gradient direction in degrees (0 = left→right, 90 = bottom→top).
    public var angle: Double = 315
    /// Space between the screenshot and the edge of the backdrop, in points.
    public var padding: Double = 48
    /// Shadow darkness 0…1 and blur radius in points.
    public var shadow: Double = 0.35
    public var shadowBlur: Double = 30
    /// Corner radius of the whole backdrop and of the screenshot, in points.
    public var outerRadius: Double = 0
    public var innerRadius: Double = 10
    public var imagePath: String?

    public init() {}

    public static let none = BackdropSpec()

    public var isOn: Bool { kind != .none }
    public var effectivePadding: Double { isOn ? padding : 0 }

    public static func solid(_ c: RGBColor) -> BackdropSpec {
        var s = BackdropSpec(); s.kind = .solid; s.colors = [c, c, c, c]; return s
    }

    public static func linear(_ a: RGBColor, _ b: RGBColor, angle: Double = 315) -> BackdropSpec {
        var s = BackdropSpec(); s.kind = .gradient; s.gradient = .linear; s.colors = [a, b, a, b]; s.angle = angle; return s
    }

    /// Named starting points shown as a swatch grid.
    public static let presets: [(name: String, spec: BackdropSpec)] = {
        func radial(_ a: RGBColor, _ b: RGBColor) -> BackdropSpec { var s = linear(a, b); s.gradient = .radial; return s }
        func mesh(_ a: RGBColor, _ b: RGBColor, _ c: RGBColor, _ d: RGBColor) -> BackdropSpec {
            var s = BackdropSpec(); s.kind = .gradient; s.gradient = .mesh; s.colors = [a, b, c, d]; return s
        }
        return [
            ("Ocean", linear(RGBColor(56, 189, 248), RGBColor(37, 99, 235))),
            ("Sky", linear(RGBColor(125, 211, 252), RGBColor(59, 130, 246))),
            ("Night", linear(RGBColor(30, 41, 59), RGBColor(2, 6, 23))),
            ("Sunset", linear(RGBColor(251, 146, 60), RGBColor(219, 39, 119))),
            ("Peach", linear(RGBColor(253, 186, 116), RGBColor(244, 114, 182))),
            ("Dawn", linear(RGBColor(254, 240, 138), RGBColor(147, 197, 253))),
            ("Violet", linear(RGBColor(167, 139, 250), RGBColor(99, 102, 241))),
            ("Mint", linear(RGBColor(167, 243, 208), RGBColor(16, 185, 129))),
            ("Rose", linear(RGBColor(253, 164, 175), RGBColor(244, 63, 94))),
            ("Slate", linear(RGBColor(148, 163, 184), RGBColor(51, 65, 85))),
            ("Light", linear(RGBColor(244, 246, 250), RGBColor(214, 220, 232))),
            ("Dark", linear(RGBColor(44, 48, 60), RGBColor(18, 20, 28))),
            ("Aurora", radial(RGBColor(34, 211, 238), RGBColor(79, 70, 229))),
            ("Glow", radial(RGBColor(250, 204, 21), RGBColor(220, 38, 38))),
            ("Candy mesh", mesh(RGBColor(244, 114, 182), RGBColor(129, 140, 248), RGBColor(52, 211, 153), RGBColor(251, 191, 36))),
            ("Ocean mesh", mesh(RGBColor(14, 165, 233), RGBColor(99, 102, 241), RGBColor(6, 182, 212), RGBColor(30, 64, 175))),
            ("White", solid(RGBColor(255, 255, 255))),
            ("Charcoal", solid(RGBColor(38, 40, 46))),
        ]
    }()

    /// New random colours, keeping every other setting.
    public mutating func randomizeColors() {
        func pick() -> RGBColor { RGBColor(r: .random(in: 0.1...0.95), g: .random(in: 0.1...0.95), b: .random(in: 0.1...0.95)) }
        colors = [pick(), pick(), pick(), pick()]
        if kind == .solid { colors = [colors[0], colors[0], colors[0], colors[0]] }
    }

    /// Reverses the colour order (a gradient run backwards).
    public mutating func swapColors() {
        colors = [colors[1], colors[0], colors[3], colors[2]]
    }

    // MARK: Remembering the last choice

    private static let storageKey = "backdropSpec"

    public static func loadSaved(defaults: UserDefaults = .standard) -> BackdropSpec {
        guard let data = defaults.data(forKey: storageKey), let spec = try? JSONDecoder().decode(BackdropSpec.self, from: data) else {
            return presets[0].spec
        }
        return spec
    }

    public func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

/// The original fixed styles, kept as shortcuts to presets.
public enum BackdropStyle: String, CaseIterable {
    case none, light, dark, ocean, sunset, violet

    public var title: String {
        switch self {
        case .none: return t("No backdrop")
        case .light: return t("Light")
        case .dark: return t("Dark")
        case .ocean: return t("Ocean")
        case .sunset: return t("Sunset")
        case .violet: return t("Violet")
        }
    }

    public var spec: BackdropSpec {
        func preset(_ name: String) -> BackdropSpec { BackdropSpec.presets.first { $0.name == name }!.spec }
        switch self {
        case .none: return .none
        case .light: return preset("Light")
        case .dark: return preset("Dark")
        case .ocean: return preset("Ocean")
        case .sunset: return preset("Sunset")
        case .violet: return preset("Violet")
        }
    }
}

/// Wraps a screenshot in padding, a background, rounded corners and a soft shadow (for docs and slides).
public enum Backdrop {
    private static var imageCache: [String: CGImage] = [:]

    static func backgroundImage(_ path: String?) -> CGImage? {
        guard let path, !path.isEmpty else { return nil }
        if let cached = imageCache[path] { return cached }
        guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        imageCache[path] = image
        return image
    }

    /// Paints the background into a context whose origin is bottom-left (flip it first when drawing into a flipped view).
    public static func drawBackground(_ spec: BackdropSpec, in ctx: CGContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = spec.colors.count >= 4 ? spec.colors : spec.colors + Array(repeating: spec.colors.last ?? RGBColor(255, 255, 255), count: 4 - spec.colors.count)
        switch spec.kind {
        case .none:
            return
        case .solid:
            ctx.setFillColor(c[0].cgColor)
            ctx.fill(rect)
        case .image:
            if let image = backgroundImage(spec.imagePath) {
                let s = max(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
                let w = CGFloat(image.width) * s, h = CGFloat(image.height) * s
                ctx.interpolationQuality = .high
                ctx.draw(image, in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
            } else {
                ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
                ctx.fill(rect)
            }
        case .gradient:
            switch spec.gradient {
            case .linear:
                guard let g = CGGradient(colorsSpace: space, colors: [c[0].cgColor, c[1].cgColor] as CFArray, locations: [0, 1]) else { return }
                let a = spec.angle * .pi / 180
                let half = (abs(size.width * cos(a)) + abs(size.height * sin(a))) / 2   // reaches both corners at any angle
                let mid = CGPoint(x: size.width / 2, y: size.height / 2)
                ctx.drawLinearGradient(
                    g, start: CGPoint(x: mid.x - cos(a) * half, y: mid.y - sin(a) * half),
                    end: CGPoint(x: mid.x + cos(a) * half, y: mid.y + sin(a) * half),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            case .radial:
                guard let g = CGGradient(colorsSpace: space, colors: [c[0].cgColor, c[1].cgColor] as CFArray, locations: [0, 1]) else { return }
                let mid = CGPoint(x: size.width / 2, y: size.height / 2)
                ctx.drawRadialGradient(g, startCenter: mid, startRadius: 0, endCenter: mid, endRadius: hypot(size.width, size.height) / 2,
                                       options: [.drawsAfterEndLocation])
            case .mesh:
                // Four corner colours blended smoothly: top-left, top-right, bottom-left, bottom-right.
                let n = 48
                var px = [UInt8](repeating: 255, count: n * n * 4)
                for y in 0..<n {
                    for x in 0..<n {
                        let u = Double(x) / Double(n - 1), v = Double(y) / Double(n - 1)   // y = 0 is the top row
                        func mix(_ k: Int) -> Double {
                            let comp: (RGBColor) -> Double = k == 0 ? { $0.r } : k == 1 ? { $0.g } : { $0.b }
                            let top = comp(c[0]) * (1 - u) + comp(c[1]) * u
                            let bottom = comp(c[2]) * (1 - u) + comp(c[3]) * u
                            return top * (1 - v) + bottom * v
                        }
                        let i = (y * n + x) * 4
                        px[i] = UInt8(max(0, min(255, mix(0) * 255))); px[i + 1] = UInt8(max(0, min(255, mix(1) * 255))); px[i + 2] = UInt8(max(0, min(255, mix(2) * 255)))
                    }
                }
                if let provider = CGDataProvider(data: Data(px) as CFData),
                   let img = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: space,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                                     decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
                    ctx.interpolationQuality = .high
                    ctx.draw(img, in: rect)
                }
            }
        }
    }

    /// Everything except the screenshot itself: background, shadow, and the screenshot's rounded silhouette.
    /// `imageRect` is where the screenshot goes (bottom-left origin).
    public static func drawFrame(_ spec: BackdropSpec, in ctx: CGContext, size: CGSize, imageRect: CGRect, scale: CGFloat) {
        let outer = spec.outerRadius * Double(scale)
        ctx.saveGState()
        if outer > 0 {
            ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: outer, cornerHeight: outer, transform: nil))
            ctx.clip()
        }
        drawBackground(spec, in: ctx, size: size)
        if spec.shadow > 0 {
            ctx.saveGState()  // fill an opaque shape so the blur has something to cast
            ctx.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: CGFloat(spec.shadowBlur) * scale,
                          color: CGColor(gray: 0, alpha: CGFloat(spec.shadow)))
            let inner = spec.innerRadius * Double(scale)
            ctx.addPath(CGPath(roundedRect: imageRect, cornerWidth: inner, cornerHeight: inner, transform: nil))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    public static func apply(to image: CGImage, spec: BackdropSpec, pixelScale: CGFloat) -> CGImage {
        guard spec.isOn else { return image }
        let pad = (CGFloat(spec.padding) * pixelScale).rounded()
        let width = image.width + Int(pad) * 2, height = image.height + Int(pad) * 2
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return image }
        let size = CGSize(width: width, height: height)
        let rect = CGRect(x: pad, y: pad, width: CGFloat(image.width), height: CGFloat(image.height))
        drawFrame(spec, in: ctx, size: size, imageRect: rect, scale: pixelScale)
        let inner = CGFloat(spec.innerRadius) * pixelScale
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: inner, cornerHeight: inner, transform: nil))
        ctx.clip()
        ctx.draw(image, in: rect)
        ctx.restoreGState()
        return ctx.makeImage() ?? image
    }

    /// The fixed-style entry point used before backdrops became customisable.
    public static func apply(
        to image: CGImage, style: BackdropStyle, pixelScale: CGFloat,
        padding: CGFloat = 48, cornerRadius: CGFloat = 10
    ) -> CGImage {
        var spec = style.spec
        spec.padding = Double(padding)
        spec.innerRadius = Double(cornerRadius)
        return apply(to: image, spec: spec, pixelScale: pixelScale)
    }

    /// A small swatch image of a preset, for the picker grid.
    public static func thumbnail(_ spec: BackdropSpec, size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil))
            ctx.clip()
            drawBackground(spec, in: ctx, size: rect.size)
            ctx.restoreGState()
            return true
        }
    }
}
