import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum Storage {
    /// `~/Pictures/Tenix-ChaeDiew`, created on demand.
    public static func defaultFolder() -> URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let folder = pictures.appendingPathComponent("Tenix-ChaeDiew", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Fixed Gregorian/POSIX formatting so file names don't depend on the user's calendar
    /// (a Buddhist-calendar locale would otherwise produce year 2569).
    public static func fileName(date: Date = Date(), ext: String = "png") -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Tenix-ChaeDiew \(formatter.string(from: date)).\(ext)"
    }

    /// 144 dpi for Retina images that are saved at full size, 72 otherwise (nil = leave the file's default).
    public static func dpi(pixelScale: CGFloat, settings: Settings = .shared) -> Double? {
        pixelScale > 1.01 && !settings.downscaleRetina ? 72 * Double(pixelScale) : nil
    }

    private static func dpiProperties(_ dpi: Double?) -> CFDictionary? {
        dpi.map { [kCGImagePropertyDPIWidth: $0, kCGImagePropertyDPIHeight: $0] as CFDictionary }
    }

    public static func pngData(from image: CGImage, dpi: Double? = nil) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, dpiProperties(dpi))
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    public static func jpegData(from image: CGImage, quality: Double, dpi: Double? = nil) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if let dpi { props[kCGImagePropertyDPIWidth] = dpi; props[kCGImagePropertyDPIHeight] = dpi }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    public static func encoded(_ image: CGImage, format: ImageFormat, quality: Double = 0.9, dpi: Double? = nil) -> Data? {
        format == .png ? pngData(from: image, dpi: dpi) : jpegData(from: image, quality: quality, dpi: dpi)
    }

    /// PNG for interface screenshots (flat colours, transparency), JPEG for photographic content.
    public static func autoFormat(for image: CGImage) -> ImageFormat {
        let longest = max(image.width, image.height)
        let f = min(1, 256.0 / Double(longest))
        guard let small = ImageOps.scaled(image, width: max(1, Int(Double(image.width) * f)), height: max(1, Int(Double(image.height) * f)), smooth: false),
              let b = RegionEffects.buffer(of: small, rect: CGRect(x: 0, y: 0, width: small.width, height: small.height))
        else { return .png }
        var colours = Set<UInt32>()
        for i in 0..<(b.width * b.height) {
            if b.px[i * 4 + 3] < 255 { return .png }  // transparency needs PNG
            colours.insert(UInt32(b.px[i * 4]) << 16 | UInt32(b.px[i * 4 + 1]) << 8 | UInt32(b.px[i * 4 + 2]))
        }
        return Double(colours.count) / Double(b.width * b.height) > 0.25 ? .jpeg : .png
    }

    /// The format to save `image` in under the user's settings.
    public static func resolveFormat(for image: CGImage, settings: Settings = .shared) -> ImageFormat {
        settings.autoFormat ? autoFormat(for: image) : settings.imageFormat
    }

    /// The image as it should be written to disk or uploaded: Retina screenshots optionally scaled down to 1×.
    public static func outputImage(_ image: CGImage, pixelScale: CGFloat, settings: Settings = .shared) -> CGImage {
        guard settings.downscaleRetina, pixelScale > 1.01 else { return image }
        let w = Int((Double(image.width) / Double(pixelScale)).rounded()), h = Int((Double(image.height) / Double(pixelScale)).rounded())
        return ImageOps.scaled(image, width: w, height: h) ?? image
    }

    /// Writes `image` in the format implied by the URL's extension (PNG unless .jpg/.jpeg).
    @discardableResult
    public static func save(_ image: CGImage, to url: URL, quality: Double = 0.9, dpi: Double? = nil) throws -> URL {
        let isJPEG = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        guard let data = encoded(image, format: isJPEG ? .jpeg : .png, quality: quality, dpi: dpi) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Picks a name that does not overwrite an existing file.
    public static func uniqueURL(in folder: URL, date: Date = Date(), ext: String = "png") -> URL {
        let base = fileName(date: date, ext: ext)
        var url = folder.appendingPathComponent(base)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(base.replacingOccurrences(of: ".\(ext)", with: " (\(n)).\(ext)"))
            n += 1
        }
        return url
    }
}
