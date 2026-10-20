import Foundation

public enum ColorFormat: String, CaseIterable {
    case hex, rgb, hsl, oklch
}

/// Colour conversions for the colour picker. Inputs are sRGB components in 0...1.
public enum ColorFormats {
    public static func string(r: Double, g: Double, b: Double, format: ColorFormat) -> String {
        switch format {
        case .hex:
            return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
        case .rgb:
            return "rgb(\(byte(r)), \(byte(g)), \(byte(b)))"
        case .hsl:
            let c = hsl(r: r, g: g, b: b)
            return String(format: "hsl(%.0f, %.0f%%, %.0f%%)", c.h, c.s * 100, c.l * 100)
        case .oklch:
            let c = oklch(r: r, g: g, b: b)
            return String(format: "oklch(%.1f%% %.3f %.1f)", c.l * 100, c.c, c.h)
        }
    }

    private static func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }

    public static func hsl(r: Double, g: Double, b: Double) -> (h: Double, s: Double, l: Double) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let l = (mx + mn) / 2
        let d = mx - mn
        guard d > 0 else { return (0, 0, l) }
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        switch mx {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h *= 60
        return (h, s, l)
    }

    /// OKLCH via Björn Ottosson's OKLab matrices. Hue is in degrees; achromatic colours report hue 0.
    public static func oklch(r: Double, g: Double, b: Double) -> (l: Double, c: Double, h: Double) {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let lr = linear(r), lg = linear(g), lb = linear(b)
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let chroma = hypot(a, bb)
        var hue = atan2(bb, a) * 180 / .pi
        if hue < 0 { hue += 360 }
        return (L, chroma, chroma < 1e-4 ? 0 : hue)
    }
}
