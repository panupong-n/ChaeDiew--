import AppKit
import ChaeDiewLicense
import CryptoKit
import ImageIO
import ChaeDiewKit

var failures = 0

// `ChaeDiewChecks --upload-e2e <port>` talks to scripts/fake-s3.py, whose Python signer verifies our requests.
if let i = CommandLine.arguments.firstIndex(of: "--upload-e2e"), CommandLine.arguments.count > i + 1 {
    let port = CommandLine.arguments[i + 1]
    func ok(_ name: String, _ cond: Bool) { print(cond ? "PASS  \(name)" : "FAIL  \(name)"); if !cond { failures += 1 } }
    let payload = Data((0..<5000).map { UInt8(truncatingIfNeeded: $0 &* 31) })

    let config = S3Config(endpoint: "http://127.0.0.1:\(port)", region: "us-east-1", bucket: "chaediew", prefix: "team shots",
                          accessKey: "AKIAFAKEFAKEFAKE", secretKey: "fakeSecret/KEY+for/testing", expirySeconds: 600)
    do {
        let link = try await Uploader.uploadS3(payload, fileName: "Shot 2026-10-19 at 12.00.png", contentType: "image/png", config: config)
        ok("S3 PUT accepted: the independent Python verifier agrees with our signature", true)
        let (body, response) = try await URLSession.shared.data(from: link)
        ok("presigned link downloads the same bytes", (response as? HTTPURLResponse)?.statusCode == 200 && body == payload)
        var tampered = URLComponents(url: link, resolvingAgainstBaseURL: false)!
        tampered.queryItems = tampered.queryItems?.map { $0.name == "X-Amz-Expires" ? URLQueryItem(name: $0.name, value: "999999") : $0 }
        let (_, bad) = try await URLSession.shared.data(from: tampered.url!)
        ok("a tampered presigned link is rejected", (bad as? HTTPURLResponse)?.statusCode == 403)
        ok("object key is unguessable and keeps the folder prefix", link.path.hasPrefix("/chaediew/team%20shots/") || link.path.hasPrefix("/chaediew/team shots/"))
    } catch {
        ok("S3 upload (\(error))", false)
    }

    let wrong = S3Config(endpoint: "http://127.0.0.1:\(port)", region: "us-east-1", bucket: "chaediew",
                         accessKey: "AKIAFAKEFAKEFAKE", secretKey: "WRONG-secret")
    do { _ = try await Uploader.uploadS3(payload, fileName: "x.png", contentType: "image/png", config: wrong); ok("wrong secret is rejected", false) }
    catch UploadError.server(let code, _) { ok("wrong secret is rejected (HTTP \(code))", code == 403) }
    catch { ok("wrong secret is rejected (\(error))", false) }

    let suite = UserDefaults(suiteName: "chaediew.e2e")!
    suite.removePersistentDomain(forName: "chaediew.e2e")
    suite.set("http://127.0.0.1:\(port)/upload", forKey: Settings.Key.httpURL)
    let s = Settings(defaults: suite)
    do {
        let link = try await Uploader.uploadHTTP(payload, fileName: "a b.png", contentType: "image/png", settings: s, token: "secret-token")
        let (body, _) = try await URLSession.shared.data(from: link)
        ok("HTTP endpoint upload returns a working link", body == payload)
    } catch { ok("HTTP upload (\(error))", false) }
    do { _ = try await Uploader.uploadHTTP(payload, fileName: "x.png", contentType: "image/png", settings: s, token: "nope"); ok("bad token is rejected", false) }
    catch UploadError.server(let code, _) { ok("bad token is rejected (HTTP \(code))", code == 401) }
    catch { ok("bad token is rejected (\(error))", false) }
    suite.removePersistentDomain(forName: "chaediew.e2e")

    print(failures == 0 ? "\nAll upload checks passed." : "\n\(failures) upload check(s) failed.")
    exit(failures == 0 ? 0 : 1)
}
func check(_ name: String, _ ok: @autoclosure () -> Bool) {
    if ok() { print("PASS  \(name)") } else { print("FAIL  \(name)"); failures += 1 }
}

// MARK: - Image helpers

func solidImage(width: Int, height: Int, gray: CGFloat = 1) -> CGImage {
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.setFillColor(CGColor(gray: gray, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

/// RGB of one pixel; (0,0) is the image's top-left.
func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
    var bytes = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(
        data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
}

/// A tall "web page": every row is distinct, with blank bands so background handling is exercised.
func makePage(width: Int, height: Int, seed: UInt64 = 0x9E37_79B9_7F4A_7C15) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    var state: UInt64 = seed
    for y in 0..<height {
        let blank = (300..<340).contains(y) || (900..<960).contains(y)
        if blank { continue }
        for x in 0..<width {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let v = UInt8(truncatingIfNeeded: state >> 33)
            let i = (y * width + x) * 4
            bytes[i] = v; bytes[i + 1] = v &+ 40; bytes[i + 2] = v &+ 90; bytes[i + 3] = 255
        }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

func frame(of page: CGImage, offset: Int, height: Int, stickyHeader: CGImage? = nil) -> CGImage {
    let crop = page.cropping(to: CGRect(x: 0, y: offset, width: page.width, height: height))!
    guard let header = stickyHeader else { return crop }
    let ctx = CGContext(
        data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
    ctx.draw(header, in: CGRect(x: 0, y: crop.height - header.height, width: header.width, height: header.height))
    return ctx.makeImage()!
}

// MARK: - Geometry & annotations

let r = Geometry.normalizedRect(from: CGPoint(x: 50, y: 40), to: CGPoint(x: 10, y: 90))
check("normalizedRect from any corner", r == CGRect(x: 10, y: 40, width: 40, height: 50))
let (h1, h2) = Geometry.arrowHead(from: .zero, to: CGPoint(x: 100, y: 0), length: 10)
check("arrow head sits behind the tip", h1.x < 100 && h2.x < 100)
check("arrow head is symmetric about the shaft", abs(h1.y + h2.y) < 0.0001)

let line = Annotation(kind: .line, start: .zero, end: CGPoint(x: 100, y: 0))
check("line hit test: near hits, far misses", line.hitTest(CGPoint(x: 50, y: 3)) && !line.hitTest(CGPoint(x: 50, y: 30)))
let box = Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 110, y: 110))
check("rectangle hit test: border hits, hollow centre misses", box.hitTest(CGPoint(x: 10, y: 60)) && !box.hitTest(CGPoint(x: 60, y: 60)))
let oval = Annotation(kind: .ellipse, start: .zero, end: CGPoint(x: 100, y: 50))
check("ellipse hit test: rim hits, centre misses", oval.hitTest(CGPoint(x: 50, y: 0)) && !oval.hitTest(CGPoint(x: 50, y: 25)))
let pen = Annotation(kind: .freehand, start: .zero, end: .zero, points: [CGPoint(x: 5, y: 5), CGPoint(x: 40, y: 20), CGPoint(x: 10, y: 60)])
check("freehand bounds cover all points", pen.bounds == CGRect(x: 5, y: 5, width: 35, height: 55))
check("freehand hit test follows the stroke", pen.hitTest(CGPoint(x: 22, y: 12)) && !pen.hitTest(CGPoint(x: 90, y: 90)))
let moved = box.translated(by: CGPoint(x: 5, y: -5))
check("translated moves both corners", moved.start == CGPoint(x: 15, y: 5) && moved.end == CGPoint(x: 115, y: 105))
check("scaled scales coordinates", box.scaled(by: 2).end == CGPoint(x: 220, y: 220))
check("counter is a fixed-size circle", Annotation(kind: .counter, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 50, y: 50)).bounds.width == Annotation.counterDiameter)

// MARK: - Storage

let name = Storage.fileName(date: Date(timeIntervalSince1970: 1_792_411_200))
check("file name uses Gregorian year (not 2569)", name.hasPrefix("Tenix-ChaeDiew 2026-10-") && name.hasSuffix(".png"))
let png = Storage.pngData(from: solidImage(width: 8, height: 6))
let rep = png.flatMap { NSBitmapImageRep(data: $0) }
check("PNG round-trip keeps pixel size", rep?.pixelsWide == 8 && rep?.pixelsHigh == 6)
let jpeg = Storage.encoded(solidImage(width: 8, height: 6), format: .jpeg, quality: 0.8)
check("JPEG encode works and keeps size", jpeg.flatMap { NSBitmapImageRep(data: $0) }?.pixelsWide == 8)
let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let now = Date()
let first = Storage.uniqueURL(in: dir, date: now)
try? Data().write(to: first)
check("uniqueURL never overwrites", Storage.uniqueURL(in: dir, date: now) != first)
let jpgURL = try? Storage.save(solidImage(width: 4, height: 4), to: dir.appendingPathComponent("a.jpg"))
check("save picks JPEG from the extension", jpgURL.flatMap { try? Data(contentsOf: $0) }.map { $0.prefix(2) == Data([0xFF, 0xD8]) } ?? false)
try? FileManager.default.removeItem(at: dir)

// MARK: - Renderer

let big = AnnotationRenderer.export(image: solidImage(width: 200, height: 100), pixelScale: 2, annotations: [])
check("export keeps native pixel size on 2x images", big?.width == 200 && big?.height == 100)

let tint = Annotation(kind: .highlight, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 40, y: 40), color: .red)
if let out = AnnotationRenderer.export(image: solidImage(width: 100, height: 100), pixelScale: 1, annotations: [tint]) {
    let inside = pixel(out, x: 20, y: 20), outside = pixel(out, x: 80, y: 80)
    check("highlight tints its region", inside.r > 200 && inside.g < 200)
    check("highlight leaves the rest untouched", outside == (255, 255, 255))
} else { check("highlight export", false) }

let top = Annotation(kind: .highlight, start: .zero, end: CGPoint(x: 100, y: 20), color: .blue)
if let out = AnnotationRenderer.export(image: solidImage(width: 100, height: 100), pixelScale: 1, annotations: [top]) {
    check("annotations use a top-left origin (top tinted)", pixel(out, x: 50, y: 5).r < 200)
    check("annotations use a top-left origin (bottom clean)", pixel(out, x: 50, y: 95) == (255, 255, 255))
} else { check("origin export", false) }

let dim = Annotation(kind: .spotlight, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 60, y: 60))
if let out = AnnotationRenderer.export(image: solidImage(width: 100, height: 100), pixelScale: 1, annotations: [dim]) {
    check("spotlight keeps its window bright", pixel(out, x: 50, y: 50).r > 240)
    check("spotlight dims everything else", pixel(out, x: 5, y: 5).r < 150)
} else { check("spotlight export", false) }

let scribble = Annotation(kind: .freehand, start: .zero, end: .zero,
                          points: [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)], color: .black, lineWidth: 6)
if let out = AnnotationRenderer.export(image: solidImage(width: 100, height: 100), pixelScale: 1, annotations: [scribble]) {
    check("freehand strokes along its points", pixel(out, x: 50, y: 50).r < 60 && pixel(out, x: 50, y: 10).r > 240)
} else { check("freehand export", false) }

// Pixelate must destroy the original detail, not just cover it.
let ctx = CGContext(
    data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 29, height: 64))
if let edge = ctx.makeImage(),
   let mosaic = AnnotationRenderer.pixelated(edge, pixelRect: CGRect(x: 0, y: 0, width: 64, height: 64), block: 16) {
    let row = (0..<64).map { pixel(mosaic, x: $0, y: 32).r }
    // Original: black for x<29, white from x=29. Block 16..<32 straddled that edge.
    check("pixelate flattens each block", Set(row[16..<32]).count == 1)
    check("pixelate output keeps its size", mosaic.width == 64 && mosaic.height == 64)
} else { check("pixelate", false) }

// MARK: - Editor canvas (undo / redo / crop / resize / pixelation)

let canvas = CanvasView(image: solidImage(width: 400, height: 200), pixelScale: 2)
check("canvas size is the image in points", canvas.pointSize == CGSize(width: 200, height: 100))
check("fresh canvas has nothing to undo", !canvas.canUndo && !canvas.canRedo)
let rectMark = Annotation(kind: .rectangle, start: CGPoint(x: 50, y: 20), end: CGPoint(x: 90, y: 40))
canvas.append(rectMark)
check("append adds a mark and enables undo", canvas.state.annotations.count == 1 && canvas.canUndo)
canvas.undo()
check("undo removes it and enables redo", canvas.state.annotations.isEmpty && canvas.canRedo)
canvas.redo()
check("redo brings it back", canvas.state.annotations.count == 1)
canvas.append(Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 10, y: 10)))
canvas.undo()
canvas.append(Annotation(kind: .line, start: .zero, end: CGPoint(x: 5, y: 5)))
check("a new edit after undo clears redo", !canvas.canRedo && canvas.state.annotations.count == 2)

canvas.resize(by: 2)
check("resize doubles the pixel size", canvas.state.image.width == 800 && canvas.state.image.height == 400)
check("resize scales marks with the image", canvas.state.annotations[0].end == CGPoint(x: 180, y: 80))
check("resize updates the view frame", canvas.frame.size == CGSize(width: 400, height: 200))
canvas.undo()
check("undoing a resize restores size and marks", canvas.state.image.width == 400 && canvas.state.annotations[0].end == CGPoint(x: 90, y: 40))

canvas.crop(to: CGRect(x: 40, y: 10, width: 100, height: 50))  // points; 80,20 px origin at scale 2
check("crop shrinks the image to the selection", canvas.state.image.width == 200 && canvas.state.image.height == 100)
check("crop shifts marks into the new frame", canvas.state.annotations[0].start == CGPoint(x: 10, y: 10))
canvas.undo()
check("undoing a crop restores the original", canvas.state.image.width == 400 && canvas.state.annotations[0].start == CGPoint(x: 50, y: 20))

let before = canvas.state.annotations.count
canvas.addPixelation(pixelRects: [CGRect(x: 20, y: 20, width: 40, height: 20), CGRect(x: 100, y: 60, width: 60, height: 30)])
check("addPixelation adds one mark per region in point units",
      canvas.state.annotations.count == before + 2 && canvas.state.annotations[before].kind == .blur
      && canvas.state.annotations[before].rect == CGRect(x: 10, y: 10, width: 20, height: 10))
canvas.undo()
check("all auto-redactions undo together as one step", canvas.state.annotations.count == before)
check("export renders at native pixels", canvas.exportImage()?.width == 400)


// MARK: - Object styles (phase 2A)

