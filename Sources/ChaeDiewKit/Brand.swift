import AppKit

/// Tenix-ChaeDiew's look: an ink-dark chrome, a pale text colour and one bright blue for "this is active".
/// Everything else (neutrals) is tinted towards the ink so the chrome reads as one material.
public enum Brand {
    private static func hex(_ v: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }

    public static let ink = hex(0x15171C)            // window chrome
    public static let inkRaised = hex(0x1D2027)      // panels and fields
    public static let inkHover = hex(0x2A2E37)       // hovered button
    public static let line = hex(0x2D323C)           // hairlines
    public static let text = hex(0xF5F7FA)
    public static let textMuted = hex(0xA3ABBA)      // 7.4:1 on ink
    public static let textFaint = hex(0x7C8494)      // 4.6:1 on ink (labels, hints)
    public static let accent = hex(0x1FA0FF)
    public static let accentSoft = hex(0x1FA0FF, alpha: 0.20)
    public static let positive = hex(0x4ADE80)
    public static let caution = hex(0xFBBF24)

    private static func image(_ base64: String) -> NSImage? {
        Data(base64Encoded: base64).flatMap { NSImage(data: $0) }
    }

    /// The wordmark with light lettering, for dark surfaces.
    public static var wordmarkOnDark: NSImage? { image(BrandAssets.wordmarkOnDarkBase64) }
    public static var wordmarkOnLight: NSImage? { image(BrandAssets.wordmarkOnLightBase64) }
    public static var markOnDark: NSImage? { image(BrandAssets.markOnDarkBase64) }
    public static var appIcon: NSImage? { image(BrandAssets.appIconBase64) }

    /// The viewfinder bracket mark drawn as a template image for the menu bar (the system tints it).
    public static func menuBarIcon(size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let s = rect.width / 512
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 392 * s, y: 178 * s))
            path.line(to: NSPoint(x: 392 * s, y: 120 * s))
            path.line(to: NSPoint(x: 120 * s, y: 120 * s))
            path.line(to: NSPoint(x: 120 * s, y: 392 * s))
            path.line(to: NSPoint(x: 392 * s, y: 392 * s))
            path.line(to: NSPoint(x: 392 * s, y: 334 * s))
            path.lineWidth = 76 * s
            path.lineJoinStyle = .round
            path.lineCapStyle = .butt
            NSColor.black.setStroke()
            path.stroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: (392 - 46) * s, y: (256 - 46) * s, width: 92 * s, height: 92 * s)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}
