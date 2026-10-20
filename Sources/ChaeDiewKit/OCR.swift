import AppKit
import Vision

/// One recognized line plus the means to locate any substring of it in the image.
public struct RecognizedLine {
    public let text: String
    let candidate: VNRecognizedText
    let imageSize: CGSize

    /// Pixel rectangle (top-left origin) covering `range` of `text`.
    public func pixelRect(for range: Range<String.Index>) -> CGRect? {
        guard let box = try? candidate.boundingBox(for: range)?.boundingBox else { return nil }
        return CGRect(
            x: box.minX * imageSize.width, y: (1 - box.maxY) * imageSize.height,
            width: box.width * imageSize.width, height: box.height * imageSize.height)
    }
}

/// Every Vision request runs on this one serial queue. Concurrent text-recognition requests were observed to
/// hang inside the app (e.g. OCR from the editor while the library indexes a new capture), so they never overlap.
private let visionQueue = DispatchQueue(label: "chaediew.vision", qos: .userInitiated)

public enum OCR {
    /// The first Vision request in a process spends ~10 s loading its models. Doing one tiny request in the
    /// background at launch means the user's first real OCR / Hide PII is instant instead.
    public static func warmUp() async {
        // It must contain real text: with nothing to read, Vision skips loading the recognizer.
        guard let ctx = CGContext(
            data: nil, width: 420, height: 90, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 420, height: 90))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSString(string: "Hello Tenix-ChaeDiew 123").draw(at: CGPoint(x: 14, y: 26), withAttributes: [
            .font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { return }
        _ = try? await recognizeLines(image, languages: [])
    }

    /// On-device text recognition with Apple's Vision framework; nothing leaves the machine.
    /// Empty `languages` means automatic detection.
    public static func recognizeLines(_ image: CGImage, languages: [String] = Settings.shared.ocrLanguageList) async throws -> [RecognizedLine] {
        try await withCheckedThrowingContinuation { continuation in
            visionQueue.async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                if languages.isEmpty {
                    request.automaticallyDetectsLanguage = true
                } else {
                    request.automaticallyDetectsLanguage = false
                    request.recognitionLanguages = languages
                }
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    let size = CGSize(width: image.width, height: image.height)
                    let lines = (request.results ?? []).compactMap { obs -> RecognizedLine? in
                        guard let top = obs.topCandidates(1).first else { return nil }
                        return RecognizedLine(text: top.string, candidate: top, imageSize: size)
                    }
                    continuation.resume(returning: lines)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func recognize(_ image: CGImage) async throws -> String {
        let lines = try await recognizeLines(image)
        let separator = Settings.shared.ocrRemoveBreaks ? " " : "\n"
        return lines.map(\.text).joined(separator: separator)
    }
}

public enum Barcode {
    /// Payloads of every QR code / barcode Vision can find.
    public static func detect(in image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            visionQueue.async {
                let request = VNDetectBarcodesRequest()
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    continuation.resume(returning: (request.results ?? []).compactMap(\.payloadStringValue))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
