# Windows (and a cross-platform Mac build): the Electron app

The native app (Swift/AppKit) is macOS-only. For Windows there is a separate **Electron** build in `electron/` — same brand, same licence keys, same activation codes. It also runs on macOS (universal DMG).

## Build
```
cd electron
npm install
node node_modules/electron/install.js      # npm blocks install scripts by default
npm run dist:win    # dist/Tenix-ChaeDiew Setup 0.1.0.exe  (NSIS, x64) — can be built from a Mac, no Wine needed
npm run dist:mac    # dist/Tenix-ChaeDiew-0.1.0-universal.dmg
npm test            # licence + editor-model checks (Node)
npx electron . --smoke <dir>   # drives real windows with real pointer events, writes screenshots; also works on the packaged app
```
If your shell has `ELECTRON_RUN_AS_NODE=1` (VS Code terminals do), run `env -u ELECTRON_RUN_AS_NODE …` or Electron starts as plain Node.

## What it has
Capture area / full screen (global ⌘⇧2 / ⌘⇧1, Ctrl+Shift+2/1 on Windows, tray icon), open a picture; editor with select/move/resize, rectangle, ellipse, arrow, line, pen, highlight, text, counter (double-click to type 1.1, 3.6.2, A2; next one continues), pixelate, crop, **edit text in the picture** (OCR + font/size/colour match + background fill), OCR to text (English + Thai, offline), backdrop (gradients, padding, radius, shadow), copy/save PNG/JPEG, undo/redo, Thai/English UI, licence + activation. Colours and sizes apply live.

## What it does not have (yet) compared with the native app
Scrolling capture, ruler/auto-measure, magnifier/spotlight, PII auto-detect, GIF export, upload to S3, pin to screen, print, snapping guides, sketchy hand-drawn marks, history gallery, URL scheme, launch at login. The native macOS app remains the complete one.

## Not verified on a real Windows machine
The installer was built and its contents (icon, version info, files) inspected, and the same code passes the full smoke run on macOS, but it has **not been run on Windows**. Things to check there first: the screen-capture overlay on multi-monitor / mixed-DPI setups, the global shortcuts, the titlebar overlay, and the machine-code read (`reg query HKLM\SOFTWARE\Microsoft\Cryptography /v MachineGuid`). The installer is unsigned, so SmartScreen will warn ("More info → Run anyway"); a code-signing certificate removes that.
