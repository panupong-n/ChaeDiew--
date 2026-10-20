import AppKit
import ChaeDiewLicense
import CryptoKit
import SwiftUI

/// Where license data is kept (the login keychain in the app, memory in the self-checks).
public protocol SecretStore {
    func get(_ account: String) -> String?
    func set(_ value: String, account: String)
}

struct KeychainSecrets: SecretStore {
    func get(_ account: String) -> String? { Keychain.get(account: account) }
    func set(_ value: String, account: String) { Keychain.set(value, account: account) }
}

/// Reads each Keychain item once per launch (the license screen asks several times per refresh, and every read can raise the system
/// "wants to use your confidential information" prompt). Writes go straight through and update the cache.
final class CachedSecrets: SecretStore {
    private let inner: SecretStore
    private var cache: [String: String?] = [:]
    init(_ inner: SecretStore) { self.inner = inner }
    func get(_ account: String) -> String? {
        if let hit = cache[account] { return hit }
        let value = inner.get(account)
        cache[account] = .some(value)
        return value
    }
    func set(_ value: String, account: String) {
        inner.set(value, account: account)
        cache[account] = .some(value.isEmpty ? nil : value)
    }
}

public final class MemorySecrets: SecretStore {
    private var values: [String: String] = [:]
    public init() {}
    public func get(_ account: String) -> String? { values[account] }
    public func set(_ value: String, account: String) { values[account] = value.isEmpty ? nil : value }
}

/// License state: a 14-day trial from first launch, then a signed key (see ChaeDiewLicense) is required to copy, save,
/// upload, pin, print or export. Capturing, viewing, editing and OCR stay free. Checking is local: no network, no account.
public final class LicenseManager {
    public static let shared = LicenseManager(secrets: CachedSecrets(KeychainSecrets()), now: { Date() })
    public static let trialDays = 14
    static let keyAccount = "license-key"
    static let trialAccount = "trial-start"
    static let activationAccount = "activation-code"

    public enum Status: Equatable {
        case licensed(LicenseInfo)
        case trial(daysLeft: Int)
        case trialEnded
        /// A genuine key is stored but has no activation code for this computer yet (one key = one computer).
        /// `trialDaysLeft` is what remains of the free trial (0 = over, so use is blocked until activated).
        case needsActivation(LicenseInfo, trialDaysLeft: Int)
        /// A key was entered but is no longer usable (expired). `LicenseError` text explains why.
        case keyProblem(String)

        public var allowsUse: Bool {
            switch self {
            case .licensed, .trial: return true
            case .needsActivation(_, let left): return left > 0
            case .trialEnded, .keyProblem: return false
            }
        }
    }

    private let secrets: SecretStore
    private let now: () -> Date
    private let publicKey: Curve25519.Signing.PublicKey
    private let machineRaw: () -> String
    /// false (the shipped default): a key with a genuine signature that has not expired is "Licensed" at once, nothing else to enter.
    /// true: one key = one computer — the key also needs an activation code (`TXAC1-…`) made for this computer (see MachineBinding).
    private let requireActivation: Bool

    public init(secrets: SecretStore, now: @escaping () -> Date, publicKey: Curve25519.Signing.PublicKey? = nil,
                machineID: (() -> String)? = nil, requireActivation: Bool = false) {
        self.secrets = secrets
        self.now = now
        self.requireActivation = requireActivation
        self.machineRaw = machineID ?? { MachineID.raw }
        if let publicKey { self.publicKey = publicKey } else {
            // The app ships with its own public key; a missing/garbled one would be a build error, so fail loudly.
            let data = Data(base64Encoded: LicensePublicKey.base64) ?? Data()
            self.publicKey = (try? Curve25519.Signing.PublicKey(rawRepresentation: data)) ?? { fatalError("Bad embedded license public key") }()
        }
    }

    public var storedKey: String? { secrets.get(Self.keyAccount) }
    public var storedActivation: String? { secrets.get(Self.activationAccount) }