// Rectangle fills
let solidBox = Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 110, y: 110), fill: .solid)
check("filled rectangle is hit anywhere inside", solidBox.hitTest(CGPoint(x: 60, y: 60)))
if let out = AnnotationRenderer.export(image: solidImage(width: 120, height: 120), pixelScale: 1,
                                       annotations: [Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 110, y: 110), color: .black, fill: .solid)]) {
    check("solid rectangle fills its interior", pixel(out, x: 60, y: 60).r < 20)
    check("solid rectangle leaves the outside alone", pixel(out, x: 3, y: 3) == (255, 255, 255))
} else { check("solid rectangle export", false) }
if let out = AnnotationRenderer.export(image: solidImage(width: 120, height: 120), pixelScale: 1,
                                       annotations: [Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 110, y: 110), color: .black, lineWidth: 2, fill: .hatch)]) {
    var dark = 0, light = 0
    for y in stride(from: 20, to: 100, by: 1) { for x in stride(from: 20, to: 100, by: 1) { pixel(out, x: x, y: y).r < 160 ? (dark += 1) : (light += 1) } }
    check("hatch fill draws stripes (some dark, most still light)", dark > 200 && light > dark)
} else { check("hatch export", false) }
if let out = AnnotationRenderer.export(image: solidImage(width: 120, height: 120), pixelScale: 1,
                                       annotations: [Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 110, y: 110), color: .black, lineWidth: 4, rounded: true)]) {
    check("rounded rectangle cuts its corner", pixel(out, x: 10, y: 10).r > 200 && pixel(out, x: 60, y: 10).r < 80)
} else { check("rounded export", false) }

// Arrow heads and curve
let straight = Annotation(kind: .arrow, start: CGPoint(x: 10, y: 50), end: CGPoint(x: 110, y: 50), color: .black, lineWidth: 4)
var curvy = straight; curvy.bend = 30
check("a bent arrow bulges to one side", curvy.curvePoints().allSatisfy { $0.y >= 50 } && curvy.curvePoints().contains { $0.y > 75 })
check("curve passes through the bend handle at its middle", abs(curvy.curvePoints()[12].y - curvy.bendHandle.y) < 0.01)
check("curved arrow hit test follows the curve", curvy.hitTest(curvy.bendHandle) && !curvy.hitTest(CGPoint(x: 60, y: 50)))
check("curved arrow bounds include the bulge", curvy.bounds.height > 25)
check("dragging the bend handle sets the bend, and near-zero snaps straight",
      abs(straight.moving(.bend, to: CGPoint(x: 60, y: 80)).bend - 30) < 0.01 && straight.moving(.bend, to: CGPoint(x: 60, y: 51)).bend == 0)
for head in ArrowHead.allCases {
    var a = straight; a.arrowHead = head
    if let out = AnnotationRenderer.export(image: solidImage(width: 130, height: 100), pixelScale: 1, annotations: [a]) {
        check("arrow head \(head) draws the shaft", pixel(out, x: 50, y: 50).r < 80)
        if head == .hollow { check("hollow head is empty inside", pixel(out, x: 100, y: 50).r > 150 || pixel(out, x: 98, y: 51).r > 150) }
        if head == .double { check("double head draws at the start too", pixel(out, x: 12, y: 50).r < 120) }
    } else { check("arrow \(head) export", false) }
}

// Blur modes
func textLine() -> CGImage {
    let w = 400, h = 100
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    c.setFillColor(CGColor(red: 0.95, green: 0.9, blue: 0.7, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    c.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1)); c.fill(CGRect(x: 300, y: 10, width: 80, height: 30))  // a non-text swatch, bottom right
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    NSString(string: "Secret 4821").draw(at: CGPoint(x: 20, y: 40), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 36), .foregroundColor: NSColor.black])
    NSGraphicsContext.restoreGraphicsState()
    return c.makeImage()!
}
let lineImage = textLine()
let region = CGRect(x: 0, y: 0, width: 400, height: 100)
func darkPixels(_ img: CGImage, in r: CGRect) -> Int {
    var n = 0
    for y in Int(r.minY)..<Int(r.maxY) { for x in Int(r.minX)..<Int(r.maxX) where pixel(img, x: x, y: y).r < 80 { n += 1 } }
    return n
}
check("test image really has dark text pixels", darkPixels(lineImage, in: CGRect(x: 20, y: 20, width: 260, height: 50)) > 100)
if let out = RegionEffects.erasedText(lineImage, pixelRect: region) {
    check("Erase Text removes the glyphs", darkPixels(out, in: CGRect(x: 20, y: 20, width: 260, height: 50)) < 5)
    let bg = pixel(out, x: 5, y: 5)
    check("Erase Text keeps the background colour", abs(bg.r - 242) < 6 && abs(bg.g - 230) < 6)
    let sw = pixel(out, x: 340, y: 75)
    check("Erase Text also treats a non-background swatch as foreground (erased)", abs(sw.r - 242) < 8)
} else { check("erased text", false) }
if let out = RegionEffects.erased(lineImage, pixelRect: CGRect(x: 10, y: 20, width: 280, height: 50)) {
    let c = pixel(out, x: 100, y: 40)
    check("Erase paints the region with the surrounding colour", abs(c.r - 242) < 8 && abs(c.g - 230) < 8)
} else { check("erase", false) }
if let out = RegionEffects.blurredText(lineImage, pixelRect: region, block: 12) {
    check("Blur Text leaves empty background cells untouched", pixel(out, x: 5, y: 95) == pixel(lineImage, x: 5, y: 95))
    // Every 12×12 cell that held text is one flat colour, so letter shapes cannot be read back.
    var flat = true
    for cy in stride(from: 24, to: 60, by: 12) { for cx in stride(from: 24, to: 240, by: 12) {
        for dy in 0..<10 { for dx in 0..<10 where pixel(out, x: cx + dx, y: cy + dy) != pixel(out, x: cx, y: cy) { flat = false } }
    } }
    check("Blur Text flattens cells containing text (no glyph silhouette)", flat)
} else { check("blur text", false) }
do {
    let blurMark = Annotation(kind: .blur, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 400, y: 100), blurMode: .erase)
    if let out = AnnotationRenderer.export(image: lineImage, pixelScale: 1, annotations: [blurMark]) {
        check("blur annotation honours Erase mode in export", darkPixels(out, in: region) < 5)
    }
    var weak = Annotation(kind: .blur, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 400, y: 100)); weak.level = 1
    var strong = weak; strong.level = 9
    if let a = AnnotationRenderer.export(image: lineImage, pixelScale: 1, annotations: [weak]),
       let b = AnnotationRenderer.export(image: lineImage, pixelScale: 1, annotations: [strong]) {
        check("blur strength changes the result", (0..<400).contains { pixel(a, x: $0, y: 30) != pixel(b, x: $0, y: 30) })
    }
}

// Counter, text label, spotlight, magnifier
let bigCounter = Annotation(kind: .counter, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 50, y: 50), fontSize: 36)
check("counter size follows its font size", bigCounter.bounds.width == Annotation.counterDiameter * 2)
if let out = AnnotationRenderer.export(image: solidImage(width: 100, height: 100), pixelScale: 1,
                                       annotations: [Annotation(kind: .counter, start: CGPoint(x: 50, y: 40), end: CGPoint(x: 50, y: 40), color: .black, number: 7)]) {
    check("counter bubble has a tail below-left of the circle", pixel(out, x: 39, y: 51).r < 120 && pixel(out, x: 70, y: 58).r > 200)
} else { check("counter export", false) }
let pillText = Annotation(kind: .text, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 10, y: 10), color: .black, text: "Hi", fontSize: 20, pill: true)
let plainText = Annotation(kind: .text, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 10, y: 10), color: .black, text: "Hi", fontSize: 20)
check("a text label is bigger than plain text by its padding",
      abs(pillText.bounds.width - plainText.bounds.width - 16) < 0.01 && abs(pillText.bounds.height - plainText.bounds.height - 8) < 0.01)
if let out = AnnotationRenderer.export(image: solidImage(width: 100, height: 60), pixelScale: 1, annotations: [pillText]) {
    check("label draws a filled pill behind the text", pixel(out, x: 12, y: 26).r < 60)
} else { check("pill export", false) }
check("light label colours get dark text, dark ones get white text",
      ColorMath.readableText(on: .yellow) == .black && ColorMath.readableText(on: .systemBlue.blended(withFraction: 0.5, of: .black)!) == .white)
for (level, expectBelow) in [(1, 255), (9, 60)] {
    var s = Annotation(kind: .spotlight, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 60, y: 60)); s.level = level
    if let out = AnnotationRenderer.export(image: solidImage(width: 100, height: 100), pixelScale: 1, annotations: [s]) {
        let v = pixel(out, x: 5, y: 5).r
        check("spotlight level \(level) darkens the outside \(level == 1 ? "a little" : "a lot")", level == 1 ? v > 200 && v < 250 : v < expectBelow)
    }
}
do {
    var s = Annotation(kind: .spotlight, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 80)); s.oval = true; s.level = 9
    if let out = AnnotationRenderer.export(image: solidImage(width: 100, height: 100), pixelScale: 1, annotations: [s]) {
        check("oval spotlight keeps the middle bright and dims its corners", pixel(out, x: 50, y: 50).r > 240 && pixel(out, x: 24, y: 24).r < 100)
    }
}
do {
    let mag = Annotation(kind: .magnifier, start: CGPoint(x: 30, y: 50), end: CGPoint(x: 40, y: 50))
    check("magnifier bubble is 2× the source and sits to its right", mag.bubbleRadius == 20 && mag.bubbleCenter.x == 30 + 10 + 20 + 10)
    check("magnifier bounds cover both circles", mag.bounds.minX == 20 && mag.bounds.maxX == 90)
    check("a magnifier is hit on its bubble too", mag.hitTest(CGPoint(x: 70, y: 50)) && !mag.hitTest(CGPoint(x: 70, y: 95)))
    var m4 = mag; m4.level = 4
    check("magnifier zoom 4 makes a 4× bubble", m4.bubbleRadius == 40)
    check("dragging the bubble handle moves only the bubble", mag.moving(.bubble, to: CGPoint(x: 5, y: 5)).start == mag.start && mag.moving(.bubble, to: CGPoint(x: 5, y: 5)).bubbleCenter == CGPoint(x: 5, y: 5))
    // The bubble shows the source magnified: a dot at the source centre appears larger in the bubble.
    let base = solidImage(width: 200, height: 100)
    let ctxDot = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctxDot.draw(base, in: CGRect(x: 0, y: 0, width: 200, height: 100))
    ctxDot.setFillColor(CGColor(gray: 0, alpha: 1)); ctxDot.fill(CGRect(x: 28, y: 48, width: 4, height: 4))
    if let dotted = ctxDot.makeImage(), let out = AnnotationRenderer.export(image: dotted, pixelScale: 1, annotations: [Annotation(kind: .magnifier, start: CGPoint(x: 30, y: 50), end: CGPoint(x: 50, y: 50), color: .systemRed)]) {
        // Bubble centre x = 30 + 20 + 40 + 10 = 100. The 4 px dot becomes 8 px wide there.
        check("magnifier bubble shows the source at 2×", pixel(out, x: 100, y: 50).r < 60 && pixel(out, x: 103, y: 50).r < 60 && pixel(out, x: 110, y: 50).r > 200)
    } else { check("magnifier export", false) }
}

// Handles
do {
    let r = Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 30))
    check("rectangles have 8 grab points", r.handles().count == 8)
    let grown = r.moving(.bottomRight, to: CGPoint(x: 90, y: 70))
    check("dragging a corner resizes from the opposite corner", grown.rect == CGRect(x: 10, y: 10, width: 80, height: 60))
    check("dragging an edge changes one dimension only", r.moving(.right, to: CGPoint(x: 70, y: 99)).rect == CGRect(x: 10, y: 10, width: 60, height: 20))
    check("dragging past the opposite edge flips instead of going negative", r.moving(.left, to: CGPoint(x: 80, y: 0)).rect == CGRect(x: 50, y: 10, width: 30, height: 20))
    check("lines have two end handles, arrows three", Annotation(kind: .line, start: .zero, end: CGPoint(x: 9, y: 9)).handles().count == 2 && straight.handles().count == 3)
    check("text and freehand have no resize handles", plainText.handles().isEmpty && pen.handles().isEmpty)
}

// Canvas: style editing and selection
do {
    let c = CanvasView(image: solidImage(width: 200, height: 100), pixelScale: 1)
    c.append(Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 60, y: 40)))
    c.select(0)
    check("selecting a mark makes it the style target", c.styleTarget?.kind == .rectangle)
    let undoBefore = c.canUndo
    c.updateStyle { $0.fill = .solid }
    c.updateStyle { $0.lineWidth = 9 }
    c.updateStyle { $0.lineWidth = 10 }
    check("style changes apply to the selected mark", c.state.annotations[0].fill == .solid && c.state.annotations[0].lineWidth == 10)
    check("style changes also become the default for new rectangles", c.templates[.rectangle]?.fill == .solid && c.templates[.rectangle]?.lineWidth == 10)
    c.undo()
    check("a burst of style changes is a single undo step", c.state.annotations[0].fill == .outline && c.state.annotations.count == 1 && undoBefore == c.canUndo || c.state.annotations.count == 1 && c.state.annotations[0].fill == .outline)
    c.select(nil); c.tool = .counter
    check("with a drawing tool and no selection, the panel edits that tool's defaults", c.styleTarget?.kind == .counter && c.styleTarget?.number == 1)
    c.updateStyle { $0.number = 5 }
    check("the next counter value can be dialled before placing", c.nextCounterNumber == 5)
    c.tool = .select
    check("no style panel for the select tool", c.styleTarget == nil)
}


// MARK: - Selection, colour readout, edge ruler (phase 2B)

/// Left half white, right half black, a red 10×10 square at (10,10).
func halves(width: Int = 100, height: Int = 50) -> CGImage {
    let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    c.setFillColor(CGColor(gray: 0, alpha: 1)); c.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
    c.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)); c.fill(CGRect(x: 10, y: height - 20, width: 10, height: 10))
    return c.makeImage()!
}
if let probe = PixelProbe(image: halves()) {
    check("probe reads colours with a top-left origin", probe.color(x: 12, y: 12)?.r == 255 && probe.color(x: 12, y: 12)?.g == 0 && probe.color(x: 70, y: 5)?.r == 0)
    check("probe returns nil outside the image", probe.color(x: -1, y: 0) == nil && probe.color(x: 100, y: 0) == nil)
    check("a run stops at the colour edge (white half is 50 px wide)", probe.run(x: 30, y: 40, horizontal: true) == 0...49)
    check("a run in the black half", probe.run(x: 80, y: 5, horizontal: true) == 50...99)
    check("vertical run is limited by the red square", probe.run(x: 15, y: 15, horizontal: false) == 10...19)
    check("darkest nearby pixel finds the black next to a white point", probe.darkest(x: 45, y: 25, radius: 10)?.r == 0)
    let avg = probe.average(x0: 40, y0: 30, x1: 59, y1: 39)
    check("average of a half-white half-black area is mid-grey", avg.map { abs($0.r - 127) <= 1 } ?? false)
} else { check("probe", false) }

