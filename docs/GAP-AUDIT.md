# Tenix-ChaeDiew vs Shottr — gap audit (2026-10-19)

Sources: shottr.cc feature list (fetched), live tests of Shottr 1.9.3 (docs/SHOTTR-OBSERVATIONS.md), and the user's own test of
Tenix-ChaeDiew. Status: ✅ done and covered by automated checks · 🟡 done but only partly / not tried with a real mouse ·
❌ missing. "Checks" = `swift run ChaeDiewChecks`. Nothing below has been driven with a real mouse and a real screen capture yet.

## Capture
| Feature | Status | Note |
|---|---|---|
| Fullscreen / Area / Window / Repeat / Delayed / Scrolling | 🟡 | Logic checked; live capture needs Screen Recording and was not exercised by me |
| Scrolling: max height, speed, reverse | 🟡 | Settings wired (checks cover the limit); live scrolling untested |
| Window capture shadow + background | 🟡 | shadow on/off (off = trimmed), transparent / solid colours / desktop wallpaper (wallpaper fills the margin around the window; not cropped to the window's real position) — live capture untested |
| OCR / QR / Colour picker from screen | ✅/🟡 | OCR + QR checked; the on-screen sampler is system API |
| Preview thumbnail after capture | 🟡 | Built; not seen live. ❌ "keep until used" option |
| Auto PNG/JPEG, Retina → 1×, 144 dpi metadata | ✅ | |

## Selection / crop
| Feature | Status | Note |
|---|---|---|
| Drag select + Enter to crop, Esc, nudge, ⌘-resize, [ ] | ✅ | |
| Shift = square | ✅ | |
| Q / W zoom to corners, ⌘2 zoom to selection | 🟡 | wired; zoom effect itself not visually checked |
| Smart selection: ⌘-click flat object, A auto-adjust | ✅ | ❌ edge-click auto-adjust, ❌ padding button, ❌ ⌥ preview ([ ] grows/shrinks instead) |
| Reset Crop (Edit menu) | ❌ | undo covers it; no dedicated item |

## Annotation tools
| Feature | Status | Note |
|---|---|---|
| Rectangle / Oval: fill, corner style | ✅ | ❌ fill opacity slider |
| Arrow: 4 head styles, bend, tapered body, ⌘ = reverse while drawing | ✅ | ❌ "narrow / super-slim" presets (thin head + thickness cover it) |
| Text label (pill) + plain, edit by double-click | ✅ | ❌ Tab inside text to insert the colour under the cursor |
| Counter: bubble, value, size, **rotate pointer** | ✅ | rotation added after the user's test |
| Blur / Blur text / Erase / Erase text, strength | ✅ | ❌ ⌘+B style "press B to blur a selection" |
| Spotlight 1–9, oval | ✅ | |
| Magnifier + expanding canvas | ✅ | |
| Highlighter: marker stroke (multiplies, text stays dark), round/flat ends, or box | ✅ | |
| Freehand: smoothness (⌥↑↓) | ✅ | ❌ stroke variability (⌘⏎) |
| Hand-drawn style (⌘R, panel toggle) | ✅ | rectangles, ovals, lines, arrows; ❌ text |
| Snap to objects (⌥⌘S toggle, pink guide lines, ⌃ = off while dragging) | ✅ | ❌ snapping while drawing/resizing, ❌ "similar objects" |
| Option-drag duplicate, ⌘C/⌘V of marks, marks come to front | ✅ | added after the user's test |
| Hold Space while drawing to move | ❌ | |
| Per-object style panel with colour palette | ✅ | ❌ custom saved colours |

## Measuring
| Feature | Status | Note |
|---|---|---|
| Ruler measures by itself under the pointer; 1 = height, 2 = width, arrows too; click keeps | ✅ | rewritten after the user's test |
| Manual line by dragging | ✅ | |
| Guides ⌥S / ⌥D | ✅ | |
| Shift = outer size of an element | ✅ | measures through text/icons (up to 48 px gaps) to the element's real edges |
| Logical (pt) vs physical (px) units | ✅ | per-ruler setting, default pt; Shottr toggles from the size box |
| Distance between two objects | ✅ | cursor on the gap measures the gap (same flat-colour run logic) |
| Colour readout, Tab / ⇧Tab / C | ✅ | |
| Contrast checker WCAG / APCA | ✅ | text = darkest pixel within 10 px vs colour under pointer; click the badge to switch WCAG ↔ APCA |

## View / navigation
| Feature | Status | Note |
|---|---|---|
| Zoom in/out/fit/100%, zoom % shown | ✅/🟡 | |
| Pan with Space+drag and right-drag | 🟡 | implemented; direction/feel not tried with a mouse |
| Quick zoom: Z + click (⌥ = out), Z + drag | ✅ | |
| "Prefer 100%" default zoom | ❌ | |
| Drag an image file onto the window to open it | 🟡 | implemented; not tried with a real drag |

## Image
| Feature | Status | Note |
|---|---|---|
| Resize (click size), backdrop, Add Capture, Rasterize | ✅/🟡 | Add Capture live flow untested |
| Paste image overlay, opacity 1–9 | ✅ | |
| Before/after GIF (Image ▾) | ✅ | original vs edited, 1.2 s each, saved + file copied for pasting; not tried in Slack etc. |
| Backdrop visible while editing | ✅ | live gradient, padding, rounded corners, shadow (a gradient-corner bug in the exported file was found and fixed) |

## Output / sharing
| Feature | Status | Note |
|---|---|---|
| Copy, Copy image, Save, Save As, Upload (S3 / HTTP), Pin, Print, drag-out | ✅/🟡 | upload verified against a local signature verifier, not a real bucket |
| Pin: resize by scrolling, opacity | 🟡 | check PinWindow behaviour against Shottr by hand |
| Uploaded screenshots list (⇧⌘U) | ✅ | copy/open/remove from list; ❌ deleting the remote object |
| URL scheme | ✅ | own scheme `chaediew://` |
| Raycast / Alfred integrations | ❌ | the URL scheme is the hook for them |

## App chrome
| Feature | Status | Note |
|---|---|---|
| Menus: File / Edit / Draw / Zoom / Window / Help, Keyboard Shortcuts sheet | ✅ | rebuilt after the user's test |
| Toolbar: copy/save/upload/pin/drag, undo/redo, PII, OCR, Image menu, colour readout, size, zoom; tools row | ✅ | |
| Hide menu-bar icon, always-on-top editor, splash, Esc behaviour | 🟡 | Esc ✅, hide icon ✅ (re-open the app to reach Preferences); ❌ always-on-top editor, splash is n/a |
| Hotkeys | ✅ | ours default to ⌃⇧1–9 (Shottr: ⇧⌘1 / ⇧⌘2) |

## UI tour (2026-10-19): the editor driven end to end and photographed

`Tenix-ChaeDiew --ui-tour <folder> [th]` opens the real editor on a sample page and performs ~35 steps through the window's own event
dispatch (drawing every tool, handles, panels, keyboard, paste, backdrop, Hide PII with real OCR, then Preferences ×5, Library, uploads
list, shortcuts sheet, thumbnail, pin, capture overlay), saving a PNG per step and logging expectations (`OK`/`FAIL`). It only
photographs this app's own windows, so it needs no Screen Recording permission. What it found and what was fixed:

| Finding | Status |
|---|---|
| Counter tool: pressing on an existing counter added another instead of moving it | fixed (counter/text tools move existing marks; ⌥-drag duplicates) |
| Counter numbering used the *last in the list*, which changes when marks are brought to the front | fixed (highest number + 1) |
| Hand-drawn oval was a perfect ellipse drawn twice | fixed: one thick marker loop whose ends cross |
| Double-click edit of a text label selected all text, so typing replaced it | fixed (caret goes to the end) |
| Uploaded-list dates showed Buddhist year 2569 in English UI | fixed (follows app language like the Library) |
| Floating style panel covered the top-right of the image, so nothing could be drawn under it | fixed: drag the panel by its background |
| Backdrop was four fixed presets | replaced by a full backdrop editor (see below) |
| Ruler pointer-over-text measures just the glyph (e.g. 6 pt) | by design (same as Shottr); hold ⇧ for the outer size |

Not reachable by the tour (still need a human with a real screen): the pop-up menus (Image ▾, size, zoom, menu bar), real screen capture,
scrolling capture HUD, Add Capture, drag-and-drop, print dialog, real uploads, global hotkeys, launch at login.

## Backdrop editor (new)
Type Solid / Gradient / Image · gradient Linear (angle) / Radial / Mesh (4 corner colours) · 18 presets · swap / randomise colours ·
padding 0–200 · shadow strength and blur · outer and inner corner radius · live in the editor and in the exported file · remembered
between sessions. Shottr's "Inset / Recenter" (screenshot offset inside the backdrop) is not implemented.

## Round 3 (user test of the 15:30 build)
Fixed: style changes did not reach a label that was being typed (they applied only after clicking away) → live; no separate lettering colour on labels/counters → "Text color" with Auto; counter values could only count up → any text (1.1, 3.6, A2), editable by double-click, sequence continues; the red "fail" contrast badge on flat areas → shown only next to real text, wording Low / AA / AAA, orange not red. New: Edit-text tool (OCR + font matching), font picker + bold for labels, branded one-bar toolbar with logo, license system (trial + Ed25519 keys + keygen), About window, DMG installer, app icon from the brand SVGs.
Not possible: a Windows `.exe` from this code (docs/WINDOWS.md).
