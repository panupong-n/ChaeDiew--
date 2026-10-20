import CryptoKit
import Foundation

/// Ties a license key to one computer.
///
/// A key (`TXCD1-…`) on its own does nothing. The computer shows a short **machine code** (`MC-XXXX-XXXX-XXXX-XXXX`, a hash of the
/// operating system's own machine identifier). The issuer signs `key id ‖ machine code` with the same Ed25519 private key and sends back
/// an **activation code** (`TXAC1-…`). The app accepts the key only when an activation code for *this* key and *this* machine verifies,
/// so a key (or an activation code) copied to another computer is useless. It is the same on macOS and Windows: the machine code is
/// derived the same way from each platform's identifier, and the Electron build uses a port of this file (`electron/src/license.js`).
public enum MachineBinding {
    public static let activationPrefix = "TXAC1"
    private static let machineDomain = Data("Tenix-ChaeDiew machine v1\n".utf8)
    private static let activationDomain = Data("Tenix-ChaeDiew activation v1".utf8)

    /// 10-byte fingerprint of `rawID` (macOS IOPlatformUUID, Windows MachineGuid, Linux /etc/machine-id).
    public static func machineBytes(rawID: String) -> Data {
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return Data(SHA256.hash(data: machineDomain + Data(id.utf8)).prefix(10))
    }

    /// `MC-XXXX-XXXX-XXXX-XXXX` (16 Base32 characters).
    public static func machineCode(rawID: String) -> String { machineCode(bytes: machineBytes(rawID: rawID)) }

    public static func machineCode(bytes: Data) -> String {
        let text = Base32.encode(bytes)
        let groups = stride(from: 0, to: text.count, by: 4).map { i -> String in
            let start = text.index(text.startIndex, offsetBy: i)
            return String(text[start..<text.index(start, offsetBy: min(4, text.count - i))])
        }
        return (["MC"] + groups).joined(separator: "-")
    }

    /// Reads what a person typed or pasted back into the 10 bytes; nil if it is not a machine code.
    public static func parseMachineCode(_ text: String) -> Data? {
        var s = LicenseKey.normalise(text)
        if s.count == 18, s.hasPrefix("MC") { s.removeFirst(2) }
        guard s.count == 16, let bytes = Base32.decode(s), bytes.count == 10 else { return nil }
        return Data(bytes)
    }

    // MARK: Issuing (needs the private key; ChaeDiewKeygen only)

    public static func issueActivation(keyID: String, machine: Data, privateKey: Curve25519.Signing.PrivateKey) throws -> String {
        guard let id = hex(keyID), id.count == 6, machine.count == 10 else { throw LicenseError.malformed }
        let signature = try privateKey.signature(for: activationDomain + id + machine)
        let text = Base32.encode(signature)
        let groups = stride(from: 0, to: text.count, by: 8).map { i -> String in
            let start = text.index(text.startIndex, offsetBy: i)
            return String(text[start..<text.index(start, offsetBy: min(8, text.count - i))])
        }
        return ([activationPrefix] + groups).joined(separator: "-")
    }

    // MARK: Checking (what the app does)

    public static func looksLikeActivation(_ text: String) -> Bool {
        LicenseKey.normalise(text).hasPrefix(LicenseKey.normalise(activationPrefix))
    }

    /// True when `code` is a genuine activation of the key `keyID` for the computer `machine`.
    public static func verifyActivation(_ code: String, keyID: String, machine: Data, publicKey: Curve25519.Signing.PublicKey) -> Bool {
        var text = LicenseKey.normalise(code)
        let marker = LicenseKey.normalise(activationPrefix)
        guard text.hasPrefix(marker) else { return false }
        text.removeFirst(marker.count)
        guard let id = hex(keyID), id.count == 6, machine.count == 10, let sig = Base32.decode(text), sig.count == 64 else { return false }
        return publicKey.isValidSignature(Data(sig), for: activationDomain + id + machine)
    }

    private static func hex(_ text: String) -> Data? {
        guard text.count % 2 == 0 else { return nil }
        var out = Data()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }
}