do {
    let c = CanvasView(image: halves(), pixelScale: 1)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 50), styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = c
    func mouse(_ type: NSEvent.EventType, _ p: CGPoint, clicks: Int = 1, mods: NSEvent.ModifierFlags = []) {
        let loc = c.convert(p, to: nil)
        let e = NSEvent.mouseEvent(with: type, location: loc, modifierFlags: mods, timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        switch type {
        case .leftMouseDown: c.mouseDown(with: e)
        case .leftMouseDragged: c.mouseDragged(with: e)
        case .leftMouseUp: c.mouseUp(with: e)
        default: c.mouseMoved(with: e)
        }
    }
    func key(_ code: UInt16, _ chars: String = "", _ mods: NSEvent.ModifierFlags = [], up: Bool = false) {
        let e = NSEvent.keyEvent(with: up ? .keyUp : .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: window.windowNumber,
                                 context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        up ? c.keyUp(with: e) : c.keyDown(with: e)
    }
    func drag(_ a: CGPoint, _ b: CGPoint) { mouse(.leftMouseDown, a); mouse(.leftMouseDragged, b); mouse(.leftMouseUp, b) }

    c.tool = .select
    drag(CGPoint(x: 10, y: 5), CGPoint(x: 40, y: 25))
    check("dragging in empty space makes a selection", c.selectionRect == CGRect(x: 10, y: 5, width: 30, height: 20))
    check("selection maps to whole image pixels", c.selectionPixelRect == CGRect(x: 10, y: 5, width: 30, height: 20))
    check("selectionImage is the selected part", c.selectionImage()?.width == 30 && c.selectionImage()?.height == 20)
    key(124, "", []); key(125, "", [])
    check("arrow keys nudge the selection by 1 px", c.selectionRect == CGRect(x: 11, y: 6, width: 30, height: 20))
    key(124, "", [.shift])
    check("Shift+arrow nudges by 10 px", c.selectionRect?.minX == 21)
    key(123, "", [.shift]); key(126, "", [])
    check("⌘+arrows resize instead of moving", { key(124, "", [.command]); key(125, "", [.command]); return c.selectionRect?.width == 31 && c.selectionRect?.height == 21 && c.selectionRect?.minX == 11 }())
    key(30, "]")
    check("] grows the selection by 1 px per side", c.selectionRect == CGRect(x: 10, y: 4, width: 33, height: 23))
    key(33, "[")
    check("[ shrinks it again", c.selectionRect == CGRect(x: 11, y: 5, width: 31, height: 21))
    key(124, "", [.shift]); key(124, "", [.shift]); key(124, "", [.shift]); key(124, "", [.shift]); key(124, "", [.shift])
    check("the selection cannot be pushed out of the image", (c.selectionRect?.maxX ?? 999) <= 100)
    key(53)
    check("Esc clears the selection first", c.selectionRect == nil && c.state.image.width == 100)
    drag(CGPoint(x: 10, y: 5), CGPoint(x: 40, y: 25))
    key(36)
    check("Enter crops to the selection", c.state.image.width == 30 && c.state.image.height == 20 && c.selectionRect == nil)
    c.undo()
    check("a crop by selection is one undo step", c.state.image.width == 100)
    drag(CGPoint(x: 30, y: 10), CGPoint(x: 32, y: 11))
    check("a tiny drag is not a selection", c.selectionRect == nil)

    // Colour readout
    var hovered: NSColor?
    c.onHoverColor = { color, _ in hovered = color }
    mouse(.mouseMoved, CGPoint(x: 70, y: 5))
    check("hover reports the colour under the pointer", hovered?.usingColorSpace(.sRGB)?.redComponent == 0)
    mouse(.mouseMoved, CGPoint(x: 12, y: 12))
    check("…and it follows the pointer", hovered?.usingColorSpace(.sRGB)?.redComponent == 1 && hovered?.usingColorSpace(.sRGB)?.greenComponent == 0)
    NSPasteboard.general.clearContents()
    key(48)
    check("Tab copies the colour under the pointer as text", NSPasteboard.general.string(forType: .string) == "#FF0000")
    mouse(.mouseMoved, CGPoint(x: 47, y: 25))
    key(48, "", [.shift])
    check("Shift+Tab copies the darkest pixel nearby (black)", NSPasteboard.general.string(forType: .string) == "#000000")
    c.setSelection(CGRect(x: 40, y: 30, width: 20, height: 10))
    key(8, "c")
    check("C copies the selection's average colour", NSPasteboard.general.string(forType: .string) == "#7F7F7F" || NSPasteboard.general.string(forType: .string) == "#808080")
    c.setSelection(nil)

    // Edge-measuring ruler
    _ = c.resignFirstResponder()  // forget the keys the test "pressed" above
    c.tool = .ruler
    mouse(.mouseMoved, CGPoint(x: 30, y: 40))
    let spans = c.measureMarks(at: CGPoint(x: 30, y: 40), horizontal: true, vertical: true)
    check("ruler finds the width and height of the flat area under the pointer",
          spans.count == 2 && spans[0].start.x == 0 && spans[0].end.x == 50 && spans[1].start.y == 0 && spans[1].end.y == 50)
    let before = c.state.annotations.count
    mouse(.leftMouseDown, CGPoint(x: 30, y: 40)); mouse(.leftMouseUp, CGPoint(x: 30, y: 40))
    check("the ruler measures by itself: a plain click keeps both width and height", c.state.annotations.count == before + 2
          && c.state.annotations[before].end.x == 50 && c.state.annotations[before + 1].end.y == 50)
    c.undo()
    check("a measurement is one undo step", c.state.annotations.count == before)
    key(18)   // hold 1: height only
    mouse(.mouseMoved, CGPoint(x: 30, y: 40))
    mouse(.leftMouseDown, CGPoint(x: 30, y: 40)); mouse(.leftMouseUp, CGPoint(x: 30, y: 40))
    key(18, up: true)
    check("holding 1 measures the height only", c.state.annotations.count == before + 1 && c.state.annotations.last?.start.x == c.state.annotations.last?.end.x && c.state.annotations.last?.end.y == 50)
    c.undo()
    key(19)   // hold 2: width only
    mouse(.mouseMoved, CGPoint(x: 30, y: 40))
    mouse(.leftMouseDown, CGPoint(x: 30, y: 40)); mouse(.leftMouseUp, CGPoint(x: 30, y: 40))
    key(19, up: true)
    check("holding 2 measures the width only", c.state.annotations.count == before + 1 && c.state.annotations.last?.start.y == c.state.annotations.last?.end.y && c.state.annotations.last?.end.x == 50)
    c.undo()
    mouse(.mouseMoved, CGPoint(x: 70, y: 20))
    mouse(.leftMouseDown, CGPoint(x: 70, y: 20)); mouse(.leftMouseDragged, CGPoint(x: 90, y: 20)); mouse(.leftMouseUp, CGPoint(x: 90, y: 20))
    check("dragging draws a manual measuring line instead", c.state.annotations.count == before + 1 && c.state.annotations.last?.start == CGPoint(x: 70, y: 20) && c.state.annotations.last?.end == CGPoint(x: 90, y: 20))
    c.undo()
    // Guides
    mouse(.mouseMoved, CGPoint(x: 33, y: 22))
    key(1, "s", [.option])
    mouse(.leftMouseDown, CGPoint(x: 33, y: 22)); mouse(.leftMouseUp, CGPoint(x: 33, y: 22))
    key(1, "s", [.option], up: true)
    check("Option+S keeps a full-height vertical guide at the pointer", c.state.annotations.count == before + 1 && c.state.annotations.last?.kind == .line
          && c.state.annotations.last?.start == CGPoint(x: 33, y: 0) && c.state.annotations.last?.end == CGPoint(x: 33, y: 50))
    c.undo()
    key(2, "d", [.option])
    mouse(.leftMouseDown, CGPoint(x: 33, y: 22)); mouse(.leftMouseUp, CGPoint(x: 33, y: 22))
    key(2, "d", [.option], up: true)
    check("Option+D keeps a full-width horizontal guide", c.state.annotations.last?.start == CGPoint(x: 0, y: 22) && c.state.annotations.last?.end == CGPoint(x: 100, y: 22))
    c.undo()
    c.tool = .select
    check("ruler label units default to points, switchable to pixels", Annotation(kind: .ruler, start: .zero, end: .zero).level == 1)

    // Counter pointer rotation
    var count = Annotation(kind: .counter, start: CGPoint(x: 50, y: 25), end: CGPoint(x: 50, y: 25), number: 3)
    check("a counter has a rotation handle beside its pointer", count.handles().first?.handle == .tail)
    count = count.moving(.tail, to: CGPoint(x: 80, y: 25))
    check("dragging the handle points the tail that way (right)", abs(count.angle) < 0.01 && count.counterTail.x > 64)
    count = count.moving(.tail, to: CGPoint(x: 50, y: 0))
    check("…and up", abs(count.angle + .pi / 2) < 0.01 && count.counterTail.y < 25)
    if let out = AnnotationRenderer.export(image: solidImage(width: 100, height: 60), pixelScale: 1,
                                           annotations: [Annotation(kind: .counter, start: CGPoint(x: 50, y: 30), end: CGPoint(x: 50, y: 30), color: .black, number: 1, angle: 0)]) {
        check("a rotated pointer is drawn on that side", pixel(out, x: 66, y: 30).r < 120 && pixel(out, x: 34, y: 45).r > 200)
    }

    // Marks: duplicate, copy/paste, front, opacity, zoom keys
    c.append(Annotation(kind: .rectangle, start: CGPoint(x: 5, y: 5), end: CGPoint(x: 30, y: 30)))
    c.append(Annotation(kind: .ellipse, start: CGPoint(x: 60, y: 5), end: CGPoint(x: 90, y: 30)))
    let n0 = c.state.annotations.count
    mouse(.leftMouseDown, CGPoint(x: 5, y: 15))   // the rectangle's left edge
    mouse(.leftMouseUp, CGPoint(x: 5, y: 15))
    check("clicking a mark brings it to the front", c.state.annotations.last?.kind == .rectangle && c.selectedIndex == n0 - 1)
    c.select(nil)  // (a selected mark's own handles would take the click)
    mouse(.leftMouseDown, CGPoint(x: 5, y: 15), mods: [.option]); mouse(.leftMouseDragged, CGPoint(x: 25, y: 15), mods: [.option]); mouse(.leftMouseUp, CGPoint(x: 25, y: 15), mods: [.option])
    check("Option-drag duplicates the mark and moves the copy", c.state.annotations.count == n0 + 1 && c.state.annotations[n0 - 1].start == CGPoint(x: 5, y: 5) && c.state.annotations[n0].start.x > 5)
    check("copying a selected mark works", c.copySelectedMark())
    let n1 = c.state.annotations.count
    check("pasting adds an offset copy and selects it", c.pasteMark() && c.state.annotations.count == n1 + 1 && c.state.annotations.last?.start.x == c.state.annotations[n1 - 1].start.x + 12)
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString("something else", forType: .string)
    check("after copying anything else, ⌘V is not a mark paste", !c.pasteMark())
    c.addImageOverlay(solidImage(width: 20, height: 10, gray: 0), imageScale: 1, at: CGPoint(x: 50, y: 25))
    key(23, "5")
    check("key 5 makes a pasted picture 50% opaque", c.selectedAnnotation?.kind == .image && c.selectedAnnotation?.level == 5)
    if let out = c.exportImage() {
        let v = pixel(out, x: 50, y: 25).r
        check("…and it is blended with what is underneath", v > 100 && v < 160 || v < 100)
    }
    var zooms: [CanvasView.ZoomCommand] = []
    c.onZoomCommand = { zooms.append($0) }
    c.select(nil)
    c.setSelection(CGRect(x: 10, y: 10, width: 30, height: 20))
    key(12, "q"); key(13, "w")
    check("Q and W request zooms to the selection's corners", zooms.count == 2)
    c.tool = .select
}


// MARK: - Image operations (phase 2C)

do {
    let base = halves()  // 100×50: white left, black right, red square
    let tall = solidImage(width: 100, height: 40, gray: 0.5)
    let wide = solidImage(width: 60, height: 30, gray: 0.5)
    check("a capture as wide as the base goes below it", ImageOps.preferredEdge(base: base, new: tall) == .bottom)
    check("a narrower capture goes beside it", ImageOps.preferredEdge(base: base, new: wide) == .right)
    if let below = ImageOps.appended(tall, to: base, edge: .bottom) {
        check("appending below stacks the heights", below.width == 100 && below.height == 90)
        check("the base stays at the top", pixel(below, x: 12, y: 12).g < 60 && pixel(below, x: 70, y: 5).r == 0)
        check("the new capture sits underneath", abs(pixel(below, x: 50, y: 70).r - pixel(tall, x: 5, y: 5).r) <= 2 && abs(pixel(below, x: 5, y: 89).r - pixel(tall, x: 5, y: 5).r) <= 2)
    } else { check("append below", false) }
    if let beside = ImageOps.appended(wide, to: base, edge: .right) {
        check("appending to the right adds the width and keeps the taller height", beside.width == 160 && beside.height == 50)
        check("the new capture is top-aligned beside the base", abs(pixel(beside, x: 130, y: 5).r - pixel(wide, x: 5, y: 5).r) <= 2)
        let fill = pixel(beside, x: 130, y: 45)  // below the shorter capture: filled with the base's edge colour
        check("leftover area is filled, not transparent or black garbage", fill.r == fill.g && fill.g == fill.b)
    } else { check("append right", false) }
    let pad = ImageOps.padded(base, left: 10, top: 0, right: 0, bottom: 20, fill: (200, 100, 50))
    check("padding grows the image on the requested sides", pad?.width == 110 && pad?.height == 70)
    if let pad {
        check("padding fills with the colour on the correct sides", pixel(pad, x: 3, y: 10).r == 200 && pixel(pad, x: 50, y: 65).g == 100)
        check("the original sits where it was (shifted right, still at the top)", pixel(pad, x: 22, y: 12).g < 60)
    }
    let edge = ImageOps.edgeColor(of: solidImage(width: 20, height: 20, gray: 0.5))
    check("edge colour of a flat image is that colour", abs(Int(edge.r) - pixel(solidImage(width: 20, height: 20, gray: 0.5), x: 3, y: 3).r) <= 2)
}

do {
    let c = CanvasView(image: halves(), pixelScale: 1)
    // Rasterize
    c.append(Annotation(kind: .rectangle, start: CGPoint(x: 5, y: 30), end: CGPoint(x: 40, y: 45), color: .black, fill: .solid))
    check("rasterize with a mark changes the pixels and clears the marks", c.rasterize() && c.state.annotations.isEmpty)
    check("the merged pixels contain the mark", pixel(c.state.image, x: 20, y: 38).r < 20)
    c.undo()
    check("rasterize is one undo step that brings the mark back", c.state.annotations.count == 1 && pixel(c.state.image, x: 20, y: 38).r > 200)
    c.undo()
    check("rasterizing nothing does nothing", !c.rasterize())

    // Paste overlay
    let sticker = solidImage(width: 20, height: 10, gray: 0.5)
    c.addImageOverlay(sticker, imageScale: 1, at: CGPoint(x: 80, y: 25))
    let overlay = c.state.annotations.last
    check("a pasted picture becomes a selected overlay at its natural size", overlay?.kind == .image && overlay?.rect.size == CGSize(width: 20, height: 10) && c.selectedIndex == c.state.annotations.count - 1)
    check("overlays have resize handles and can be hit", overlay?.handles().count == 8 && overlay?.hitTest(CGPoint(x: 80, y: 25)) == true)
    if let out = c.exportImage() { check("the overlay is drawn on export (grey over the black half)", abs(pixel(out, x: 80, y: 25).r - pixel(sticker, x: 1, y: 1).r) <= 2 && pixel(out, x: 80, y: 40).r == 0) }
    let huge = solidImage(width: 400, height: 400, gray: 0)
    c.addImageOverlay(huge, imageScale: 1)
    check("a picture bigger than the canvas is shrunk to fit", (c.state.annotations.last?.rect.width ?? 999) <= 80.01 && (c.state.annotations.last?.rect.height ?? 999) <= 40.01)
    let beforeAppend = c.state.image.width
    c.appendImage(solidImage(width: 30, height: 20, gray: 0.5), edge: .right)
    check("Add Capture extends the canvas and keeps the marks", c.state.image.width == beforeAppend + 30 && c.state.annotations.count >= 2 && c.frame.width == CGFloat(beforeAppend + 30))
    c.undo()
    check("Add Capture is undoable", c.state.image.width == beforeAppend)
}

do {
    // Auto-expanding canvas: a magnifier whose bubble does not fit makes the canvas grow instead of being cut off.
    let c = CanvasView(image: solidImage(width: 100, height: 60), pixelScale: 1)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 60), styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = c
    c.tool = .magnifier
    func mouse(_ type: NSEvent.EventType, _ p: CGPoint) {
        let e = NSEvent.mouseEvent(with: type, location: c.convert(p, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        switch type { case .leftMouseDown: c.mouseDown(with: e); case .leftMouseDragged: c.mouseDragged(with: e); default: c.mouseUp(with: e) }
    }
    mouse(.leftMouseDown, CGPoint(x: 30, y: 30)); mouse(.leftMouseDragged, CGPoint(x: 45, y: 30)); mouse(.leftMouseUp, CGPoint(x: 45, y: 30))
    let mark = c.state.annotations.last
    check("a magnifier was created", mark?.kind == .magnifier)
    if let mark {
        let size = c.pointSize
        check("the canvas grew to hold the whole bubble", CGRect(origin: .zero, size: size).contains(mark.bounds))
        check("growing the canvas is part of the same undo step", { c.undo(); return c.state.image.width == 100 && c.state.annotations.isEmpty }())
    }
    // A magnifier with room keeps the image size.
    let roomy = CanvasView(image: solidImage(width: 400, height: 300), pixelScale: 1)
    let w2 = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
    w2.contentView = roomy
    roomy.tool = .magnifier
    func mouse2(_ type: NSEvent.EventType, _ p: CGPoint) {
        let e = NSEvent.mouseEvent(with: type, location: roomy.convert(p, to: nil), modifierFlags: [], timestamp: 0, windowNumber: w2.windowNumber,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        switch type { case .leftMouseDown: roomy.mouseDown(with: e); case .leftMouseDragged: roomy.mouseDragged(with: e); default: roomy.mouseUp(with: e) }
    }
    mouse2(.leftMouseDown, CGPoint(x: 80, y: 150)); mouse2(.leftMouseDragged, CGPoint(x: 100, y: 150)); mouse2(.leftMouseUp, CGPoint(x: 100, y: 150))
    check("with room for the bubble the canvas size is unchanged", roomy.state.image.width == 400 && roomy.state.image.height == 300)
    // Dragging the bubble out of the image grows the canvas on release.
    if let m = roomy.state.annotations.last {
        roomy.select(roomy.state.annotations.count - 1)
        let handle = m.bubbleCenter
        mouse2(.leftMouseDown, handle); mouse2(.leftMouseDragged, CGPoint(x: 500, y: 150)); mouse2(.leftMouseUp, CGPoint(x: 500, y: 150))
        check("dragging the bubble past the edge grows the canvas", roomy.state.image.width > 400)
    }
}


// MARK: - Settings, URL scheme, output (phase 2D)

do {
    func parse(_ s: String) -> URLCommand? { URLCommand.parse(URL(string: s)!) }
    check("grab/area parses", parse("chaediew://grab/area") == .grab(.area, delay: 0, then: []))
    check("then= actions parse in order", parse("chaediew://grab/fullscreen?then=copy,save,pin") == .grab(.fullscreen, delay: 0, then: [.copy, .save, .pin]))
    check("unknown then= actions are ignored", parse("chaediew://grab/window?then=copy,explode") == .grab(.window, delay: 0, then: [.copy]))
    check("delayed=N sets the delay", parse("chaediew://grab/delayed=3?then=edit") == .grab(.area, delay: 3, then: [.edit]))
    check("delayed without a value defaults to 5 s and is capped at 60", parse("chaediew://grab/delayed") == .grab(.area, delay: 5, then: []) && parse("chaediew://grab/delayed=999") == .grab(.area, delay: 60, then: []))
    check("scrolling, repeat, ocr, qr, clipboard, show, settings parse",
          parse("chaediew://grab/scrolling") == .grab(.scrolling, delay: 0, then: []) && parse("chaediew://grab/repeat") == .grab(.repeatLast, delay: 0, then: [])
          && parse("chaediew://ocr") == .ocr && parse("chaediew://qr") == .qr && parse("chaediew://load/clipboard") == .loadClipboard
          && parse("chaediew://show") == .showLibrary && parse("chaediew://settings") == .settings && parse("chaediew://grab/append") == .addCapture)
    check("load/file needs an absolute path", parse("chaediew://load/file?path=/tmp/a.png") == .loadFile(URL(fileURLWithPath: "/tmp/a.png")) && parse("chaediew://load/file?path=a.png") == nil)
    check("commands are case-insensitive", parse("CHAEDIEW://Grab/Area") == .grab(.area, delay: 0, then: []))
    check("other schemes and nonsense are rejected", parse("shottr://grab/area") == nil && parse("chaediew://grab/teleport") == nil && parse("chaediew://") == nil)

    let suite = UserDefaults(suiteName: "chaediew.2d")!
    suite.removePersistentDomain(forName: "chaediew.2d")
    let st = Settings(defaults: suite)
    check("new settings have safe defaults", !st.urlSchemeEnabled && !st.autoFormat && !st.downscaleRetina && st.windowBackground == .transparent && st.scrollMaxHeight == 20_000 && st.scrollSpeed == 1)
    suite.set(5_000_000, forKey: Settings.Key.scrollMaxHeight); suite.set(9.0, forKey: Settings.Key.scrollSpeed)
    check("scroll limits are clamped", st.scrollMaxHeight == 200_000 && st.scrollSpeed == 2)
    suite.set("darkGray", forKey: Settings.Key.windowBackground)
    check("window background reads back", st.windowBackground == .darkGray && st.windowBackground.rgb?.r == 52)
    suite.set("nonsense", forKey: Settings.Key.windowBackground)
    check("a bad window background falls back to transparent", st.windowBackground == .transparent)

    // Output: Retina downscale and automatic format
    let retina = solidImage(width: 200, height: 100)
    suite.set(true, forKey: Settings.Key.downscaleRetina)
    let half = Storage.outputImage(retina, pixelScale: 2, settings: st)
    check("Retina downscale halves a 2× image", half.width == 100 && half.height == 50)
    check("…but leaves 1× images alone", Storage.outputImage(retina, pixelScale: 1, settings: st).width == 200)
    suite.set(false, forKey: Settings.Key.downscaleRetina)
    check("…and does nothing when the setting is off", Storage.outputImage(retina, pixelScale: 2, settings: st).width == 200)

    check("a flat interface screenshot is saved as PNG", Storage.autoFormat(for: textImage("Hello")) == .png)
    var photoBytes = [UInt8](repeating: 255, count: 300 * 200 * 4)
    var rng: UInt64 = 12345
    for i in 0..<(300 * 200) { for c in 0..<3 { rng = rng &* 6364136223846793005 &+ 1442695040888963407; photoBytes[i * 4 + c] = UInt8(truncatingIfNeeded: rng >> 33) } }
    let photo = CGImage(width: 300, height: 200, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 1200, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: CGDataProvider(data: Data(photoBytes) as CFData)!,
                        decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    check("a photographic image (many distinct colours) is saved as JPEG", Storage.autoFormat(for: photo) == .jpeg)
    let clear = CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    clear.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)); clear.fill(CGRect(x: 10, y: 10, width: 20, height: 20))
    let transparent = clear.makeImage()!
    check("an image with transparency is always PNG", Storage.autoFormat(for: transparent) == .png)
    suite.set(true, forKey: Settings.Key.autoFormat); suite.set("jpeg", forKey: Settings.Key.imageFormat)
    check("auto format overrides the fixed format", Storage.resolveFormat(for: textImage("Hello"), settings: st) == .png)
    suite.set(false, forKey: Settings.Key.autoFormat)
    check("without auto, the chosen format wins", Storage.resolveFormat(for: textImage("Hello"), settings: st) == .jpeg)

    if let flat = ImageOps.flattened(transparent, onto: (0, 255, 0)) {
        check("window background fills transparent corners", pixel(flat, x: 2, y: 2) == (0, 255, 0))
        check("…and keeps the opaque content", pixel(flat, x: 20, y: 20).r > 240 && pixel(flat, x: 20, y: 20).g < 20)
    } else { check("flatten", false) }
    suite.removePersistentDomain(forName: "chaediew.2d")

    // Scrolling max height is honoured by the stitcher
    let limited = ScrollStitcher(maxHeight: 500)
    let pageShot = makePage(width: 100, height: 400)
    _ = limited.add(frame(of: pageShot, offset: 0, height: 300))
    let second = limited.add(frame(of: pageShot, offset: 150, height: 250))
    var reachedLimit = false
    if case .limitReached = second { reachedLimit = true }
    check("scroll stitching stops at the configured maximum height", reachedLimit || limited.totalHeight <= 500)
}


// MARK: - Round 1 refinements: smart selection, taper, marker, smoothing, snapping, contrast

do {
    let probe = PixelProbe(image: halves())!
    let flood = probe.floodBounds(x: 30, y: 40)
    check("flood fill finds the white half as one object", flood.map { $0.x0 == 0 && $0.x1 == 49 && $0.y0 == 0 && $0.y1 == 49 } ?? false)
    let red = probe.floodBounds(x: 15, y: 15)
    check("…and the red square inside it", red.map { $0.x0 == 10 && $0.x1 == 19 && $0.y0 == 10 && $0.y1 == 19 } ?? false)
    let tight = probe.contentBounds(x0: 5, y0: 5, x1: 30, y1: 30)
    check("content bounds hug what differs from the frame", tight.map { $0.x0 == 10 && $0.x1 == 19 && $0.y0 == 10 && $0.y1 == 19 } ?? false)
    check("a flat selection has no content bounds", probe.contentBounds(x0: 22, y0: 22, x1: 40, y1: 40) == nil)

    let s1 = Snap.adjust(moving: CGRect(x: 52, y: 10, width: 20, height: 10), targets: [CGRect(x: 0, y: 40, width: 50, height: 10)], threshold: 6)
    check("snap pulls a near edge onto the target's edge", s1.dx == -2 && s1.guideXs == [50])
    let s2 = Snap.adjust(moving: CGRect(x: 100, y: 10, width: 20, height: 10), targets: [CGRect(x: 0, y: 40, width: 50, height: 10)], threshold: 6)
    check("snap does nothing when nothing is close", s2.dx == 0 && s2.dy == 0 && s2.guideXs.isEmpty)
    let s3 = Snap.adjust(moving: CGRect(x: 10, y: 10, width: 20, height: 10), targets: [CGRect(x: 100, y: 0, width: 40, height: 60)], threshold: 6)
    check("centres snap too (vertical centre 15 → 30 is out of reach, so none)", s3.dy == 0)
    let s4 = Snap.adjust(moving: CGRect(x: 10, y: 27, width: 20, height: 10), targets: [CGRect(x: 100, y: 0, width: 40, height: 60)], threshold: 6)
    check("centre-to-centre snapping works", s4.dy == -2 && s4.guideYs == [30])

    let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 0)]
    let sm = Geometry.smoothed(pts, iterations: 2)
    check("smoothing keeps the end points and adds points", sm.first == pts.first && sm.last == pts.last && sm.count > pts.count)
    check("smoothing 0 leaves the stroke alone", Geometry.smoothed(pts, iterations: 0) == pts)
    check("a pen mark smooths by 2 by default", Annotation(kind: .freehand, start: .zero, end: .zero).level == 2)

    check("APCA: black on white is about 106", abs(ColorMath.apca(text: (0, 0, 0), background: (255, 255, 255)) - 106) < 2)
    check("APCA: white on black is negative about -107", abs(ColorMath.apca(text: (255, 255, 255), background: (0, 0, 0)) + 107) < 2)
    check("APCA: identical colours give 0", ColorMath.apca(text: (120, 120, 120), background: (120, 120, 120)) == 0)
    check("WCAG: black on white is 21:1", abs(ColorMath.wcagRatio((0, 0, 0), (255, 255, 255)) - 21) < 0.01)
    check("WCAG: #767676 on white just passes AA (4.5)", ColorMath.wcagRatio((0x76, 0x76, 0x76), (255, 255, 255)) >= 4.5)

    // Tapered arrow: thin at the tail, heavy near the head
    func darkColumn(_ img: CGImage, x: Int) -> Int { (0..<img.height).filter { pixel(img, x: x, y: $0).r < 128 }.count }
    var tap = Annotation(kind: .arrow, start: CGPoint(x: 10, y: 50), end: CGPoint(x: 190, y: 50), color: .black, lineWidth: 8, tapered: true)
    tap.arrowHead = .normal
    if let out = AnnotationRenderer.export(image: solidImage(width: 200, height: 100), pixelScale: 1, annotations: [tap]) {
        check("a tapered arrow is thinner at the tail than near the head", darkColumn(out, x: 20) < darkColumn(out, x: 120) && darkColumn(out, x: 20) >= 1)
    } else { check("taper export", false) }
    var uni = tap; uni.tapered = false
    if let out = AnnotationRenderer.export(image: solidImage(width: 200, height: 100), pixelScale: 1, annotations: [uni]) {
        check("a uniform arrow keeps one thickness", abs(darkColumn(out, x: 20) - darkColumn(out, x: 120)) <= 1)
    }

    // Marker highlighter
    let marker = Annotation(kind: .highlight, start: CGPoint(x: 10, y: 50), end: CGPoint(x: 90, y: 50), color: .yellow, lineWidth: 4, marker: true)
    check("a marker is as thick as 4× its line width and hit along its stroke", marker.markerWidth == 16 && marker.hitTest(CGPoint(x: 50, y: 56)) && !marker.hitTest(CGPoint(x: 50, y: 80)))
    check("a marker has two end handles", marker.handles().count == 2 && marker.bounds.height >= 16)
    if let out = AnnotationRenderer.export(image: solidImage(width: 100, height: 100), pixelScale: 1, annotations: [marker]) {
        let on = pixel(out, x: 50, y: 50)
        check("the marker tints the page yellow", on.r > 200 && on.g > 200 && on.b < 90)
        check("…and leaves the rest white", pixel(out, x: 50, y: 70) == (255, 255, 255))
    }
    // Multiplying keeps black text black under a highlighter
    let ink = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ink.setFillColor(CGColor(gray: 1, alpha: 1)); ink.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    ink.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)); ink.fill(CGRect(x: 40, y: 46, width: 20, height: 8))
    if let page = ink.makeImage(), let out = AnnotationRenderer.export(image: page, pixelScale: 1, annotations: [marker]) {
        check("dark text under the marker stays dark", pixel(out, x: 50, y: 50).r < 40)
    }
}

