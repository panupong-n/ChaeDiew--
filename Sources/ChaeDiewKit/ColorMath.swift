import AppKit

/// WCAG relative luminance and contrast, used to pick readable label text on any colour.
public enum ColorMath {
    public static func luminance(r: Double, g: Double, b: Double) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    public static func contrastRatio(_ l1: Double, _ l2: Double) -> Double {
        (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// APCA lightness contrast (Lc, APCA-W3 0.0.98G): about 60 is comfortable for body text, 75+ is good. Signed by polarity.
    public static func apca(text: (r: Int, g: Int, b: Int), background: (r: Int, g: Int, b: Int)) -> Double {
        func y(_ c: (r: Int, g: Int, b: Int)) -> Double {
            func lin(_ v: Int) -> Double { pow(Double(v) / 255, 2.4) }
            let l = 0.2126729 * lin(c.r) + 0.7151522 * lin(c.g) + 0.0721750 * lin(c.b)
            return l < 0.022 ? l + pow(0.022 - l, 1.414) : l   // soft clamp near black
        }
        let yt = y(text), yb = y(background)
        guard abs(yb - yt) >= 0.0005 else { return 0 }
        if yb > yt {
            let s = (pow(yb, 0.56) - pow(yt, 0.57)) * 1.14
            return s < 0.1 ? 0 : (s - 0.027) * 100
        }
        let s = (pow(yb, 0.65) - pow(yt, 0.62)) * 1.14
        return s > -0.1 ? 0 : (s + 0.027) * 100
    }

    /// WCAG 2.x contrast ratio between two 8-bit colours.
    public static func wcagRatio(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int)) -> Double {
        contrastRatio(luminance(r: Double(a.r) / 255, g: Double(a.g) / 255, b: Double(a.b) / 255),
                      luminance(r: Double(b.r) / 255, g: Double(b.g) / 255, b: Double(b.b) / 255))
    }

    public static func luminance(of color: NSColor) -> Double {
        let c = color.usingColorSpace(.sRGB) ?? .black
        return luminance(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }

    /// Black or white, whichever reads better on `background`.
    public static func readableText(on background: NSColor) -> NSColor {
        let l = luminance(of: background)
        return contrastRatio(l, 0) >= contrastRatio(l, 1) ? .black : .white
    }
}
