# Tenix-ChaeDiew  (เท็นนิค แชะเดียว)

*Powered by Panupong Nijjaboon*

Screenshot, annotate, OCR and share tool for macOS, built for internal use (menu-bar app, Thai/English UI).
Written from scratch on public Apple APIs (ScreenCaptureKit, Vision, AppKit, SwiftUI, CryptoKit). No third-party
code, no telemetry: everything runs on the Mac, and the only network traffic is an upload you configure yourself.

## Windows / Electron build
A separate Electron app in `electron/` (Windows `.exe` installer + macOS universal DMG) shares the brand, licence keys and activation codes. One licence key = one computer. See `docs/WINDOWS.md` and `docs/LICENSING.md`.

## What it does

**Capture** — area · full screen · window (even when overlapped) · scrolling (auto-scroll or manual) · delayed (3/5/10 s)
· repeat last area · screen colour picker (HEX / RGB / HSL / OKLCH) · QR / barcode scan · open image / clipboard image.
Window mode: press Space in the selector to switch between area and window.

**Read** — OCR to clipboard (Thai + English, on-device) · text search across your capture history.

**Annotate** — select/move/delete/nudge marks · rectangle · ellipse · arrow · line · pen · text · pixelate · numbered
markers · highlight · spotlight · pixel ruler · magnifier · crop · resize · undo/redo (100 steps).
Tool keys: V C R O A L P T B N H S M G. Hold ⇧ to snap lines to 45° and boxes to squares.
A floating **style panel** (top-right of the canvas) edits the selected mark, or the defaults of the active tool:
rectangle outline/hatch/solid + round/square corners · arrows with 4 head styles and a draggable bend · blur modes
*Blur / Blur text / Erase / Erase text* with strength · numbered speech-bubble counters with an editable value and size ·
text as a filled label (auto black/white lettering) · spotlight darkness 1–9 (keys 1–9) and rectangle/oval ·
magnifier bubble with 2–4× zoom and a draggable bubble.
**Selection** — drag on empty canvas (Select or Crop tool): a pixel-size label shows; ⏎ crops (or double-click inside), Esc cancels,
arrows move it (⇧ = 10 px), ⌘+arrows resize, `[` `]` shrink/grow per side, C copies its average colour; OCR and Copy then act on the
selection only. **Colour readout** in the toolbar follows the pointer: Tab copies it, ⇧Tab the darkest pixel nearby (text colour).
**Image menu / Edit menu** — *Add capture* (⌥⌘A: take another area and join it below the image if it is about as wide, otherwise beside it),
*Paste image* (⌘V: the clipboard picture becomes a movable, resizable overlay), *Merge marks into image* (⇧⌘R: rasterize). The canvas
grows by itself when a magnifier bubble or pasted picture sticks out, instead of cutting it off.
**Output & automation** — optional automatic PNG/JPEG choice, Retina → 1× downscale on save/upload, window-screenshot background
(transparent / white / black / grays), scrolling capture limits (max height, speed, reverse direction), *Show thumbnail* after
capture (click to edit, Copy/Save buttons, fades after 8 s), File ▸ Print (⇧⌘P). The **`chaediew://` URL scheme** (off by default,
enable in Preferences): `grab/area|fullscreen|window|scrolling|repeat|delayed=5|append`, `ocr`, `qr`, `color`, `load/clipboard`,
`load/file?path=/abs/path`, `show`, `settings`; every `grab/…` accepts `?then=copy,save,edit,pin,thumbnail`.
**Install** — `scripts/make-dmg.sh` builds `dist/Tenix-ChaeDiew-<version>.dmg` (drag to Applications). There is no Windows build: see docs/WINDOWS.md.
**License** — 14-day trial, then a signed key (Preferences ▸ License). Keys are Ed25519-signed; generate them with `ChaeDiewKeygen` (docs/LICENSING.md).
**Look** — one dark, branded title-bar toolbar (logo · actions · tools · readouts), brand palette and components in `Brand.swift`/`Chrome.swift`, rules in DESIGN.md.
**Edit text in the picture** (E) — click text in the screenshot: OCR finds the line, the best-matching installed typeface/size/colour is chosen by comparing glyph shapes, the original is erased and your new text set in its place (movable, re-editable). Counters take any text (1.1, 3.6, A2) and continue the sequence.
**Backdrop** — Image ▾ ▸ Backdrop…: solid / gradient (linear, radial, 4-corner mesh) / image, 18 presets, padding, shadow, outer and inner radius, live preview, remembered. **UI tour** — `Tenix-ChaeDiew --ui-tour <dir>` drives the editor with synthetic events and photographs every step (see docs/GAP-AUDIT.md).
**More** — before/after GIF (Image ▾), hand-drawn style (⌘R), quick zoom (hold Z: click / ⌥-click / drag), Shift while measuring = outer size, drag an image file onto an editor to open it, uploaded-links list (⇧⌘U), desktop-wallpaper window background, 144 dpi PNGs, optional hidden menu-bar icon.
**Ruler** (M): measures the flat-coloured element under the pointer by itself (width and height); hold 1 / ↑↓ for height only, 2 / ←→ for width only; ⌥S / ⌥D show guide lines; click keeps it, drag draws a manual line. Counters have a handle to rotate their pointer; ⌥-drag duplicates a mark, ⌘C/⌘V copy marks. See docs/GAP-AUDIT.md for what Shottr has that this app does not yet. Selected marks show resize handles; double-click text to edit it.