do {
    let c = CanvasView(image: halves(), pixelScale: 1)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 50), styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = c
    func mouse(_ type: NSEvent.EventType, _ p: CGPoint, mods: NSEvent.ModifierFlags = []) {
        let e = NSEvent.mouseEvent(with: type, location: c.convert(p, to: nil), modifierFlags: mods, timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        switch type { case .leftMouseDown: c.mouseDown(with: e); case .leftMouseDragged: c.mouseDragged(with: e); default: c.mouseUp(with: e) }
    }
    func key(_ code: UInt16, _ chars: String = "", _ mods: NSEvent.ModifierFlags = []) {
        c.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: window.windowNumber,
                                         context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!)
    }
    c.tool = .select
    mouse(.leftMouseDown, CGPoint(x: 35, y: 40), mods: [.command]); mouse(.leftMouseUp, CGPoint(x: 35, y: 40), mods: [.command])
    check("⌘-click selects the flat object under the pointer", c.selectionRect == CGRect(x: 0, y: 0, width: 50, height: 50))
    c.setSelection(CGRect(x: 5, y: 5, width: 25, height: 25))
    key(0, "a")
    check("A snaps a loose selection to the content inside it", c.selectionRect == CGRect(x: 10, y: 10, width: 10, height: 10))
    c.setSelection(CGRect(x: 22, y: 22, width: 18, height: 18))
    key(0, "a")
    check("A on flat colour grows the selection to that object", c.selectionRect == CGRect(x: 0, y: 0, width: 50, height: 50))
    c.setSelection(nil)

    // Reversed arrow with ⌘
    c.tool = .arrow
    mouse(.leftMouseDown, CGPoint(x: 10, y: 40)); mouse(.leftMouseDragged, CGPoint(x: 40, y: 40)); mouse(.leftMouseUp, CGPoint(x: 40, y: 40), mods: [.command])
    check("⌘ while finishing an arrow reverses its direction", c.state.annotations.last?.start == CGPoint(x: 40, y: 40) && c.state.annotations.last?.end == CGPoint(x: 10, y: 40))
    check("new arrows are tapered by default", c.state.annotations.last?.tapered == true)
    c.undo()

    // Snapping while dragging
    c.tool = .select
    c.append(Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 5), end: CGPoint(x: 30, y: 15)))
    c.append(Annotation(kind: .rectangle, start: CGPoint(x: 60, y: 30), end: CGPoint(x: 80, y: 40)))
    c.select(nil)
    mouse(.leftMouseDown, CGPoint(x: 60, y: 35)); mouse(.leftMouseDragged, CGPoint(x: 41, y: 35)); mouse(.leftMouseUp, CGPoint(x: 41, y: 35))
    // Moving by -19 would put its left edge at 41; the other rectangle's right edge is 30 and centre 20, image left edge 0, image centre 50 → near 50? left 41, centre 51 snaps to 50.
    let moved = c.state.annotations.last!
    check("dragging snaps the mark's centre to the image centre", abs(moved.bounds.midX - 50) < 0.001)
    Settings.shared.snapToObjects = false
    c.undo()
    mouse(.leftMouseDown, CGPoint(x: 60, y: 35)); mouse(.leftMouseDragged, CGPoint(x: 41, y: 35)); mouse(.leftMouseUp, CGPoint(x: 41, y: 35))
    check("with snapping off it moves exactly", abs(c.state.annotations.last!.bounds.minX - 41) < 0.001)
    Settings.shared.snapToObjects = true
    c.undo()

    // Pen smoothness keys
    c.tool = .freehand
    key(126, "", [.option])
    check("⌥↑ raises the pen smoothness", c.templates[.freehand]?.level == 3)
    key(125, "", [.option]); key(125, "", [.option])
    check("⌥↓ lowers it (not below 0)", c.templates[.freehand]?.level == 1)
    c.tool = .select
}


