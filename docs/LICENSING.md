# Licensing

**Model.** 14-day trial from first launch. **A genuine key switches the app on at once — paste it and you are done (no server, no second code).** After that, copying, saving, uploading, pinning, printing and exporting need a license key. Capturing, viewing, editing and OCR stay free. Checking is local (no network, no account).

**Keys.** `TXCD1-…` — Base32 of a signed payload: version, edition, seats, issued day, expiry day (or perpetual), licensee name (≤ 32 bytes) and a random 6-byte key id, followed by a 64-byte **Ed25519** signature. About 150–190 characters, in groups of 8. The length is the cost of real security: the signature alone is 64 bytes (103 Base32 characters). Short "serial-style" keys (20–30 characters) need a shared secret inside the app, which anyone can extract and use to mint keys.

**Who can make keys.** Only the holder of the private key, via `ChaeDiewKeygen`. The app contains the public key only (`LicensePublicKey.swift`), so it can check keys but not create them.

## Issuing
```
swift build -c release --product ChaeDiewKeygen
.build/release/ChaeDiewKeygen issue --name "ACME Co" --days 365 --seats 10
.build/release/ChaeDiewKeygen issue --name "Panupong Nijjaboon" --perpetual
.build/release/ChaeDiewKeygen inspect TXCD1-…
```
The private key is `~/Library/Application Support/Tenix-ChaeDiew-Keygen/private.key` (permissions 600). **Back it up.** If it is lost you cannot issue more keys for this build; if it leaks, anyone can. To rotate: `ChaeDiewKeygen init --force --emit-swift Sources/ChaeDiewKit/LicensePublicKey.swift`, rebuild, and re-issue keys.

## Optional: one key = one computer (OFF by default)
Shipped mode (`requireActivation = false` in `LicenseManager` / Electron `LicenseManager`): any key with a valid signature that has not expired is Licensed; seats are informational only and one key works on any number of computers. Everything below is kept for switching back (`requireActivation: true`).

A key alone does nothing. The app shows a **machine code** (`MC-XXXX-XXXX-XXXX-XXXX`, a hash of the OS machine id: macOS `IOPlatformUUID`, Windows `MachineGuid`). The user sends you the Key ID + machine code; you answer with an **activation code** (`TXAC1-…`, an Ed25519 signature over key id ‖ machine). The app accepts the key only if that code verifies for its own machine, so a copied key or activation code is useless elsewhere. Native macOS app and Electron (macOS/Windows) use the same keys and codes; on a Mac both share one machine code.
```
ChaeDiewKeygen issue    --name "Tenix" --count 50 --perpetual --seats 1 --csv keys.csv   # 50 keys: Tenix #01 … #50
ChaeDiewKeygen activate TXCD1-… --machine MC-XXXX-XXXX-XXXX-XXXX --note "Somchai, laptop"
ChaeDiewKeygen release  TXCD1-… [--machine MC-…]     # free the seat so the key can move to a new computer
ChaeDiewKeygen ledger   [--csv ledger.csv]           # who has which key
```
The ledger (`~/Library/Application Support/Tenix-ChaeDiew-Keygen/ledger.json`) refuses to activate a key on more machines than its `seats` (1 for the 50 keys). Every key is bound, including multi-seat ones (seats = number of computers you will activate it on).

## Honest limits
Verification is client-side, so someone who patches the app binary can bypass it; this protects against casual sharing and typos, not a determined cracker. Activation is offline, so it cannot be *taken back*: `release` frees the seat in your ledger but the old computer keeps working until the key is removed there; and the machine code changes if the OS machine id does (reinstall on new hardware = new activation). Fully automatic activation / revocation would need an activation server. The trial start is stored locally and can be reset by someone determined.