**Protect** — *Hide PII*: OCR finds emails, Thai national IDs (checksum-validated), phone numbers, payment cards
(Luhn-validated), IPv4 addresses, API keys / tokens and `password=…` pairs (plus your own regexes) and pixelates them.
Pixelation replaces the pixels, so the hidden text cannot be recovered from the saved file.

**Share** — copy · save (PNG/JPEG) · pin as floating window · drag the file out of the editor into any app ·
upload to S3-compatible storage (AWS, MinIO, R2…) or your own HTTP endpoint and get a link copied ·
backdrop (gradient, padding, rounded corners, shadow) for docs and slides.

**Library** — every capture is kept (optional) with its OCR text, searchable by content or date, auto-deleted after a
retention period you choose (default 30 days).

Default hotkeys (all changeable in Preferences): area ⌃⇧4 · full screen ⌃⇧3 · window ⌃⇧5 · scrolling ⌃⇧6 ·
OCR ⌃⇧2 · QR ⌃⇧8 · repeat last ⌃⇧7 · colour picker ⌃⇧1 · library ⌃⇧9.

## Build & run

```bash
swift run ChaeDiewChecks                              # automated checks (no Xcode needed)
BUNDLE_ID=com.yourorg.chaediew ./scripts/make-app.sh  # produces Tenix-ChaeDiew.app
open Tenix-ChaeDiew.app
```

Needs macOS 14+ and the Swift toolchain (Command Line Tools are enough; XCTest, Swift Testing and the `@State` macro
are not available there, so tests are a plain executable and the SwiftUI views use `ObservableObject` boxes).

**Permissions** (System Settings › Privacy & Security): *Screen Recording* for any capture (quit and reopen Tenix-ChaeDiew
after granting); *Accessibility* only if you use auto-scroll in scrolling capture. Builds are ad-hoc signed, so macOS
forgets permissions on every rebuild unless you sign with a stable identity:
`SIGN_IDENTITY="Developer ID Application: …" ./scripts/make-app.sh`.

## Layout

- `Sources/ChaeDiewKit` – everything: capture, selection overlay, editor, renderer, OCR, redaction, stitching, SigV4,
  upload, library, preferences
- `Sources/Tenix-ChaeDiew` – entry point. `Tenix-ChaeDiew --ui-smoke <dir> [th]` renders the real windows with sample data to PNGs
- `Sources/ChaeDiewChecks` – automated checks

## Verification status

Automated (`swift run ChaeDiewChecks`, 404 checks): geometry and hit-testing, editor undo/redo/crop/resize, rendering and pixelation, backdrop,
colour conversions, settings/hotkeys, PII patterns and validators, **AWS Signature V4 against AWS's published
examples**, scroll stitching (down, up, sticky header, rejected jumps), library storage/search/retention, OCR +
auto-redact on a screen-sized image, QR detection. UI windows were rendered and inspected in English and Thai.
Uploads: `python3 scripts/fake-s3.py` starts a local server that re-computes SigV4 independently; run
`swift run ChaeDiewChecks --upload-e2e <port>` against it (7 checks: signed PUT accepted, presigned link round-trips,
tampered/wrong-secret/bad-token rejected).

**Not verified** (need a person at the screen with permissions granted): real ScreenCaptureKit capture on
Retina/multi-display setups, the drag-to-select overlay, window capture, live scrolling capture (stitching is tested on
synthetic frames; the auto-scroll event injection and the timing around smooth-scroll are not), hotkeys that clash with
other apps, pin window, drag-out, launch-at-login, and uploads against a real bucket/endpoint.

Known limits: scrolling capture stitches by matching rows, so it handles sticky headers but duplicates a sticky
footer, and fast flings that move more than ~90% of the frame between captures are rejected rather than guessed.
The first OCR when the system's Vision model cache is cold takes 12–25 s. Tenix-ChaeDiew warms Vision up in the background at
launch, after which OCR is ~0.1 s (measured: still instant after 4 min idle; longer idle not measured).