// MARK: - Round 2: outer measure, quick zoom, GIF, DPI, wallpaper, uploads, hand-drawn

do {
    // A white bar with a black "label" in the middle: normal measuring stops at the label, outer measuring crosses it.
    let c0 = CGContext(data: nil, width: 120, height: 30, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    c0.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.9, alpha: 1)); c0.fill(CGRect(x: 10, y: 5, width: 100, height: 20))   // button
    c0.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)); c0.fill(CGRect(x: 50, y: 10, width: 20, height: 10))        // label
    let button = c0.makeImage()!
    let probe = PixelProbe(image: button)!
    check("plain run stops at the label", probe.run(x: 20, y: 15, horizontal: true) == 10...49)
    check("a run with a gap allowance crosses the label to the real edge", probe.run(x: 20, y: 15, horizontal: true, maxGap: 30) == 10...109)
    check("…but not across a gap that is too wide", probe.run(x: 20, y: 15, horizontal: true, maxGap: 10) == 10...49)
    let cv = CanvasView(image: button, pixelScale: 1)
    let outer = cv.measureMarks(at: CGPoint(x: 20, y: 15), horizontal: true, vertical: false, outer: true)
    check("outer measuring reports the whole button width (100)", outer.first.map { $0.end.x - $0.start.x == 100 } ?? false)
}

do {
    let c = CanvasView(image: halves(), pixelScale: 1)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 50), styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = c
    func mouse(_ type: NSEvent.EventType, _ p: CGPoint, mods: NSEvent.ModifierFlags = []) {
        let e = NSEvent.mouseEvent(with: type, location: c.convert(p, to: nil), modifierFlags: mods, timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        switch type { case .leftMouseDown: c.mouseDown(with: e); case .leftMouseDragged: c.mouseDragged(with: e); default: c.mouseUp(with: e) }
    }
    func key(_ code: UInt16, _ chars: String, up: Bool = false) {
        let e = NSEvent.keyEvent(with: up ? .keyUp : .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                 context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        up ? c.keyUp(with: e) : c.keyDown(with: e)
    }
    var commands: [String] = []
    c.onZoomCommand = { cmd in
        switch cmd {
        case .point(_, let out): commands.append(out ? "out" : "in")
        case .area(let r): commands.append("area \(Int(r.width))x\(Int(r.height))")
        default: commands.append("other")
        }
    }
    c.tool = .rectangle
    let before = c.state.annotations.count
    key(6, "z")
    mouse(.leftMouseDown, CGPoint(x: 20, y: 20)); mouse(.leftMouseUp, CGPoint(x: 20, y: 20))
    mouse(.leftMouseDown, CGPoint(x: 20, y: 20), mods: [.option]); mouse(.leftMouseUp, CGPoint(x: 20, y: 20), mods: [.option])
    mouse(.leftMouseDown, CGPoint(x: 10, y: 10)); mouse(.leftMouseDragged, CGPoint(x: 40, y: 30)); mouse(.leftMouseUp, CGPoint(x: 40, y: 30))
    key(6, "z", up: true)
    check("Z + click zooms in, Z + ⌥-click zooms out, Z + drag zooms to the dragged area", commands == ["in", "out", "area 30x20"])
    check("quick zoom never draws anything", c.state.annotations.count == before)
    mouse(.leftMouseDown, CGPoint(x: 10, y: 10)); mouse(.leftMouseDragged, CGPoint(x: 40, y: 30)); mouse(.leftMouseUp, CGPoint(x: 40, y: 30))
    check("without Z the tool draws as usual", c.state.annotations.count == before + 1)
}

do {
    let a = solidImage(width: 60, height: 40, gray: 1), b = solidImage(width: 80, height: 40, gray: 0)
    if let data = GIFExport.beforeAfter(before: a, after: b), let src = CGImageSourceCreateWithData(data as CFData, nil) {
        check("the before/after GIF has exactly two frames", CGImageSourceGetCount(src) == 2)
        let f0 = CGImageSourceCreateImageAtIndex(src, 0, nil), f1 = CGImageSourceCreateImageAtIndex(src, 1, nil)
        check("both frames share the larger size", f0?.width == 80 && f0?.height == 40 && f1?.width == 80)
        check("the first frame is the 'before' (light), the second the 'after' (dark)", (f0.map { pixel($0, x: 40, y: 20).r } ?? 0) > 200 && (f1.map { pixel($0, x: 40, y: 20).r } ?? 255) < 50)
        check("it is a GIF file", data.prefix(3) == Data("GIF".utf8))
    } else { check("GIF export", false) }

    let wall = solidImage(width: 400, height: 300, gray: 0.3)
    if let over = ImageOps.over(solidImage(width: 100, height: 60, gray: 1), background: wall, margin: 20) {
        check("a window over the wallpaper is padded on every side", over.width == 140 && over.height == 100)
        check("…wallpaper shows in the margin, the window in the middle", pixel(over, x: 5, y: 5).r < 150 && pixel(over, x: 70, y: 50).r > 240)
    } else { check("wallpaper composite", false) }
    check("the wallpaper background needs no fill colour", WindowBackground.wallpaper.rgb == nil && WindowBackground.white.rgb != nil)

    let png = Storage.pngData(from: a, dpi: 144)
    let props = png.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
    check("a Retina PNG is saved with 144 dpi", (props?[kCGImagePropertyDPIWidth] as? Double).map { abs($0 - 144) < 0.5 } ?? false)
    let suite = UserDefaults(suiteName: "chaediew.r2")!
    suite.removePersistentDomain(forName: "chaediew.r2")
    let st = Settings(defaults: suite)
    check("dpi follows the pixel scale unless images are downscaled", Storage.dpi(pixelScale: 2, settings: st) == 144 && Storage.dpi(pixelScale: 1, settings: st) == nil)
    suite.set(true, forKey: Settings.Key.downscaleRetina)
    check("…and is left alone when Retina images are downscaled to 1×", Storage.dpi(pixelScale: 2, settings: st) == nil)
    check("the menu-bar icon is visible by default", !st.hideMenuBarIcon)
    suite.removePersistentDomain(forName: "chaediew.r2")

    let hs = UserDefaults(suiteName: "chaediew.uploads")!
    hs.removePersistentDomain(forName: "chaediew.uploads")
    let history = UploadHistory(defaults: hs)
    history.add(url: URL(string: "https://example.org/a.png")!, name: "a.png", date: Date(timeIntervalSince1970: 100))
    history.add(url: URL(string: "https://example.org/b.png")!, name: "b.png", date: Date(timeIntervalSince1970: 200))
    check("uploads are listed newest first", history.records.map(\.name) == ["b.png", "a.png"])
    history.remove(history.records[0].id)
    check("an entry can be removed", history.records.map(\.name) == ["a.png"])
    for i in 0..<250 { history.add(url: URL(string: "https://example.org/\(i)")!, name: "\(i)") }
    check("the list is capped at 200", history.records.count == 200)
    history.removeAll()
    check("and can be cleared", history.records.isEmpty)
    hs.removePersistentDomain(forName: "chaediew.uploads")

    // Hand-drawn style
    let clean = Annotation(kind: .rectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 120, y: 80), color: .black, lineWidth: 4, rounded: false)
    var sketch = clean; sketch.sketchy = true
    func render(_ a: Annotation) -> CGImage { AnnotationRenderer.export(image: solidImage(width: 140, height: 100), pixelScale: 1, annotations: [a])! }
    let r1 = render(sketch), r2 = render(sketch)
    check("a hand-drawn mark renders identically every time (no shimmer)", (0..<140).allSatisfy { pixel(r1, x: $0, y: 20) == pixel(r2, x: $0, y: 20) })
    let rc = render(clean)
    check("it differs from the clean outline", (0..<140).contains { x in (0..<100).contains { y in pixel(r1, x: x, y: y) != pixel(rc, x: x, y: y) } })
    check("but still draws along the same edges", (20..<120).contains { pixel(r1, x: $0, y: 20).r < 120 || pixel(r1, x: $0, y: 21).r < 120 || pixel(r1, x: $0, y: 19).r < 120 })
    check("and keeps the inside empty", pixel(r1, x: 70, y: 50) == (255, 255, 255))
    var line = Annotation(kind: .line, start: CGPoint(x: 10, y: 50), end: CGPoint(x: 130, y: 50), color: .black, lineWidth: 4); line.sketchy = true
    var arrow = Annotation(kind: .arrow, start: CGPoint(x: 10, y: 50), end: CGPoint(x: 130, y: 50), color: .black, lineWidth: 4); arrow.sketchy = true
    var oval = Annotation(kind: .ellipse, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 120, y: 80), color: .black, lineWidth: 4); oval.sketchy = true
    check("sketchy lines, arrows and ovals all draw",
          (0..<140).contains { pixel(render(line), x: $0, y: 50).r < 100 } && (0..<140).contains { pixel(render(arrow), x: $0, y: 50).r < 100 } && pixel(render(oval), x: 70, y: 50) == (255, 255, 255)
          && (0..<100).contains { pixel(render(oval), x: 20, y: $0).r < 100 || pixel(render(oval), x: 21, y: $0).r < 100 })
}


