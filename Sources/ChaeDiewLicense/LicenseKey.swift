import CryptoKit
import Foundation

/// What a license key says about its holder.
public struct LicenseInfo: Equatable {
    public let licensee: String
    public let seats: Int
    public let issued: Date
    /// nil = perpetual.
    public let expires: Date?
    /// Short identifier of this particular key (shown in support requests, never secret).
    public let keyID: String
}

public enum LicenseError: Error, Equatable, LocalizedError {
    case malformed, unsupportedVersion, badSignature
    case expired(Date)
    /// An activation code was entered but no license key has been entered yet.
    case activationNeedsKey
    /// The activation code is not for this key on this computer.
    case wrongActivation

    public var errorDescription: String? {
        switch self {
        case .activationNeedsKey: return "Enter the license key first, then the activation code."
        case .wrongActivation: return "This activation code is not for this key on this computer."
        case .malformed: return "This is not a Tenix-ChaeDiew license key (check for missing or extra characters)."
        case .unsupportedVersion: return "This key was made for a newer version of Tenix-ChaeDiew."
        case .badSignature: return "The key is not genuine (its signature does not match)."
        case .expired(let date): return "This key expired on \(LicenseKey.isoDay(date))."
        }
    }
}

/// License keys are signed with Ed25519, so the app only holds a public key: it can check a key but cannot make one.
///
/// Layout of the signed payload (big-endian): version(1) · edition(1) · seats(2) · issued day(2) · expiry day(2, 0 = never) ·
/// name length(1) · name(UTF-8, ≤ 32 bytes) · key id(6 random bytes). The key text is `TXCD1-` plus the Base32 of
/// payload ‖ 64-byte signature, in groups of 8. The 64-byte signature is what makes it about 150–190 characters: that is the
/// price of a key nobody can forge without the issuer's private key.
public enum LicenseKey {
    public static let prefix = "TXCD1"
    private static let domain = Data("Tenix-ChaeDiew license v1".utf8)
    /// Day 0 for the two date fields.
    private static let epoch = Date(timeIntervalSince1970: 1_704_067_200)  // 2024-01-01 00:00 UTC
    public static let maxNameBytes = 32

    /// yyyy-MM-dd in the Gregorian calendar, whatever the system calendar is (a Buddhist-calendar Mac would otherwise print 2569).
    public static func isoDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func day(_ date: Date) -> UInt16 {
        UInt16(max(0, min(65_535, Int((date.timeIntervalSince(epoch) / 86_400).rounded(.down)))))
    }

    private static func date(_ day: UInt16) -> Date { epoch.addingTimeInterval(Double(day) * 86_400) }

    // MARK: Issuing (needs the private key; used by the ChaeDiewKeygen tool only)

    public static func issue(
        licensee: String, seats: Int = 1, expires: Date? = nil, now: Date = Date(), edition: UInt8 = 1,
        privateKey: Curve25519.Signing.PrivateKey
    ) throws -> String {
        var name = Data(licensee.utf8)
        if name.count > maxNameBytes {
            // Cut on a character boundary.
            var s = licensee
            while Data(s.utf8).count > maxNameBytes { s.removeLast() }
            name = Data(s.utf8)
        }
        var payload = Data([1, edition])
        payload.append(contentsOf: [UInt8(seats >> 8 & 0xFF), UInt8(seats & 0xFF)])
        let issued = day(now), exp = expires.map(day) ?? 0
        payload.append(contentsOf: [UInt8(issued >> 8), UInt8(issued & 0xFF), UInt8(exp >> 8), UInt8(exp & 0xFF)])
        payload.append(UInt8(name.count))
        payload.append(name)
        payload.append(Data((0..<6).map { _ in UInt8.random(in: 0...255) }))
        let signature = try privateKey.signature(for: domain + payload)
        return format(Base32.encode(payload + signature))
    }

    private static func format(_ base32: String) -> String {
        var groups: [String] = []
        var rest = Substring(base32)
        while !rest.isEmpty { groups.append(String(rest.prefix(8))); rest = rest.dropFirst(8) }
        return ([prefix] + groups).joined(separator: "-")
    }

    // MARK: Checking (what the app does)

    /// Removes spaces, line breaks and dashes, upper-cases, and fixes the look-alikes 0→O, 1→I, 8→B.
    public static func normalise(_ text: String) -> String {
        String(text.uppercased().filter { !$0.isWhitespace && $0 != "-" }.map { c -> Character in
            switch c { case "0": return "O"; case "1": return "I"; case "8": return "B"; default: return c }
        })
    }

    public static func verify(_ key: String, publicKey: Curve25519.Signing.PublicKey, now: Date = Date()) throws -> LicenseInfo {
        var text = normalise(key)
        // normalise() also turns the "1" of "TXCD1" into "I", so compare against the prefix in that same form.
        let marker = normalise(prefix)
        guard text.hasPrefix(marker) else { throw LicenseError.malformed }
        text.removeFirst(marker.count)
        guard let bytes = Base32.decode(text), bytes.count > 9 + 6 + 64 else { throw LicenseError.malformed }
        let payload = Data(bytes.dropLast(64)), signature = Data(bytes.suffix(64))
        guard payload.count >= 9 else { throw LicenseError.malformed }
        guard payload[0] == 1 else { throw LicenseError.unsupportedVersion }
        let nameLength = Int(payload[8])
        guard payload.count == 9 + nameLength + 6 else { throw LicenseError.malformed }
        guard publicKey.isValidSignature(signature, for: domain + payload) else { throw LicenseError.badSignature }

        let seats = Int(payload[2]) << 8 | Int(payload[3])
        let issued = UInt16(payload[4]) << 8 | UInt16(payload[5])
        let exp = UInt16(payload[6]) << 8 | UInt16(payload[7])
        let name = String(data: payload.subdata(in: 9..<(9 + nameLength)), encoding: .utf8) ?? ""
        let id = payload.suffix(6).map { String(format: "%02X", $0) }.joined()
        let expires = exp == 0 ? nil : date(exp)
        if let expires, now > expires.addingTimeInterval(86_400) { throw LicenseError.expired(expires) }
        return LicenseInfo(licensee: name, seats: seats, issued: date(issued), expires: expires, keyID: id)
    }
}

enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func encode(_ data: Data) -> String {
        var out = ""
        var buffer = 0, bits = 0
        for byte in data {
            buffer = buffer << 8 | Int(byte)
            bits += 8
            while bits >= 5 { out.append(alphabet[(buffer >> (bits - 5)) & 31]); bits -= 5 }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 { out.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return out
    }

    static func decode(_ text: String) -> [UInt8]? {
        var out: [UInt8] = []
        var buffer = 0, bits = 0
        for c in text {
            guard let v = alphabet.firstIndex(of: c) else { return nil }
            buffer = buffer << 5 | v
            bits += 5
            if bits >= 8 { out.append(UInt8((buffer >> (bits - 8)) & 0xFF)); bits -= 8 }
            buffer &= (1 << bits) - 1
        }
        return out
    }
}
