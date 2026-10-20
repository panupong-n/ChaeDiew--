import CoreGraphics

/// Whole-image operations used by Add Capture, auto-expanding canvas and Rasterize.
public enum ImageOps {
    public enum Edge { case right, bottom }

    private static func context(width: Int, height: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    /// `image` resampled to a new pixel size.
    public static func scaled(_ image: CGImage, width: Int, height: Int, smooth: Bool = true) -> CGImage? {
        guard width > 0, height > 0, let ctx = context(width: width, height: height) else { return nil }
        ctx.interpolationQuality = smooth ? .high : .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// The image laid over a solid colour (removes transparency: window corners, shadows).
    public static func flattened(_ image: CGImage, onto fill: (r: UInt8, g: UInt8, b: UInt8)) -> CGImage? {
        guard let ctx = context(width: image.width, height: image.height) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: CGFloat(fill.r) / 255, green: CGFloat(fill.g) / 255, blue: CGFloat(fill.b) / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    /// `foreground` centred on `background` (scaled to fill, cropped) with `margin` pixels of background all round:
    /// a window screenshot over the desktop picture.
    public static func over(_ foreground: CGImage, background: CGImage, margin: Int) -> CGImage? {
        let w = foreground.width + margin * 2, h = foreground.height + margin * 2
        guard let ctx = context(width: w, height: h) else { return nil }
        let scale = max(CGFloat(w) / CGFloat(background.width), CGFloat(h) / CGFloat(background.height))
        let bw = CGFloat(background.width) * scale, bh = CGFloat(background.height) * scale
        ctx.interpolationQuality = .high
        ctx.draw(background, in: CGRect(x: (CGFloat(w) - bw) / 2, y: (CGFloat(h) - bh) / 2, width: bw, height: bh))
        ctx.draw(foreground, in: CGRect(x: margin, y: margin, width: foreground.width, height: foreground.height))
        return ctx.makeImage()
    }

    /// Most common colour along the image's outer 2-pixel frame, so new canvas area blends with the screenshot.
    public static func edgeColor(of image: CGImage) -> (r: UInt8, g: UInt8, b: UInt8) {
        guard let b = RegionEffects.buffer(of: image, rect: CGRect(x: 0, y: 0, width: image.width, height: image.height)) else { return (255, 255, 255) }
        var frame: [Int] = []
        for y in 0..<b.height {
            for x in 0..<b.width where x < 2 || y < 2 || x >= b.width - 2 || y >= b.height - 2 { frame.append(y * b.width + x) }
        }
        return RegionEffects.dominantColor(b.px, indices: frame)
    }

    /// The image with extra pixels on each side (top-left coordinates), filled with `fill`.
    public static func padded(
        _ image: CGImage, left: Int, top: Int, right: Int, bottom: Int, fill: (r: UInt8, g: UInt8, b: UInt8)
    ) -> CGImage? {
        let w = image.width + left + right, h = image.height + top + bottom
        guard let ctx = context(width: w, height: h) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: CGFloat(fill.r) / 255, green: CGFloat(fill.g) / 255, blue: CGFloat(fill.b) / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // CoreGraphics' origin is bottom-left, so "bottom padding" is where the image's y starts.
        ctx.draw(image, in: CGRect(x: left, y: bottom, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    /// `new` placed next to `base` (to its right, or below it), top/left aligned, on the base's edge colour.
    public static func appended(_ new: CGImage, to base: CGImage, edge: Edge) -> CGImage? {
        let fill = edgeColor(of: base)
        let w = edge == .right ? base.width + new.width : max(base.width, new.width)
        let h = edge == .right ? max(base.height, new.height) : base.height + new.height
        guard let ctx = context(width: w, height: h) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: CGFloat(fill.r) / 255, green: CGFloat(fill.g) / 255, blue: CGFloat(fill.b) / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(base, in: CGRect(x: 0, y: h - base.height, width: base.width, height: base.height))
        if edge == .right {
            ctx.draw(new, in: CGRect(x: base.width, y: h - new.height, width: new.width, height: new.height))
        } else {
            ctx.draw(new, in: CGRect(x: 0, y: 0, width: new.width, height: new.height))
        }
        return ctx.makeImage()
    }

    /// Below when the new capture is about as wide as the base (a taller page), otherwise beside it.
    public static func preferredEdge(base: CGImage, new: CGImage) -> Edge {
        abs(Double(new.width) - Double(base.width)) <= Double(base.width) * 0.15 ? .bottom : .right
    }
}