// MARK: - Customisable backdrop

do {
    let shot = solidImage(width: 100, height: 60, gray: 0.5)
    check("there are 18 presets", BackdropSpec.presets.count == 18)
    var spec = BackdropSpec.solid(RGBColor(200, 30, 30))
    spec.padding = 20; spec.shadow = 0; spec.innerRadius = 0; spec.outerRadius = 0
    do { let out = Backdrop.apply(to: shot, spec: spec, pixelScale: 1)
        check("padding adds the requested space (20 pt each side)", out.width == 140 && out.height == 100)
        check("a solid backdrop fills the margin with its colour", pixel(out, x: 3, y: 3) == (200, 30, 30) && pixel(out, x: 136, y: 96) == (200, 30, 30))
        check("the screenshot sits in the middle", abs(pixel(out, x: 70, y: 50).r - pixel(shot, x: 5, y: 5).r) <= 2)
    }
    spec.padding = 0
    check("zero padding keeps the size", Backdrop.apply(to: shot, spec: spec, pixelScale: 1).width == 100)
    check("an off backdrop returns the image itself", Backdrop.apply(to: shot, spec: .none, pixelScale: 1).width == 100)

    var rounded = BackdropSpec.solid(RGBColor(0, 0, 255)); rounded.padding = 30; rounded.outerRadius = 20; rounded.shadow = 0; rounded.innerRadius = 12
    do { let out = Backdrop.apply(to: shot, spec: rounded, pixelScale: 1)
        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            var b = [UInt8](repeating: 0, count: 4)
            let c = CGContext(data: &b, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(out, in: CGRect(x: -x, y: -(out.height - 1 - y), width: out.width, height: out.height))
            return b[3]
        }
        check("outer radius rounds the backdrop's own corners (transparent)", alpha(0, 0) == 0 && alpha(30, 0) == 255)
        check("inner radius rounds the screenshot's corners (backdrop shows there)", pixel(out, x: 31, y: 31).b > 200 && pixel(out, x: 60, y: 60).b < 160)
    }

    // Gradients
    var mesh = BackdropSpec(); mesh.kind = .gradient; mesh.gradient = .mesh
    mesh.colors = [RGBColor(255, 0, 0), RGBColor(0, 255, 0), RGBColor(0, 0, 255), RGBColor(255, 255, 0)]
    mesh.padding = 40; mesh.shadow = 0; mesh.innerRadius = 0
    do { let out = Backdrop.apply(to: shot, spec: mesh, pixelScale: 1)
        let tl = pixel(out, x: 1, y: 1), tr = pixel(out, x: out.width - 2, y: 1), bl = pixel(out, x: 1, y: out.height - 2), br = pixel(out, x: out.width - 2, y: out.height - 2)
        check("mesh gradient shows its four corner colours (red, green, blue, yellow)", tl.r > 200 && tl.g < 60 && tr.g > 200 && tr.r < 60 && bl.b > 200 && bl.r < 60 && br.r > 200 && br.g > 200)
    }
    var lin = BackdropSpec.linear(RGBColor(0, 0, 0), RGBColor(255, 255, 255), angle: 0)
    lin.padding = 50; lin.shadow = 0; lin.innerRadius = 0
    do { let out = Backdrop.apply(to: shot, spec: lin, pixelScale: 1)
        check("a 0° linear gradient runs left to right", pixel(out, x: 1, y: 10).r < 40 && pixel(out, x: out.width - 2, y: 10).r > 215)
    }
    lin.angle = 90
    do { let out = Backdrop.apply(to: shot, spec: lin, pixelScale: 1)
        check("a 90° linear gradient runs bottom to top", pixel(out, x: 10, y: out.height - 2).r < 40 && pixel(out, x: 10, y: 1).r > 215)
    }
    var radial = BackdropSpec.linear(RGBColor(255, 255, 255), RGBColor(0, 0, 0)); radial.gradient = .radial; radial.padding = 80; radial.shadow = 0; radial.innerRadius = 0
    let framed = shot.width + 160
    _ = framed
    do { let out = Backdrop.apply(to: shot, spec: radial, pixelScale: 1)
        check("a radial gradient is lighter in the middle ring than at the corners", pixel(out, x: 8, y: out.height / 2).r > pixel(out, x: 1, y: 1).r)
    }
    let swapped: BackdropSpec = { var s = BackdropSpec.linear(RGBColor(1, 2, 3), RGBColor(4, 5, 6)); s.swapColors(); return s }()
    check("swap reverses the colour order", swapped.colors[0] == RGBColor(4, 5, 6) && swapped.colors[1] == RGBColor(1, 2, 3))
    var randomised = BackdropSpec.linear(RGBColor(1, 2, 3), RGBColor(4, 5, 6)); randomised.randomizeColors()
    check("randomise changes the colours", randomised.colors[0] != RGBColor(1, 2, 3) || randomised.colors[1] != RGBColor(4, 5, 6))

    // An image backdrop
    let bgURL = FileManager.default.temporaryDirectory.appendingPathComponent("chaediew-bg-\(UUID().uuidString).png")
    try? Storage.pngData(from: solidImage(width: 40, height: 30, gray: 0.2))?.write(to: bgURL)
    var imageSpec = BackdropSpec(); imageSpec.kind = .image; imageSpec.imagePath = bgURL.path; imageSpec.padding = 30; imageSpec.shadow = 0; imageSpec.innerRadius = 0
    do { let out = Backdrop.apply(to: shot, spec: imageSpec, pixelScale: 1)
        check("an image backdrop fills the margin with the picture", pixel(out, x: 3, y: 3).r < 90 && abs(pixel(out, x: 70, y: 50).r - pixel(shot, x: 5, y: 5).r) <= 2)
    }
    try? FileManager.default.removeItem(at: bgURL)

    // Persistence
    let suite = UserDefaults(suiteName: "chaediew.bd")!
    suite.removePersistentDomain(forName: "chaediew.bd")
    check("with nothing saved, the first preset is offered", BackdropSpec.loadSaved(defaults: suite) == BackdropSpec.presets[0].spec)
    var custom = BackdropSpec.presets[3].spec; custom.padding = 77; custom.outerRadius = 9
    custom.save(defaults: suite)
    check("the last backdrop is remembered exactly", BackdropSpec.loadSaved(defaults: suite) == custom)
    suite.removePersistentDomain(forName: "chaediew.bd")

    // The old fixed styles still work
    check("the old style names still map to presets", BackdropStyle.ocean.spec.isOn && !BackdropStyle.none.spec.isOn)
}

// MARK: - Touch-ups after the second user test

do {
    let c = CanvasView(image: halves(), pixelScale: 1)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 50), styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = c
    func mouse(_ type: NSEvent.EventType, _ p: CGPoint) {
        let e = NSEvent.mouseEvent(with: type, location: c.convert(p, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        switch type { case .leftMouseDown: c.mouseDown(with: e); case .leftMouseDragged: c.mouseDragged(with: e); default: c.mouseUp(with: e) }
    }
    c.tool = .counter
    mouse(.leftMouseDown, CGPoint(x: 20, y: 20)); mouse(.leftMouseUp, CGPoint(x: 20, y: 20))
    mouse(.leftMouseDown, CGPoint(x: 70, y: 20)); mouse(.leftMouseUp, CGPoint(x: 70, y: 20))
    check("two counters are placed and numbered", c.state.annotations.map(\.number) == [1, 2])
    Settings.shared.snapToObjects = false
    mouse(.leftMouseDown, CGPoint(x: 20, y: 20)); mouse(.leftMouseDragged, CGPoint(x: 20, y: 40)); mouse(.leftMouseUp, CGPoint(x: 20, y: 40))
    Settings.shared.snapToObjects = true
    check("with the counter tool still active, pressing on an old counter moves it", c.state.annotations.count == 2 && c.state.annotations.first { $0.number == 1 }?.start.y == 40)
    c.undo()
    check("…as one undo step", c.state.annotations.first { $0.number == 1 }?.start.y == 20)
    mouse(.leftMouseDown, CGPoint(x: 45, y: 20)); mouse(.leftMouseUp, CGPoint(x: 45, y: 20))
    check("pressing on empty space still adds the next counter", c.state.annotations.count == 3 && c.state.annotations.last?.number == 3)

    // Hand-drawn oval is a loop whose ends overlap
    let oval = Annotation(kind: .ellipse, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 110, y: 70), sketchy: true)
    let loop = Sketch.loopPoints(oval.rect, seed: Sketch.seed(oval))
    let travelled = zip(loop, loop.dropFirst()).reduce(CGFloat(0)) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    check("the hand-drawn oval travels more than one full lap (ends overlap)", travelled > 2 * .pi * 30 * 1.0 && hypot(loop.first!.x - loop.last!.x, loop.first!.y - loop.last!.y) < 90)
    check("the loop is stable for the same mark", Sketch.loopPoints(oval.rect, seed: Sketch.seed(oval)) == loop)
}


// MARK: - Counter text, text colours, retyping picture text

do {
    check("counter text steps the last number: 1.1 → 1.2, 3.6 → 3.7, A9 → A10, 7 → 8",
          CounterText.next("1.1") == "1.2" && CounterText.next("3.6") == "3.7" && CounterText.next("A9") == "A10" && CounterText.next("7") == "8")
    check("…keeps leading zeros and handles no digits", CounterText.next("007") == "008" && CounterText.next("abc") == "1" && CounterText.step("2.1", by: -1) == "2.0" && CounterText.step("0", by: -1) == "0")
    check("multi-dot values step only the last component", CounterText.next("v1.2.3") == "v1.2.4")

    var wide = Annotation(kind: .counter, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 50, y: 50), number: 1)
    let narrow = wide.bounds.width
    wide.label = "12.3.4"
    check("a long counter text widens the bubble into a capsule", wide.bounds.width > narrow + 10 && wide.bounds.midX == 50)
    if let out = AnnotationRenderer.export(image: solidImage(width: 140, height: 100), pixelScale: 1, annotations: [Annotation(kind: .counter, start: CGPoint(x: 70, y: 50), end: CGPoint(x: 70, y: 50), color: .black, angle: 0, label: "12.3.4")]) {
        check("the capsule is painted across its whole width", pixel(out, x: 70 - Int(wide.bounds.width / 2) + 4, y: 50).r < 100)
    }
    let custom = Annotation(kind: .counter, start: .zero, end: .zero, color: .black, number: 5, textColor: NSColor.yellow)
    check("counters and labels take an explicit lettering colour, or pick black/white", custom.labelTextColor == NSColor.yellow && Annotation(kind: .counter, start: .zero, end: .zero, color: .black).labelTextColor == .white)

    let c = CanvasView(image: halves(), pixelScale: 1)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 50), styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = c
    func mouse(_ type: NSEvent.EventType, _ p: CGPoint, clicks: Int = 1) {
        let e = NSEvent.mouseEvent(with: type, location: c.convert(p, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        switch type { case .leftMouseDown: c.mouseDown(with: e); case .leftMouseDragged: c.mouseDragged(with: e); default: c.mouseUp(with: e) }
    }
    c.tool = .counter
    c.setCounterText("1.1")
    check("the next counter can be set to any text before placing it", c.nextCounterText == "1.1")
    mouse(.leftMouseDown, CGPoint(x: 15, y: 15)); mouse(.leftMouseUp, CGPoint(x: 15, y: 15))
    check("it is placed with that text", c.state.annotations.last?.counterText == "1.1")
    check("and the next one continues from it (1.2)", c.nextCounterText == "1.2")
    mouse(.leftMouseDown, CGPoint(x: 60, y: 15)); mouse(.leftMouseUp, CGPoint(x: 60, y: 15))
    mouse(.leftMouseDown, CGPoint(x: 80, y: 40)); mouse(.leftMouseUp, CGPoint(x: 80, y: 40))
    check("placing more counters keeps counting 1.2, 1.3", c.state.annotations.map(\.counterText) == ["1.1", "1.2", "1.3"])
    c.select(0)
    c.setCounterText("3.6")
    check("the value of a placed counter can be changed from the panel", c.state.annotations[0].counterText == "3.6")
    c.undo()
    check("…as one undo step", c.state.annotations[0].counterText == "1.1")
    mouse(.leftMouseDown, CGPoint(x: 60, y: 15), clicks: 2)   // double-click opens the inline value editor
    check("double-clicking a counter opens an editor on it (no new counter)", c.state.annotations.count == 3 && c.subviews.contains { $0 is NSTextField })

    // A style change reaches the label being typed straight away
    let t2 = CanvasView(image: halves(), pixelScale: 1)
    let w2 = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 50), styleMask: [.titled], backing: .buffered, defer: true)
    w2.contentView = t2
    t2.tool = .text
    let down = NSEvent.mouseEvent(with: .leftMouseDown, location: t2.convert(CGPoint(x: 10, y: 10), to: nil), modifierFlags: [], timestamp: 0, windowNumber: w2.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    t2.mouseDown(with: down)
    if let field = t2.subviews.compactMap({ $0 as? NSTextField }).first {
        t2.updateStyle { $0.color = .systemGreen; $0.fontSize = 40; $0.pill = false }
        check("changing the colour while typing changes the field at once (no need to click away)", field.textColor == NSColor.systemGreen)
        check("…and so does the size", field.font?.pointSize == 40)
        t2.updateStyle { $0.pill = true; $0.color = .black; $0.textColor = .yellow }
        check("a label's own lettering colour applies to the field live", field.drawsBackground && field.textColor == .yellow)
    } else { check("a typing field opened", false) }
}