    /// What the person sends to the issuer to get an activation code.
    public var machineCode: String { MachineBinding.machineCode(rawID: machineRaw()) }

    /// First time this is called is the start of the trial.
    private var trialStart: Date {
        let formatter = ISO8601DateFormatter()
        if let text = secrets.get(Self.trialAccount), let date = formatter.date(from: text) { return date }
        let start = now()
        secrets.set(formatter.string(from: start), account: Self.trialAccount)
        return start
    }

    public var status: Status {
        if let key = storedKey {
            do {
                let info = try LicenseKey.verify(key, publicKey: publicKey, now: now())
                if !requireActivation { return .licensed(info) }
                if let code = storedActivation,
                   MachineBinding.verifyActivation(code, keyID: info.keyID, machine: MachineBinding.machineBytes(rawID: machineRaw()), publicKey: publicKey) {
                    return .licensed(info)
                }
                let left: Int
                switch trialStatus { case .trial(let d): left = d; default: left = 0 }
                return .needsActivation(info, trialDaysLeft: left)
            } catch { /* fall through to the trial if the stored key is no longer valid */
                let trial = trialStatus
                if trial.allowsUse { return trial }
                return .keyProblem((error as? LocalizedError)?.errorDescription ?? "The stored key is not valid.")
            }
        }
        return trialStatus
    }

    private var trialStatus: Status {
        let elapsed = Int(now().timeIntervalSince(trialStart) / 86_400)
        let left = Self.trialDays - elapsed
        return left > 0 ? .trial(daysLeft: left) : .trialEnded
    }

    /// Takes either a license key (`TXCD1-…`) or the activation code (`TXAC1-…`) the issuer sent back for this computer.
    /// A key alone is stored but only switches the app on once its activation code has been entered too.
    @discardableResult
    public func activate(_ text: String) throws -> LicenseInfo {
        if MachineBinding.looksLikeActivation(text) {
            guard let key = storedKey else { throw LicenseError.activationNeedsKey }
            let info = try LicenseKey.verify(key, publicKey: publicKey, now: now())
            guard MachineBinding.verifyActivation(text, keyID: info.keyID, machine: MachineBinding.machineBytes(rawID: machineRaw()), publicKey: publicKey) else {
                throw LicenseError.wrongActivation
            }
            secrets.set(LicenseKey.normalise(text), account: Self.activationAccount)
            return info
        }
        let info = try LicenseKey.verify(text, publicKey: publicKey, now: now())
        let normalised = LicenseKey.normalise(text)
        if normalised != storedKey { secrets.set("", account: Self.activationAccount) }   // a different key needs its own activation
        secrets.set(normalised, account: Self.keyAccount)
        return info
    }

    public func remove() {
        secrets.set("", account: Self.keyAccount)
        secrets.set("", account: Self.activationAccount)
    }

    public var allowsUse: Bool { status.allowsUse }
}

extension LicenseManager {
    /// Gate for the actions that need a license once the trial is over. Shows the license window and returns false if not allowed.
    @MainActor
    public func require(_ action: String = "") -> Bool {
        if allowsUse { return true }
        LicenseWindowController.shared.show(reason: action.isEmpty ? nil : action)
        return false
    }
}

// MARK: - License screen

private struct LicenseView: View {
    var reason: String?
    var embedded = false
    @StateObject private var input = Box("")
    @StateObject private var message = Box("")
    @StateObject private var failed = Box(false)
    @StateObject private var tick = Box(0)   // bumped to refresh the status after (de)activating

    private var status: LicenseManager.Status { _ = tick.value; return LicenseManager.shared.status }

