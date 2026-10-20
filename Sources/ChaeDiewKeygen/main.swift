import ChaeDiewLicense
import CryptoKit
import Foundation

// Tenix-ChaeDiew license key generator and activation desk.
//   chaediew-keygen init      [--key-file PATH] [--emit-swift PATH] [--emit-js PATH] [--force]
//   chaediew-keygen issue     --name "ACME Co" [--count 50] [--days 365 | --perpetual] [--seats 1] [--csv PATH]
//   chaediew-keygen activate  KEY --machine MC-XXXX-XXXX-XXXX-XXXX [--note "who"]
//   chaediew-keygen release   KEY [--machine MC-…]        (frees a seat so the key can move to another computer)
//   chaediew-keygen ledger    [--csv PATH]
//   chaediew-keygen inspect   KEY
//   chaediew-keygen machine-code --raw "<os machine id>"  (what the app would show for that id; used to cross-check ports)
// One key = one computer: the app only switches on with an activation code signed for that key *and* that machine.
// The ledger remembers which machines each key was activated on and refuses more than `seats`.
// The private key never goes into the app or the repository. Keep it (and a backup) somewhere only you can read.

let args = Array(CommandLine.arguments.dropFirst())

func value(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), args.count > i + 1 else { return nil }
    return args[i + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func note(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }

let supportFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Tenix-ChaeDiew-Keygen")
let defaultKeyFile = supportFolder.appendingPathComponent("private.key").path
let keyFile = value("--key-file") ?? defaultKeyFile
let ledgerFile = supportFolder.appendingPathComponent("ledger.json")

func loadPrivateKey() -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOfFile: keyFile, encoding: .utf8),
          let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
    else { fail("No private key at \(keyFile). Run `chaediew-keygen init` first.") }
    return key
}

// MARK: Ledger

struct Machine: Codable { var code: String; var activatedOn: String; var note: String }
struct Entry: Codable { var licensee: String; var seats: Int; var expires: String; var issued: String; var machines: [Machine] }

func loadLedger() -> [String: Entry] {
    guard let data = try? Data(contentsOf: ledgerFile), let ledger = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
    return ledger
}

func saveLedger(_ ledger: [String: Entry]) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        try FileManager.default.createDirectory(at: supportFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try encoder.encode(ledger).write(to: ledgerFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ledgerFile.path)
    } catch { fail("Could not write the ledger \(ledgerFile.path): \(error)") }
}

func csvField(_ s: String) -> String { s.contains(",") || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }

func parseMachine() -> (code: String, bytes: Data) {
    guard let text = value("--machine"), let bytes = MachineBinding.parseMachineCode(text) else {
        fail("--machine MC-XXXX-XXXX-XXXX-XXXX is required (the code the app shows on its License screen).")
    }
    return (MachineBinding.machineCode(bytes: bytes), bytes)
}

