import Foundation

public enum UploadError: LocalizedError {
    case notConfigured(String)
    case server(Int, String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let what): return "\(t("Upload is not configured")): \(what)"
        case .server(let code, let body): return "\(t("Server replied")) \(code). \(body.prefix(200))"
        case .badResponse: return t("The server's reply did not contain a link.")
        }
    }
}

public struct S3Config {
    public var endpoint: String      // empty = AWS
    public var region: String
    public var bucket: String
    public var prefix: String
    public var accessKey: String
    public var secretKey: String
    public var publicBase: String    // optional CDN / public bucket base URL
    public var expirySeconds: Int

    public init(endpoint: String = "", region: String, bucket: String, prefix: String = "",
                accessKey: String, secretKey: String, publicBase: String = "", expirySeconds: Int = 3600) {
        self.endpoint = endpoint; self.region = region; self.bucket = bucket; self.prefix = prefix
        self.accessKey = accessKey; self.secretKey = secretKey; self.publicBase = publicBase
        self.expirySeconds = expirySeconds
    }

    public static func fromSettings(_ s: Settings = .shared) -> S3Config {
        let d = s.defaults
        return S3Config(
            endpoint: d.string(forKey: Settings.Key.s3Endpoint) ?? "",
            region: d.string(forKey: Settings.Key.s3Region) ?? "us-east-1",
            bucket: d.string(forKey: Settings.Key.s3Bucket) ?? "",
            prefix: d.string(forKey: Settings.Key.s3Prefix) ?? "",
            accessKey: d.string(forKey: Settings.Key.s3AccessKey) ?? "",
            secretKey: Keychain.get(account: Keychain.s3SecretAccount) ?? "",
            publicBase: d.string(forKey: Settings.Key.s3PublicBase) ?? "",
            expirySeconds: max(60, d.integer(forKey: Settings.Key.s3ExpirySeconds)))
    }

    /// Where an object lives: AWS uses virtual-hosted style, custom endpoints use path style.
    public func location(key: String) throws -> (scheme: String, host: String, path: String) {
        let trimmed = endpoint.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return ("https", "\(bucket).s3.\(region).amazonaws.com", "/\(key)") }
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)"),
              let host = url.host else { throw UploadError.notConfigured("endpoint") }
        let hostHeader = url.port.map { "\(host):\($0)" } ?? host
        return (url.scheme ?? "https", hostHeader, "/\(bucket)/\(key)")
    }
}

public enum Uploader {
    /// Unguessable key: prefix / random id / file name.
    static func objectKey(prefix: String, fileName: String) -> String {
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        let cleanPrefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let safeName = fileName.replacingOccurrences(of: " ", with: "-")
        return [cleanPrefix, String(id), safeName].filter { !$0.isEmpty }.joined(separator: "/")
    }

    public static func upload(_ data: Data, fileName: String, contentType: String, settings: Settings = .shared) async throws -> URL {
        switch settings.defaults.string(forKey: Settings.Key.uploadMode) ?? "none" {
        case "s3": return try await uploadS3(data, fileName: fileName, contentType: contentType, config: .fromSettings(settings))
        case "http": return try await uploadHTTP(data, fileName: fileName, contentType: contentType, settings: settings)
        default: throw UploadError.notConfigured(t("choose an upload method in Preferences"))
        }
    }

    public static func uploadS3(_ data: Data, fileName: String, contentType: String, config: S3Config, date: Date = Date()) async throws -> URL {
        guard !config.bucket.isEmpty, !config.accessKey.isEmpty, !config.secretKey.isEmpty else {
            throw UploadError.notConfigured("bucket / access key / secret key")
        }
        let key = objectKey(prefix: config.prefix, fileName: fileName)
        let loc = try config.location(key: key)
        let signer = SigV4(accessKey: config.accessKey, secretKey: config.secretKey, region: config.region)
        let payloadHash = SigV4.sha256Hex(data)
        let headers: [(String, String)] = [
            ("host", loc.host), ("content-type", contentType),
            ("x-amz-content-sha256", payloadHash), ("x-amz-date", SigV4.amzDate(date)),
        ]
        let authorization = signer.authorizationHeader(
            method: "PUT", path: loc.path, headers: headers, payloadHash: payloadHash, date: date)

        guard let url = URL(string: "\(loc.scheme)://\(loc.host)\(SigV4.uriEncode(loc.path, keepSlash: true))") else {
            throw UploadError.notConfigured("endpoint")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        for (name, value) in headers where name != "host" { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let (body, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UploadError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw UploadError.server(http.statusCode, String(decoding: body, as: UTF8.self))
        }

        let base = config.publicBase.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if !base.isEmpty, let link = URL(string: "\(base)/\(SigV4.uriEncode(key, keepSlash: true))") { return link }
        guard let link = signer.presignedURL(
            scheme: loc.scheme, host: loc.host, path: loc.path, expires: config.expirySeconds, date: Date())
        else { throw UploadError.badResponse }
        return link
    }

    /// POST multipart/form-data (field "file") to an internal endpoint; the reply must contain a URL.
    public static func uploadHTTP(_ data: Data, fileName: String, contentType: String, settings: Settings, token explicitToken: String? = nil) async throws -> URL {
        guard let endpoint = settings.defaults.string(forKey: Settings.Key.httpURL), let url = URL(string: endpoint),
              url.scheme != nil else { throw UploadError.notConfigured("URL") }
        let boundary = "chaediew-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = explicitToken ?? Keychain.get(account: Keychain.httpTokenAccount), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (reply, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UploadError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw UploadError.server(http.statusCode, String(decoding: reply, as: UTF8.self))
        }
        guard let link = parseLink(from: reply) else { throw UploadError.badResponse }
        return link
    }

    /// Accepts `{"url": …}`, `{"link": …}`, `{"data": {"url": …}}` or a bare URL.
    public static func parseLink(from data: Data) -> URL? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let candidates: [Any?] = [json["url"], json["link"], (json["data"] as? [String: Any])?["url"]]
            for case let s as String in candidates { if let u = URL(string: s), u.scheme != nil { return u } }
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("http") ? URL(string: text) : nil
    }
}