    private static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        let thai = Settings.shared.language == .th
        f.locale = Locale(identifier: thai ? "th_TH" : "en_US")
        f.calendar = thai ? Calendar(identifier: .buddhist) : Calendar(identifier: .gregorian)
        f.dateStyle = .medium
        return f.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let w = Brand.wordmarkOnDark {
                Image(nsImage: w).resizable().scaledToFit().frame(height: 46).accessibilityLabel("Tenix-ChaeDiew")
            }
            if let reason {
                Text(reason).font(.callout).foregroundStyle(Color(nsColor: Brand.caution))
            }
            statusBlock
            Divider().overlay(Color(nsColor: Brand.line))
            if case .licensed = status {
                HStack {
                    Spacer()
                    Button(t("Remove license")) { LicenseManager.shared.remove(); message.value = ""; input.value = ""; tick.value += 1 }
                        .buttonStyle(BrandButton())
                }
            } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("License key")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(nsColor: Brand.textMuted))
                TextEditor(text: $input.value)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 74)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: Brand.inkRaised)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: failed.value ? Brand.caution : Brand.line), lineWidth: 1))
                if !message.value.isEmpty {
                    Text(message.value).font(.caption).foregroundStyle(Color(nsColor: failed.value ? Brand.caution : Brand.positive))
                }
                HStack(spacing: 10) {
                    Button(t("Activate")) { activate() }
                        .buttonStyle(BrandButton(primary: true))
                        .disabled(input.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(t("Paste")) {
                        if let s = NSPasteboard.general.string(forType: .string) { input.value = s }
                    }.buttonStyle(BrandButton())
                    Spacer()
                    if LicenseManager.shared.storedKey != nil {
                        Button(t("Remove license")) { LicenseManager.shared.remove(); message.value = ""; input.value = ""; tick.value += 1 }
                            .buttonStyle(BrandButton())
                    }
                }
            }
            }
            Spacer(minLength: 0)
            Text("Powered by Panupong Nijjaboon").font(.caption).foregroundStyle(Color(nsColor: Brand.textFaint))
        }
        .padding(embedded ? 20 : 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: Brand.ink))
        .foregroundStyle(Color(nsColor: Brand.text))
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var statusBlock: some View {
        switch status {
        case .licensed(let info):
            VStack(alignment: .leading, spacing: 10) {
                Label(t("Licensed"), systemImage: "checkmark.seal.fill").foregroundStyle(Color(nsColor: Brand.positive)).font(.system(size: 15, weight: .semibold))
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow { Text(t("Licensed to")).foregroundStyle(Color(nsColor: Brand.textMuted)); Text(info.licensee) }
                    GridRow { Text(t("Expires")).foregroundStyle(Color(nsColor: Brand.textMuted)); Text(info.expires.map(Self.dateText) ?? t("Never")) }
                    GridRow { Text(t("Key ID")).foregroundStyle(Color(nsColor: Brand.textMuted)); Text(info.keyID).font(.system(size: 12, design: .monospaced)) }
                }.font(.system(size: 13))
            }
        case .needsActivation(let info, let left):
            VStack(alignment: .leading, spacing: 10) {
                Label(t("Activation needed"), systemImage: "key.fill").foregroundStyle(Color(nsColor: Brand.accent)).font(.system(size: 15, weight: .semibold))
                Text(t("One key works on one computer. Send the key ID and this computer's machine code to the issuer, then paste the activation code you get back below."))
                    .font(.callout).foregroundStyle(Color(nsColor: Brand.textMuted)).fixedSize(horizontal: false, vertical: true)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow { Text(t("Licensed to")).foregroundStyle(Color(nsColor: Brand.textMuted)); Text(info.licensee) }
                    GridRow { Text(t("Key ID")).foregroundStyle(Color(nsColor: Brand.textMuted)); Text(info.keyID).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }
                    GridRow {
                        Text(t("Machine code")).foregroundStyle(Color(nsColor: Brand.textMuted))
                        HStack(spacing: 8) {
                            Text(LicenseManager.shared.machineCode).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            Button(t("Copy")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("Key ID: \(info.keyID)\nMachine code: \(LicenseManager.shared.machineCode)", forType: .string)
                            }.buttonStyle(BrandButton())
                        }
                    }
                }.font(.system(size: 13))
                if left > 0 { Text(String(format: t("Free trial — %d days left"), left)).font(.caption).foregroundStyle(Color(nsColor: Brand.textFaint)) }
            }
        case .trial(let days):
            Label(String(format: t("Free trial — %d days left"), days), systemImage: "clock").foregroundStyle(Color(nsColor: Brand.accent)).font(.system(size: 15, weight: .semibold))
        case .trialEnded:
            VStack(alignment: .leading, spacing: 4) {
                Label(t("Trial ended"), systemImage: "lock.fill").foregroundStyle(Color(nsColor: Brand.caution)).font(.system(size: 15, weight: .semibold))
                Text(t("Capturing and editing still work. Enter a license key to copy, save, upload, pin and print.")).font(.callout).foregroundStyle(Color(nsColor: Brand.textMuted))
            }
        case .keyProblem(let problem):
            VStack(alignment: .leading, spacing: 4) {
                Label(t("Key not usable"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color(nsColor: Brand.caution)).font(.system(size: 15, weight: .semibold))
                Text(problem).font(.callout).foregroundStyle(Color(nsColor: Brand.textMuted))
            }
        }
    }

    private func activate() {
        do {
            let info = try LicenseManager.shared.activate(input.value)
            failed.value = false
            if case .licensed = LicenseManager.shared.status {
                message.value = String(format: t("Activated for %@"), info.licensee)
            } else {
                message.value = t("Key accepted. Now paste the activation code for this computer.")
            }
            input.value = ""
        } catch {
            failed.value = true
            message.value = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        tick.value += 1
    }
}