switch args.first {
case "init":
    if FileManager.default.fileExists(atPath: keyFile), !args.contains("--force") {
        fail("A private key already exists at \(keyFile). Keys already issued would stop working if you replaced it. Use --force only if you mean it.")
    }
    let key = Curve25519.Signing.PrivateKey()
    let folder = URL(fileURLWithPath: keyFile).deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    do {
        try key.rawRepresentation.base64EncodedString().write(toFile: keyFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile)
    } catch { fail("Could not write \(keyFile): \(error)") }
    let publicBase64 = key.publicKey.rawRepresentation.base64EncodedString()
    print("Private key written to \(keyFile) (permissions 600). Back it up and never share it.")
    print("Public key (safe to ship): \(publicBase64)")
    if let path = value("--emit-swift") {
        let source = """
        import Foundation

        /// The public half of the license signing key (made by `chaediew-keygen init`). Safe to ship: it can check keys, not make them.
        enum LicensePublicKey {
            static let base64 = "\(publicBase64)"
        }

        """
        do { try source.write(toFile: path, atomically: true, encoding: .utf8); print("Wrote \(path)") } catch { fail("Could not write \(path): \(error)") }
    }
    if let path = value("--emit-js") {
        let source = "// Generated by `chaediew-keygen init --emit-js`. The public half of the license signing key; safe to ship.\nmodule.exports = '\(publicBase64)';\n"
        do { try source.write(toFile: path, atomically: true, encoding: .utf8); print("Wrote \(path)") } catch { fail("Could not write \(path): \(error)") }
    }

case "issue":
    guard let name = value("--name"), !name.isEmpty else { fail("--name is required, e.g. --name \"ACME Co\"") }
    let seats = max(1, value("--seats").flatMap(Int.init) ?? 1)
    let count = max(1, min(1000, value("--count").flatMap(Int.init) ?? 1))
    var expires: Date?
    if args.contains("--perpetual") { expires = nil }
    else {
        let days = value("--days").flatMap(Int.init) ?? 365
        expires = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: Date())
    }
    let privateKey = loadPrivateKey()
    var ledger = loadLedger()
    var rows = ["no,key_id,licensee,seats,expires,license_key,machine_code,activation_code,assigned_to"]
    for n in 1...count {
        let licensee = count > 1 ? "\(name) #\(String(format: "%02d", n))" : name
        do {
            let key = try LicenseKey.issue(licensee: licensee, seats: seats, expires: expires, privateKey: privateKey)
            let info = try LicenseKey.verify(key, publicKey: privateKey.publicKey)
            ledger[info.keyID] = Entry(licensee: info.licensee, seats: seats, expires: expires.map { LicenseKey.isoDay($0) } ?? "never",
                                       issued: LicenseKey.isoDay(Date()), machines: [])
            rows.append([String(n), info.keyID, info.licensee, String(seats), expires.map { LicenseKey.isoDay($0) } ?? "never", key, "", "", ""].map(csvField).joined(separator: ","))
            print(key)
            note("[\(n)/\(count)] \(info.licensee) · key id \(info.keyID) · seats \(seats) · expires \(expires.map { LicenseKey.isoDay($0) } ?? "never") · \(key.count) characters")
        } catch { fail("Could not issue a key: \(error)") }
    }
    saveLedger(ledger)
    if let path = value("--csv") {
        do {
            try (rows.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            note("Wrote \(path) (keep it private: anyone with a key and an activation desk can use it)")
        } catch { fail("Could not write \(path): \(error)") }
    }

case "activate":
    guard args.count > 1 else { fail("Usage: chaediew-keygen activate KEY --machine MC-XXXX-XXXX-XXXX-XXXX [--note \"who\"]") }
    let privateKey = loadPrivateKey()
    let machine = parseMachine()
    do {
        let info = try LicenseKey.verify(args[1], publicKey: privateKey.publicKey)
        var ledger = loadLedger()
        var entry = ledger[info.keyID] ?? Entry(licensee: info.licensee, seats: info.seats, expires: info.expires.map { LicenseKey.isoDay($0) } ?? "never",
                                               issued: LicenseKey.isoDay(info.issued), machines: [])
        if !entry.machines.contains(where: { $0.code == machine.code }) {
            guard entry.machines.count < entry.seats else {
                fail("Key \(info.keyID) (\(info.licensee)) is already activated on \(entry.machines.count) of \(entry.seats) computer(s): \(entry.machines.map(\.code).joined(separator: ", ")).\nIf it is moving to a new computer, run `release` first. (The old computer keeps working offline: an activation code cannot be taken back.)")
            }
            entry.machines.append(Machine(code: machine.code, activatedOn: LicenseKey.isoDay(Date()), note: value("--note") ?? ""))
            ledger[info.keyID] = entry
            saveLedger(ledger)
        }
        let code = try MachineBinding.issueActivation(keyID: info.keyID, machine: machine.bytes, privateKey: privateKey)
        print(code)
        note("Activation for \(info.licensee) (key id \(info.keyID)) on \(machine.code) · \(entry.machines.count)/\(entry.seats) computer(s) · \(code.count) characters")
    } catch let error as LicenseError { fail("Not valid: \(error.localizedDescription)") }
    catch { fail("Could not issue an activation code: \(error)") }

case "release":
    guard args.count > 1 else { fail("Usage: chaediew-keygen release KEY [--machine MC-…]") }
    do {
        let info = try LicenseKey.verify(args[1], publicKey: loadPrivateKey().publicKey)
        var ledger = loadLedger()
        guard var entry = ledger[info.keyID] else { fail("Key \(info.keyID) is not in the ledger.") }
        if value("--machine") != nil {
            let machine = parseMachine()
            entry.machines.removeAll { $0.code == machine.code }
        } else { entry.machines.removeAll() }
        ledger[info.keyID] = entry
        saveLedger(ledger)
        print("Key \(info.keyID) is now on \(entry.machines.count) of \(entry.seats) computer(s).")
    } catch { fail("Not valid: \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }

case "ledger":
    let ledger = loadLedger()
    var rows = ["key_id,licensee,seats,expires,issued,activated,machines"]
    for (id, e) in ledger.sorted(by: { $0.value.licensee < $1.value.licensee }) {
        rows.append([id, e.licensee, String(e.seats), e.expires, e.issued, "\(e.machines.count)/\(e.seats)",
                     e.machines.map { "\($0.code) (\($0.activatedOn)\($0.note.isEmpty ? "" : " " + $0.note))" }.joined(separator: " | ")].map(csvField).joined(separator: ","))
    }
    if let path = value("--csv") {
        do { try (rows.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8); note("Wrote \(path)") } catch { fail("Could not write \(path): \(error)") }
    } else {
        print("\(ledger.count) key(s) · \(ledger.values.filter { !$0.machines.isEmpty }.count) activated · \(ledger.values.filter { $0.machines.isEmpty }.count) unused")
        for (id, e) in ledger.sorted(by: { $0.value.licensee < $1.value.licensee }) {
            print("\(id)  \(e.licensee.padding(toLength: 24, withPad: " ", startingAt: 0))  \(e.machines.count)/\(e.seats)  \(e.machines.map(\.code).joined(separator: ", "))")
        }
    }

case "inspect":
    guard args.count > 1 else { fail("Usage: chaediew-keygen inspect KEY") }
    do {
        let info = try LicenseKey.verify(args[1], publicKey: loadPrivateKey().publicKey)
        let used = loadLedger()[info.keyID]?.machines.count ?? 0
        print("Valid. Licensee: \(info.licensee) · seats: \(info.seats) · issued: \(LicenseKey.isoDay(info.issued)) · expires: \(info.expires.map { LicenseKey.isoDay($0) } ?? "never") · id: \(info.keyID) · activated on \(used) computer(s)")
    } catch { fail("Not valid: \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }

case "machine-code":
    guard let raw = value("--raw") else { fail("Usage: chaediew-keygen machine-code --raw \"<machine id>\"") }
    print(MachineBinding.machineCode(rawID: raw))

default:
    print("""
    chaediew-keygen init      [--key-file PATH] [--emit-swift PATH] [--emit-js PATH] [--force]
    chaediew-keygen issue     --name "ACME Co" [--count 50] [--days 365 | --perpetual] [--seats 1] [--csv PATH]
    chaediew-keygen activate  KEY --machine MC-XXXX-XXXX-XXXX-XXXX [--note "who"]
    chaediew-keygen release   KEY [--machine MC-…]
    chaediew-keygen ledger    [--csv PATH]
    chaediew-keygen inspect   KEY
    chaediew-keygen machine-code --raw "<os machine id>"
    """)
}