do {
    // Font matching: render known text in known faces and see if they are recognised.
    func lineImage(_ text: String, fontName: String?, bold: Bool, size: CGFloat, ink: NSColor, bg: NSColor) -> (CGImage, CGRect) {
        let font: NSFont = fontName.flatMap { NSFont(name: $0, size: size) }.map { bold ? NSFontManager.shared.convert($0, toHaveTrait: .boldFontMask) : $0 }
            ?? (bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size))
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
        let measured = NSString(string: text).size(withAttributes: attrs)
        let w = Int(measured.width) + 80, h = Int(measured.height) + 60
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setFillColor(bg.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSString(string: text).draw(at: CGPoint(x: 40, y: 30), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        // The line's rectangle as OCR would report it: the text box in top-left image coordinates.
        return (ctx.makeImage()!, CGRect(x: 40, y: CGFloat(h) - 30 - measured.height, width: measured.width, height: measured.height))
    }
    let samples: [(String?, Bool)] = [("Georgia", true), ("Menlo", false), ("Arial", true)]
    for (name, bold) in samples {
        let (img, rect) = lineImage("Quarterly total 4,500 baht", fontName: name, bold: bold, size: 44, ink: NSColor(srgbRed: 0.1, green: 0.2, blue: 0.6, alpha: 1), bg: NSColor(srgbRed: 0.96, green: 0.94, blue: 0.85, alpha: 1))
        if let g = FontMatcher.guess(image: img, lineRect: rect, text: "Quarterly total 4,500 baht", pixelScale: 1) {
            let sizeOK = abs(g.sizePoints - 44) / 44 < 0.12
            check("font match: \(name ?? "system") \(bold ? "bold" : "regular") is recognised (got \(g.fontName ?? "system") \(g.bold ? "bold" : "regular"), \(Int(g.sizePoints))pt, score \(String(format: "%.2f", g.score)))",
                  (g.fontName == name && g.bold == bold || g.score > 0.5 && g.fontName == name) && sizeOK)
            check("  …ink colour is the text's (blue), background is the page's", g.ink.usingColorSpace(.sRGB)!.blueComponent > 0.45 && g.ink.usingColorSpace(.sRGB)!.redComponent < 0.3 && g.background.usingColorSpace(.sRGB)!.redComponent > 0.9)
        } else { check("font match for \(name ?? "system")", false) }
    }
    let (sysImg, sysRect) = lineImage("Settings and Preferences", fontName: nil, bold: false, size: 36, ink: .black, bg: .white)
    let sysGuess = FontMatcher.guess(image: sysImg, lineRect: sysRect, text: "Settings and Preferences", pixelScale: 1)
    check("the system font is matched by the system font or its close cousin Helvetica Neue", sysGuess.map { $0.fontName == nil || $0.fontName == "Helvetica Neue" } ?? false)
    check("a retina 2× picture reports the size in points (half the pixel size)", {
        let (img, rect) = lineImage("Retina text sample", fontName: "Georgia", bold: false, size: 60, ink: .black, bg: .white)
        return FontMatcher.guess(image: img, lineRect: rect, text: "Retina text sample", pixelScale: 2).map { abs($0.sizePoints - 30) < 4 } ?? false
    }())
    check("flat colour with no text has nothing to match", FontMatcher.guess(image: solidImage(width: 200, height: 40), lineRect: CGRect(x: 10, y: 5, width: 150, height: 30), text: "x", pixelScale: 1) == nil)
}


// MARK: - Licensing

do {
    let signer = Curve25519.Signing.PrivateKey()
    let other = Curve25519.Signing.PrivateKey()
    let today = Date(timeIntervalSince1970: 1_792_411_200)  // 2026-10-19
    let yearOn = today.addingTimeInterval(365 * 86_400)
    let key = try! LicenseKey.issue(licensee: "Panupong Nijjaboon", seats: 25, expires: yearOn, now: today, privateKey: signer)
    check("a key starts with TXCD1 and is grouped", key.hasPrefix("TXCD1-") && key.split(separator: "-").count > 10)
    print("      (key length \(key.count) characters)")
    if let info = try? LicenseKey.verify(key, publicKey: signer.publicKey, now: today) {
        check("a genuine key verifies and carries its details", info.licensee == "Panupong Nijjaboon" && info.seats == 25 && info.expires != nil && info.keyID.count == 12)
        check("…the expiry is a year ahead", abs((info.expires!.timeIntervalSince(today)) - 365 * 86_400) < 2 * 86_400)
    } else { check("genuine key verifies", false) }
    check("a key does not verify under another public key", (try? LicenseKey.verify(key, publicKey: other.publicKey, now: today)) == nil)
    var tampered = Array(key)
    let idx = tampered.firstIndex { $0 == "A" } ?? 20
    tampered[idx] = tampered[idx] == "B" ? "C" : "B"
    check("changing a single character breaks the signature", (try? LicenseKey.verify(String(tampered), publicKey: signer.publicKey, now: today)) == nil)
    check("a truncated key is rejected as malformed", { do { _ = try LicenseKey.verify(String(key.dropLast(12)), publicKey: signer.publicKey, now: today); return false } catch { return true } }())
    check("text that is not a key is rejected", { do { _ = try LicenseKey.verify("hello world", publicKey: signer.publicKey); return false } catch LicenseError.malformed { return true } catch { return false } }())
    check("pasting with spaces, line breaks and lower case still works", (try? LicenseKey.verify(" " + key.lowercased().replacingOccurrences(of: "-", with: "\n") + "\n", publicKey: signer.publicKey, now: today)) != nil)
    check("an expired key is refused after its last day",
          { do { _ = try LicenseKey.verify(key, publicKey: signer.publicKey, now: yearOn.addingTimeInterval(3 * 86_400)); return false } catch LicenseError.expired { return true } catch { return false } }())
    let forever = try! LicenseKey.issue(licensee: "Everyone", expires: nil, now: today, privateKey: signer)
    check("a perpetual key never expires", (try? LicenseKey.verify(forever, publicKey: signer.publicKey, now: today.addingTimeInterval(20 * 365 * 86_400))).map { $0.expires == nil } ?? false)
    check("two keys for the same person are different (random id)", try! LicenseKey.issue(licensee: "Everyone", expires: nil, now: today, privateKey: signer) != forever)
    let thai = try! LicenseKey.issue(licensee: "บริษัท เท็นนิค จำกัด (มหาชน) สาขาใหญ่มากๆ", privateKey: signer)
    check("a long Thai name is cut on a character boundary and still verifies", (try? LicenseKey.verify(thai, publicKey: signer.publicKey))?.licensee.isEmpty == false)

    // The shipped public key matches the keygen's private key (the one that issues real keys)
    let keyFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Tenix-ChaeDiew-Keygen/private.key")
    if let text = try? String(contentsOf: keyFile, encoding: .utf8), let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
       let priv = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
        let real = try! LicenseKey.issue(licensee: "Check", privateKey: priv)
        check("a key from the real issuer is accepted by the app's embedded public key", (try? LicenseManager(secrets: MemorySecrets(), now: { Date() }).activate(real)) != nil)
    } else { print("      (skipped: issuer private key not on this machine)") }

    // Machine binding: one key = one computer
    let macA = "11111111-AAAA-BBBB-CCCC-000000000001", macB = "22222222-AAAA-BBBB-CCCC-000000000002"
    let codeA = MachineBinding.machineCode(rawID: macA)
    check("a machine code looks like MC-XXXX-XXXX-XXXX-XXXX", codeA.count == 22 && codeA.hasPrefix("MC-") && codeA.split(separator: "-").count == 5)
    check("the machine code is stable and differs per computer", codeA == MachineBinding.machineCode(rawID: macA.lowercased()) && codeA != MachineBinding.machineCode(rawID: macB))
    check("a typed-back machine code parses (any case, spaces, no dashes)", MachineBinding.parseMachineCode(" " + codeA.lowercased().replacingOccurrences(of: "-", with: " ") + " ") == MachineBinding.machineBytes(rawID: macA))
    check("junk is not a machine code", MachineBinding.parseMachineCode("MC-1234") == nil)
    let bound = try! LicenseKey.issue(licensee: "Bound", seats: 1, expires: nil, now: today, privateKey: signer)
    let boundInfo = try! LicenseKey.verify(bound, publicKey: signer.publicKey, now: today)
    let activationA = try! MachineBinding.issueActivation(keyID: boundInfo.keyID, machine: MachineBinding.machineBytes(rawID: macA), privateKey: signer)
    check("an activation code is TXAC1 plus a 64-byte signature (~110 characters)", activationA.hasPrefix("TXAC1-") && activationA.count > 100 && activationA.count < 130)
    print("      (activation length \(activationA.count) characters)")
    check("the activation verifies for its own key and computer", MachineBinding.verifyActivation(activationA, keyID: boundInfo.keyID, machine: MachineBinding.machineBytes(rawID: macA), publicKey: signer.publicKey))
    check("…not on another computer", !MachineBinding.verifyActivation(activationA, keyID: boundInfo.keyID, machine: MachineBinding.machineBytes(rawID: macB), publicKey: signer.publicKey))
    check("…not for another key", !MachineBinding.verifyActivation(activationA, keyID: "AABBCCDDEEFF", machine: MachineBinding.machineBytes(rawID: macA), publicKey: signer.publicKey))
    check("…not under another issuer", !MachineBinding.verifyActivation(activationA, keyID: boundInfo.keyID, machine: MachineBinding.machineBytes(rawID: macA), publicKey: other.publicKey))
    check("a license key is not mistaken for an activation code (and vice versa)", !MachineBinding.looksLikeActivation(bound) && MachineBinding.looksLikeActivation(activationA))

    // Trial and activation
    var clock = today
    let secrets = MemorySecrets()
    let manager = LicenseManager(secrets: secrets, now: { clock }, publicKey: signer.publicKey, machineID: { macA }, requireActivation: true)
    check("the first look starts a 14-day trial", manager.status == .trial(daysLeft: 14) && manager.allowsUse)
    clock = today.addingTimeInterval(10 * 86_400 + 3_600)
    check("days count down", manager.status == .trial(daysLeft: 4))
    clock = today.addingTimeInterval(15 * 86_400)
    check("after the trial, use is refused", manager.status == .trialEnded && !manager.allowsUse)
    check("an invalid key cannot be activated", (try? manager.activate("TXCD1-NOPE")) == nil && manager.status == .trialEnded)
    check("an activation code before any key is refused", { do { _ = try manager.activate(activationA); return false } catch LicenseError.activationNeedsKey { return true } catch { return false } }())
    clock = today
    check("the manager shows this computer's machine code", manager.machineCode == codeA)
    if let info = try? manager.activate(bound) {
        check("a genuine key alone is stored but waits for activation", manager.storedKey != nil && manager.status == .needsActivation(info, trialDaysLeft: 14) && manager.allowsUse)
        clock = today.addingTimeInterval(15 * 86_400)
        check("…and once the trial is over a key without activation does not unlock anything", !manager.allowsUse)
        let wrongMachine = try! MachineBinding.issueActivation(keyID: info.keyID, machine: MachineBinding.machineBytes(rawID: macB), privateKey: signer)
        check("an activation code made for another computer is refused", { do { _ = try manager.activate(wrongMachine); return false } catch LicenseError.wrongActivation { return true } catch { return false } }())
        check("…and changes nothing", !manager.allowsUse)
        check("the right activation code switches the app on", (try? manager.activate(activationA)) != nil && manager.status == .licensed(info) && manager.allowsUse)
        check("an activated licence keeps working long after the trial", manager.allowsUse)
        // The same stored values on a different computer (copied Keychain/profile) do not unlock it.
        let copied = MemorySecrets()
        copied.set(secrets.get("license-key") ?? "", account: "license-key"); copied.set(secrets.get("activation-code") ?? "", account: "activation-code")
        copied.set(secrets.get("trial-start") ?? "", account: "trial-start")
        let elsewhere = LicenseManager(secrets: copied, now: { clock }, publicKey: signer.publicKey, machineID: { macB }, requireActivation: true)
        check("a key and activation copied to another computer do not work there", !elsewhere.allowsUse)
        let again = LicenseManager(secrets: copied, now: { clock }, publicKey: signer.publicKey, machineID: { macA }, requireActivation: true)
        check("…but still work on the original computer", again.allowsUse)
        // Entering a different key discards the old activation.
        let second = try! LicenseKey.issue(licensee: "Second", seats: 1, expires: nil, now: today, privateKey: signer)
        _ = try? manager.activate(second)
        check("a different key needs its own activation", manager.storedActivation == nil)
        _ = try? manager.activate(bound)
        _ = try? manager.activate(activationA)
        check("…and re-entering the first key and its code works again", manager.status == .licensed(boundInfo))
    } else { check("activation", false) }
    clock = today.addingTimeInterval(15 * 86_400)
    check("(still licensed after the trial would have ended)", manager.allowsUse)
    clock = today
    let termKey = try! LicenseKey.issue(licensee: "Term", seats: 1, expires: today.addingTimeInterval(30 * 86_400), now: today, privateKey: signer)
    let termInfo = try! manager.activate(termKey)
    _ = try? manager.activate(try! MachineBinding.issueActivation(keyID: termInfo.keyID, machine: MachineBinding.machineBytes(rawID: macA), privateKey: signer))
    clock = yearOn.addingTimeInterval(30 * 86_400)
    check("when the key itself has expired, use stops (trial long over)", { if case .keyProblem = manager.status { return !manager.allowsUse } else { return false } }())
    // Default mode: a genuine key is enough
    var simpleClock = today
    let simple = LicenseManager(secrets: MemorySecrets(), now: { simpleClock }, publicKey: signer.publicKey, machineID: { macA })
    check("default: no key → trial", simple.status == .trial(daysLeft: 14))
    simpleClock = today.addingTimeInterval(20 * 86_400)
    check("default: trial over → blocked", !simple.allowsUse)
    check("default: a junk key is refused", (try? simple.activate("TXCD1-NOPE")) == nil)
    if let info = try? simple.activate(bound) {
        check("default: a genuine key is Licensed at once, no activation code needed", simple.status == .licensed(info) && simple.allowsUse)
        check("default: the same key works on any computer (machine id is ignored)", LicenseManager(secrets: { let m = MemorySecrets(); m.set(bound, account: "license-key"); return m }(), now: { simpleClock }, publicKey: signer.publicKey, machineID: { macB }).allowsUse)
        check("default: an activation code is still accepted but not needed", (try? simple.activate(activationA)) != nil && simple.allowsUse)
    } else { check("default activation", false) }
    let shortLived = try! LicenseKey.issue(licensee: "Short", expires: today.addingTimeInterval(10 * 86_400), now: today, privateKey: signer)
    simpleClock = today
    _ = try? simple.activate(shortLived)
    simpleClock = today.addingTimeInterval(40 * 86_400)
    check("default: an expired key stops working", !simple.allowsUse)

    manager.remove()
    check("removing the key clears the activation too and returns to the trial state", manager.storedKey == nil && manager.storedActivation == nil && manager.status == .trialEnded)
    check("the trial start survives (it cannot be reset by removing the key)", manager.status != .trial(daysLeft: 14))
}