/// Quiet bordered button in the brand palette; the primary one carries the accent.
struct BrandButton: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .foregroundStyle(primary ? Color(nsColor: Brand.ink) : Color(nsColor: Brand.text))
            .background(RoundedRectangle(cornerRadius: 7).fill(primary ? Color(nsColor: Brand.accent) : Color(nsColor: Brand.inkRaised)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: primary ? .clear : Brand.line), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Preferences ▸ License.
struct LicenseTab: View {
    var body: some View { LicenseView(embedded: true) }
}

@MainActor
public final class LicenseWindowController {
    public static let shared = LicenseWindowController()
    private var window: NSWindow?

    public func show(reason: String? = nil) {
        window?.close()
        let w = NSWindow(contentViewController: NSHostingController(rootView: LicenseView(reason: reason)))
        w.title = "Tenix-ChaeDiew — " + t("License")
        w.styleMask = [.titled, .closable]
        w.appearance = NSAppearance(named: .darkAqua)
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 520, height: 600))
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    public func reset() { window?.close(); window = nil }
}

// MARK: - About

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            if let icon = Brand.appIcon { Image(nsImage: icon).resizable().frame(width: 84, height: 84) }
            if let w = Brand.wordmarkOnDark { Image(nsImage: w).resizable().scaledToFit().frame(height: 40) }
            Text("\(t("Version")) 0.1.0").font(.system(size: 12)).foregroundStyle(Color(nsColor: Brand.textMuted))
            Text(t("Screenshot, annotate, read text and share — built for your team.")).font(.callout).multilineTextAlignment(.center)
                .foregroundStyle(Color(nsColor: Brand.textMuted)).frame(maxWidth: 300)
            Text("Powered by Panupong Nijjaboon").font(.system(size: 12, weight: .medium)).foregroundStyle(Color(nsColor: Brand.accent))
        }
        .padding(30)
        .frame(width: 400, height: 330)
        .background(Color(nsColor: Brand.ink))
        .foregroundStyle(Color(nsColor: Brand.text))
        .preferredColorScheme(.dark)
    }
}

@MainActor
public final class AboutWindowController {
    public static let shared = AboutWindowController()
    private var window: NSWindow?

    public func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            w.title = t("About Tenix-ChaeDiew")
            w.styleMask = [.titled, .closable]
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
