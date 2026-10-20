import CoreGraphics
import Foundation

public struct RedactionPattern {
    public let id: String
    public let name: String
    public let regex: String
    public var caseInsensitive = true
    /// Extra check on the matched text (checksums), to avoid hiding harmless numbers.
    public var validate: (String) -> Bool = { _ in true }
}

/// Finds personal / secret data in OCR text so it can be pixelated automatically.
public enum Redactor {
    public static let builtins: [RedactionPattern] = [
        RedactionPattern(id: "email", name: "Email addresses",
                         regex: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#),
        RedactionPattern(id: "thai_id", name: "Thai national ID",
                         regex: #"(?<!\d)\d[ -]?\d{4}[ -]?\d{5}[ -]?\d{2}[ -]?\d(?!\d)"#,
                         validate: { isValidThaiID($0) }),
        RedactionPattern(id: "phone_th", name: "Phone numbers",
                         regex: #"(?<!\d)(?:\+66[ -]?|0)\d{1,2}[ -]?\d{3}[ -]?\d{4}(?!\d)"#,
                         validate: { s in (9...11).contains(s.filter(\.isNumber).count) }),
        RedactionPattern(id: "card", name: "Payment card numbers",
                         regex: #"(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)"#,
                         validate: { s in isValidLuhn(s) }),
        RedactionPattern(id: "ip", name: "IPv4 addresses",
                         regex: #"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b"#),
        RedactionPattern(id: "secret", name: "API keys & tokens",
                         regex: #"\b(?:AKIA[0-9A-Z]{16}|(?:ghp|gho|ghu|ghs|github_pat|glpat|xox[baprs]|sk|pk)[-_][A-Za-z0-9_-]{16,}|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,})"#,
                         caseInsensitive: false),
        RedactionPattern(id: "password", name: "Password / secret assignments",
                         regex: #"\b(?:password|passwd|pwd|secret|token|api[_-]?key)\b\s*[:=]\s*\S+"#),
    ]

    /// Built-ins whose id is enabled, plus user-supplied regexes (invalid ones are skipped).
    public static func patterns(enabledIDs: Set<String>, custom: [String]) -> [RedactionPattern] {
        var result = builtins.filter { enabledIDs.contains($0.id) }
        for (i, regex) in custom.enumerated() where (try? NSRegularExpression(pattern: regex)) != nil {
            result.append(RedactionPattern(id: "custom\(i)", name: regex, regex: regex))
        }
        return result
    }

    public static func matches(in text: String, patterns: [RedactionPattern]) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        let whole = NSRange(text.startIndex..., in: text)
        for pattern in patterns {
            let options: NSRegularExpression.Options = pattern.caseInsensitive ? [.caseInsensitive] : []
            guard let regex = try? NSRegularExpression(pattern: pattern.regex, options: options) else { continue }
            for m in regex.matches(in: text, range: whole) {
                guard let range = Range(m.range, in: text), pattern.validate(String(text[range])) else { continue }
                found.append(range)
            }
        }
        return found
    }

    /// Pixel rectangles (top-left origin) of everything in `image` that matches, padded slightly.
    public static func regions(in image: CGImage, patterns: [RedactionPattern], padding: CGFloat = 3) async throws -> [CGRect] {
        let lines = try await OCR.recognizeLines(image, languages: Settings.shared.ocrLanguageList)
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        var rects: [CGRect] = []
        for line in lines {
            for range in matches(in: line.text, patterns: patterns) {
                if let r = line.pixelRect(for: range) {
                    rects.append(r.insetBy(dx: -padding, dy: -padding).intersection(bounds))
                }
            }
        }
        return rects
    }

    // MARK: Validators

    /// Thai national ID: 13 digits, the last is a mod-11 checksum of the first 12.
    public static func isValidThaiID(_ text: String) -> Bool {
        let digits = text.compactMap { $0.wholeNumberValue }
        guard digits.count == 13 else { return false }
        let sum = (0..<12).reduce(0) { $0 + digits[$1] * (13 - $1) }
        return (11 - sum % 11) % 10 == digits[12]
    }

    public static func isValidLuhn(_ text: String) -> Bool {
        let digits = text.compactMap { $0.wholeNumberValue }
        guard (13...19).contains(digits.count) else { return false }
        var sum = 0
        for (i, d) in digits.reversed().enumerated() {
            if i % 2 == 1 {
                let doubled = d * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += d
            }
        }
        return sum % 10 == 0
    }
}
