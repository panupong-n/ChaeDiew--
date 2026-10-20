import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Two-frame "before / after" GIF.
public enum GIFExport {
    /// Both frames share one size (the larger of the two); a smaller frame is centred on the other's edge colour.
    public static func beforeAfter(before: CGImage, after: CGImage, seconds: Double = 1.2) -> Data? {
        let w = max(before.width, after.width), h = max(before.height, after.height)
        func frame(_ image: CGImage) -> CGImage? {
            if image.width == w, image.height == h { return image }
            let fill = ImageOps.edgeColor(of: image)
            return ImageOps.padded(image, left: (w - image.width) / 2, top: (h - image.height) / 2,
                                   right: w - image.width - (w - image.width) / 2, bottom: h - image.height - (h - image.height) / 2, fill: fill)
        }
        guard let a = frame(before), let b = frame(after) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil) else { return nil }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: seconds]] as CFDictionary
        CGImageDestinationAddImage(dest, a, props)
        CGImageDestinationAddImage(dest, b, props)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
