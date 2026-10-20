import CryptoKit
import Foundation

/// AWS Signature Version 4, enough for S3 PUT uploads and presigned GET links.
/// Works with any S3-compatible store (MinIO, Ceph, Cloudflare R2, …).
public struct SigV4 {
    public var accessKey: String
    public var secretKey: String
    public var region: String
    public var service: String

    public init(accessKey: String, secretKey: String, region: String, service: String = "s3") {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.region = region
        self.service = service
    }

    public static func amzDate(_ date: Date) -> String { format(date, "yyyyMMdd'T'HHmmss'Z'") }
    public static func dateStamp(_ date: Date) -> String { format(date, "yyyyMMdd") }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = pattern
        return f.string(from: date)
    }

    /// RFC 3986 percent-encoding as SigV4 requires; `/` is kept only inside paths.
    public static func uriEncode(_ s: String, keepSlash: Bool = false) -> String {
        var allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        if keepSlash { allowed.insert("/") }
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func hmac(_ key: SymmetricKey, _ message: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key))
    }

    private func signingKey(dateStamp: String) -> SymmetricKey {
        let k0 = SymmetricKey(data: Data("AWS4\(secretKey)".utf8))
        let k1 = SymmetricKey(data: hmac(k0, dateStamp))
        let k2 = SymmetricKey(data: hmac(k1, region))
        let k3 = SymmetricKey(data: hmac(k2, service))
        return SymmetricKey(data: hmac(k3, "aws4_request"))
    }

    public func scope(_ date: Date) -> String {
        "\(Self.dateStamp(date))/\(region)/\(service)/aws4_request"
    }

    private func canonicalQuery(_ items: [(String, String)]) -> String {
        var encoded: [(name: String, value: String)] = []
        for item in items { encoded.append((Self.uriEncode(item.0), Self.uriEncode(item.1))) }
        encoded.sort { a, b in a.name == b.name ? a.value < b.value : a.name < b.name }
        var parts: [String] = []
        for pair in encoded { parts.append(pair.name + "=" + pair.value) }
        return parts.joined(separator: "&")
    }

    /// Signs a request; returns the hex signature plus the signed-headers list.
    /// `path` is the unencoded absolute path (e.g. "/bucket/my file.png").
    public func sign(
        method: String, path: String, query: [(String, String)], headers: [(String, String)],
        payloadHash: String, date: Date
    ) -> (signature: String, signedHeaders: String) {
        let normalized = headers.map { ($0.0.lowercased(), $0.1.trimmingCharacters(in: .whitespaces)) }
            .sorted { $0.0 < $1.0 }
        let canonicalHeaders = normalized.map { "\($0.0):\($0.1)\n" }.joined()
        let signedHeaders = normalized.map(\.0).joined(separator: ";")
        let canonicalRequest = [
            method, Self.uriEncode(path, keepSlash: true), canonicalQuery(query),
            canonicalHeaders, signedHeaders, payloadHash,
        ].joined(separator: "\n")
        let stringToSign = [
            "AWS4-HMAC-SHA256", Self.amzDate(date), scope(date),
            Self.sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")
        let signature = hmac(signingKey(dateStamp: Self.dateStamp(date)), stringToSign)
            .map { String(format: "%02x", $0) }.joined()
        return (signature, signedHeaders)
    }

    /// `Authorization` header value for a header-signed request.
    public func authorizationHeader(
        method: String, path: String, query: [(String, String)] = [], headers: [(String, String)],
        payloadHash: String, date: Date
    ) -> String {
        let (signature, signedHeaders) = sign(
            method: method, path: path, query: query, headers: headers, payloadHash: payloadHash, date: date)
        return "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(scope(date)), SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    /// A time-limited GET (or other method) URL that needs no credentials.
    public func presignedURL(
        method: String = "GET", scheme: String = "https", host: String, path: String,
        expires: Int, date: Date
    ) -> URL? {
        let query: [(String, String)] = [
            ("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
            ("X-Amz-Credential", "\(accessKey)/\(scope(date))"),
            ("X-Amz-Date", Self.amzDate(date)),
            ("X-Amz-Expires", String(expires)),
            ("X-Amz-SignedHeaders", "host"),
        ]
        let (signature, _) = sign(
            method: method, path: path, query: query, headers: [("host", host)],
            payloadHash: "UNSIGNED-PAYLOAD", date: date)
        let full = canonicalQuery(query) + "&X-Amz-Signature=\(signature)"
        return URL(string: "\(scheme)://\(host)\(Self.uriEncode(path, keepSlash: true))?\(full)")
    }
}