// MARK: - Backdrop

let shot = AnnotationRenderer.export(image: solidImage(width: 100, height: 80, gray: 0), pixelScale: 1, annotations: [])!
let framed = Backdrop.apply(to: shot, style: .light, pixelScale: 1)
check("backdrop adds padding on every side", framed.width == 196 && framed.height == 176)
check("backdrop shows the gradient in the corner", pixel(framed, x: 2, y: 2).r > 200)
check("backdrop paints every corner (no unpainted gaps)", [(2, 2), (framed.width - 3, 2), (2, framed.height - 3), (framed.width - 3, framed.height - 3)].allSatisfy { pixel(framed, x: $0.0, y: $0.1).r > 150 })
check("backdrop keeps the screenshot in the middle", pixel(framed, x: 98, y: 88).r < 30)
check("backdrop .none returns the image unchanged", Backdrop.apply(to: shot, style: .none, pixelScale: 1).width == 100)

// MARK: - Colour formats

check("hex", ColorFormats.string(r: 1, g: 0.5, b: 0, format: .hex) == "#FF8000")
check("rgb", ColorFormats.string(r: 1, g: 0, b: 0, format: .rgb) == "rgb(255, 0, 0)")
check("hsl of red", ColorFormats.string(r: 1, g: 0, b: 0, format: .hsl) == "hsl(0, 100%, 50%)")
let red = ColorFormats.oklch(r: 1, g: 0, b: 0)
check("oklch of red matches the CSS Color 4 reference (0.628, 0.258, 29.23°)",
      abs(red.l - 0.6280) < 0.002 && abs(red.c - 0.2577) < 0.002 && abs(red.h - 29.23) < 0.3)
let white = ColorFormats.oklch(r: 1, g: 1, b: 1)
check("oklch of white is L=1, no chroma", abs(white.l - 1) < 0.001 && white.c < 0.001)

// MARK: - Settings & hotkeys

let suite = "chaediew.checks"
UserDefaults().removePersistentDomain(forName: suite)
let settings = Settings(defaults: UserDefaults(suiteName: suite)!)
check("default area hotkey is ⌃⇧4", settings.hotKey(for: .area)?.display == "⌃⇧4")
settings.setHotKey(HotKeySpec(keyCode: 0x00, modifiers: 256 | 2048), for: .area)  // ⌘⌥A
check("custom hotkey round-trips", settings.hotKey(for: .area) == HotKeySpec(keyCode: 0, modifiers: 2304))
settings.setHotKey(nil, for: .ocr)
check("hotkey can be switched off", settings.hotKey(for: .ocr) == nil)
settings.resetHotKey(for: .ocr)
check("reset restores the default", settings.hotKey(for: .ocr)?.display == "⌃⇧2")
check("all default hotkeys are distinct",
      Set(HotKeyAction.allCases.map { $0.defaultSpec.stored }).count == HotKeyAction.allCases.count)
check("every built-in redaction pattern is enabled by default", settings.enabledRedactionIDs.count == Redactor.builtins.count)
UserDefaults().removePersistentDomain(forName: suite)

// MARK: - Redaction patterns

func ids(_ text: String, _ only: String) -> Int {
    let p = Redactor.patterns(enabledIDs: [only], custom: [])
    return Redactor.matches(in: text, patterns: p).count
}
check("finds an email", ids("mail john.doe@example.com now", "email") == 1)
check("Thai ID: valid checksum is found", ids("ID 1234567890121 ok", "thai_id") == 1)
check("Thai ID: wrong checksum is ignored", ids("ID 1234567890122 ok", "thai_id") == 0)
check("Thai ID: dashed format is found", ids("1-2345-67890-12-1", "thai_id") == 1)
check("card: Luhn-valid number is found", ids("card 4111 1111 1111 1111", "card") == 1)
check("card: Luhn-invalid number is ignored", ids("card 4111 1111 1111 1112", "card") == 0)
check("phone: mobile", ids("tel 081-234-5678", "phone_th") == 1)
check("phone: landline and +66", ids("02-123-4567 / +66 81 234 5678", "phone_th") == 2)
check("ip: valid found, invalid ignored", ids("host 192.168.1.10", "ip") == 1 && ids("host 999.1.1.1", "ip") == 0)
check("secret: AWS key", ids("key AKIAIOSFODNN7EXAMPLE end", "secret") == 1)
check("password assignment", ids("password: hunter2", "password") == 1)
let custom = Redactor.patterns(enabledIDs: [], custom: ["EMP-\\d{5}", "(["])
check("custom regex works and a broken one is skipped",
      custom.count == 1 && Redactor.matches(in: "id EMP-12345", patterns: custom).count == 1)

// MARK: - AWS Signature V4 (official AWS documentation examples)

let awsDate = Date(timeIntervalSince1970: 1_369_353_600)  // 2013-05-24T00:00:00Z
let signer = SigV4(accessKey: "AKIAIOSFODNN7EXAMPLE", secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", region: "us-east-1")
check("SigV4 timestamp format", SigV4.amzDate(awsDate) == "20130524T000000Z")

let emptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
let get = signer.sign(
    method: "GET", path: "/test.txt", query: [],
    headers: [("host", "examplebucket.s3.amazonaws.com"), ("range", "bytes=0-9"),
              ("x-amz-content-sha256", emptyHash), ("x-amz-date", "20130524T000000Z")],
    payloadHash: emptyHash, date: awsDate)
check("SigV4 header-signed GET matches AWS example",
      get.signature == "f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")

let body = Data("Welcome to Amazon S3.".utf8)
let put = signer.sign(
    method: "PUT", path: "/test$file.text", query: [],
    headers: [("date", "Fri, 24 May 2013 00:00:00 GMT"), ("host", "examplebucket.s3.amazonaws.com"),
              ("x-amz-content-sha256", SigV4.sha256Hex(body)), ("x-amz-date", "20130524T000000Z"),
              ("x-amz-storage-class", "REDUCED_REDUNDANCY")],
    payloadHash: SigV4.sha256Hex(body), date: awsDate)
check("SigV4 PUT (with $ in the key) matches AWS example",
      put.signature == "98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd")

let presigned = signer.presignedURL(host: "examplebucket.s3.amazonaws.com", path: "/test.txt", expires: 86400, date: awsDate)
check("SigV4 presigned URL matches AWS example",
      presigned?.absoluteString.hasSuffix("X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404") == true)

let aws = S3Config(region: "eu-west-1", bucket: "b", accessKey: "k", secretKey: "s")
check("AWS endpoint uses virtual-hosted style", (try? aws.location(key: "x/y.png"))?.host == "b.s3.eu-west-1.amazonaws.com")
let minio = S3Config(endpoint: "http://localhost:9000", region: "us-east-1", bucket: "b", accessKey: "k", secretKey: "s")
let loc = try? minio.location(key: "x/y.png")
check("custom endpoint uses path style with its port", loc?.host == "localhost:9000" && loc?.path == "/b/x/y.png" && loc?.scheme == "http")
check("upload reply parsing: json url / nested / bare",
      Uploader.parseLink(from: Data(#"{"url":"https://a/b"}"#.utf8))?.absoluteString == "https://a/b"
      && Uploader.parseLink(from: Data(#"{"data":{"url":"https://c/d"}}"#.utf8))?.absoluteString == "https://c/d"
      && Uploader.parseLink(from: Data("https://e/f\n".utf8))?.absoluteString == "https://e/f"
      && Uploader.parseLink(from: Data("nope".utf8)) == nil)

// MARK: - Scroll stitching

let page = makePage(width: 120, height: 1500)
let pageHashes = ScrollStitcher.rowHashes(page)

let down = ScrollStitcher()
for off in [0, 130, 260, 500, 640, 900, 1100] { down.add(frame(of: page, offset: off, height: 400)) }
if let joined = down.finish() {
    check("scroll down: stitched height equals the page", joined.height == 1500)
    check("scroll down: every row matches the original page", ScrollStitcher.rowHashes(joined) == pageHashes)
} else { check("scroll down: finish", false) }

let up = ScrollStitcher()
for off in [1100, 900, 640, 500, 260, 130, 0] { up.add(frame(of: page, offset: off, height: 400)) }
if let joined = up.finish() {
    check("scroll up: stitched height equals the page", joined.height == 1500)
    check("scroll up: every row matches the original page", ScrollStitcher.rowHashes(joined) == pageHashes)
} else { check("scroll up: finish", false) }

let header = page.cropping(to: CGRect(x: 0, y: 0, width: 120, height: 30))!
let sticky = ScrollStitcher()
for off in [0, 130, 260, 500, 640] { sticky.add(frame(of: page, offset: off, height: 400, stickyHeader: header)) }
if let joined = sticky.finish() {
    let hashes = ScrollStitcher.rowHashes(joined)
    check("sticky header: height is right", joined.height == 1040)
    check("sticky header: content below the header is seamless", Array(hashes[30..<1040]) == Array(pageHashes[30..<1040]))
} else { check("sticky header: finish", false) }

let probe = ScrollStitcher()
probe.add(frame(of: page, offset: 0, height: 400))
check("identical frame reports no change", probe.add(frame(of: page, offset: 0, height: 400)) == .noChange)
check("a jump larger than the overlap is rejected, not guessed", probe.add(frame(of: page, offset: 395, height: 400)) == .unmatched)
check("an unrelated frame is rejected", probe.add(makePage(width: 120, height: 400, seed: 12345)) == .unmatched)
check("a rejected frame doesn't grow the result", probe.totalHeight == 400)
let capped = ScrollStitcher(maxHeight: 500)
capped.add(frame(of: page, offset: 0, height: 400))
check("height limit stops growth", capped.add(frame(of: page, offset: 200, height: 400)) == .limitReached)

// MARK: - Library

let libDir = FileManager.default.temporaryDirectory.appendingPathComponent("chaediew-lib-\(UUID().uuidString)")
let lib = LibraryStore(folder: libDir)
let itemA = lib.add(image: solidImage(width: 20, height: 10), pixelScale: 2, date: Date(timeIntervalSince1970: 1_700_000_000))  // Nov 2023: older than any retention window
let itemB = lib.add(image: solidImage(width: 30, height: 30), pixelScale: 1)
if let a = itemA, let b = itemB {
    lib.setOCRText("Invoice 2026 total 4,500 baht", for: a.id)
    lib.setOCRText("Meeting notes for the Bangkok office", for: b.id)
    check("library search is case-insensitive", lib.search("INVOICE").map(\.id) == [a.id])
    check("library search needs every term", lib.search("meeting bangkok").map(\.id) == [b.id] && lib.search("invoice bangkok").isEmpty)
    check("library search finds by date", lib.search("2023-11-1").contains { $0.id == a.id })
    check("empty search lists everything, newest first", lib.search("").count == 2 && lib.search("").first?.id == b.id)
    check("library files exist on disk", FileManager.default.fileExists(atPath: lib.url(for: a).path))
    let reloaded = LibraryStore(folder: libDir)
    check("library persists across launches (incl. OCR text)", reloaded.search("invoice").map(\.id) == [a.id])
    check("thumbnails load", LibraryStore.thumbnail(at: lib.url(for: a), maxPixel: 16) != nil)
    check("retention purges only old items", lib.purge(olderThanDays: 30) == 1 && lib.items.map(\.id) == [b.id])
    check("purged file is deleted from disk", !FileManager.default.fileExists(atPath: lib.url(for: a).path))
    lib.remove(b.id)
    check("remove empties the library", lib.items.isEmpty)
} else { check("library add", false) }
try? FileManager.default.removeItem(at: libDir)

// MARK: - OCR on a rendered image (needs Vision; runs on-device)

func textImage(_ text: String) -> CGImage {
    let w = 900, h = 140
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    NSString(string: text).draw(at: CGPoint(x: 20, y: 45), withAttributes: [
        .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
    NSGraphicsContext.restoreGraphicsState()
    return c.makeImage()!
}

let scene = textImage("Contact: john.doe@example.com")
do {
    let text = try await OCR.recognize(scene)
    check("OCR reads rendered text", text.lowercased().contains("example"))
    let patterns = Redactor.patterns(enabledIDs: ["email"], custom: [])
    let regions = try await Redactor.regions(in: scene, patterns: patterns)
    check("auto-redact locates the email on the right half of the line", regions.count == 1 && (regions.first?.midX ?? 0) > 350)
    if let region = regions.first {
        let a = Annotation(kind: .blur, start: region.origin, end: CGPoint(x: region.maxX, y: region.maxY))
        let hidden = AnnotationRenderer.export(image: scene, pixelScale: 1, annotations: [a])!
        let after = try await OCR.recognize(hidden)
        check("after pixelating, OCR can no longer read the email", !after.lowercased().contains("example.com"))
    }
} catch {
    check("OCR/auto-redact (Vision error: \(error))", false)
}

// Screen-sized page (2800×1600, like a Retina capture): must finish in reasonable time and find the PII.
func screenPage() -> CGImage {
    let w = 2800, h = 1600
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    c.setFillColor(CGColor(gray: 0.97, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    let lines = ["Name: Somchai Jaidee", "Email: somchai.jaidee@example.com", "National ID: 1-2345-67890-12-1",
                 "Phone: 081-234-5678", "Server: 192.168.10.25"]
    for (i, text) in lines.enumerated() {
        NSString(string: text).draw(at: CGPoint(x: 120, y: CGFloat(h) - 480 - CGFloat(i) * 160), withAttributes: [
            .font: NSFont.systemFont(ofSize: 72), .foregroundColor: NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState()
    return c.makeImage()!
}
let bigStart = Date()
do {
    let found = try await Redactor.regions(
        in: screenPage(), patterns: Redactor.patterns(enabledIDs: Set(Redactor.builtins.map(\.id)), custom: []))
    let secs = Date().timeIntervalSince(bigStart)
    print(String(format: "      (screen-size OCR took %.1fs)", secs))
    check("screen-size page: email, ID, phone and IP are all located", found.count == 4)
    check("screen-size page: OCR finishes in under 20s", secs < 20)
} catch {
    check("screen-size OCR (Vision error: \(error))", false)
}

let qrContext = CIContext()
if let qr = CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data("https://example.org/hello".utf8)])?.outputImage {
    let scaled = qr.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
    if let cg = qrContext.createCGImage(scaled, from: scaled.extent) {
        let found = (try? await Barcode.detect(in: cg)) ?? []
        check("QR code round-trips through detection", found == ["https://example.org/hello"])
    } else { check("QR render", false) }
} else { check("QR generator", false) }

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
