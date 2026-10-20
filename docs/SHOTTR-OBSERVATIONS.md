# Shottr 1.9.3 — observed behaviour (reference for Tenix-ChaeDiew)

Source: Shottr running on this Mac with a full licence (menus read through the Accessibility API; the editor driven
with keyboard/mouse on a synthetic test image; its own windows screenshotted), plus shottr.cc documentation.
Behaviour only; no code or assets were copied. Tenix-ChaeDiew implements its own versions.

## Editor window
- Top bar, left to right: Copy · Save · Pin · drag-out handle · tools · colour readout · image size · zoom.
- Tools shown (window dependent): Select/move (shows a small snap "#" badge) · Arrow · Text (T) · Ruler ("12") ·
  Rectangle · [slot showing the last-used overflow tool] · Freehand · "…". The "…" menu holds the rest:
  Magnifier (M), Add Capture (⌘A), Blur/Erase (B), Highlighter (H), Spotlight (S), Counter (C), Oval (O), Line (L),
  Paste Image (⌘V). Docs: all 16 tools show when the window is wide enough.
- Right of the bar: live colour under the cursor (`#F7F7F7`, "Tab to copy"), image size (`800×500pt`), zoom (`100%`).
  Tab copies that colour; Shift+Tab the darkest pixel in a 20×20 area (for text); C the average colour of a selection.
- Each object, once drawn, is selected with 8 handles and a floating **style panel** at the canvas top-right:
  back chevron · colour · thickness slider (tapered preview) · object-specific options.

## Per-tool findings
| Tool | Look / behaviour | Style panel |
|---|---|---|
| Rectangle (R) | rounded outline by default | corner (round/square), hatch fill, solid fill |
| Arrow (A) | thick tapered arrow; mid handle bends it into an arch | 4 head styles (hollow, normal, thin, double) + stepper |
| Text (T) | filled pill label, white text; click, type; tool returns to Select afterwards | (colour/size) |
| Blur/Erase (B) | mosaic by default | modes **Blur · Blur Text · Erase · Erase Text** + strength slider |
| Spotlight (S) | dims everything except the region; region gets a coloured border | colour · darkness slider (keys 1–9) · rect/ellipse |
| Counter (C) | numbered speech-bubble with a tail toward the click; auto-increments; value editable 0–99 | colour · size · value stepper |
| Magnifier (M) | source circle + large zoomed bubble with connector; **canvas expands** to fit (size went 800×500 → 853×704) | colour · zoom · rounded/oval |
| Highlighter (H) | text highlighter | colour (yellow) · thickness |
| Ruler ("12") | tutorial: hold an arrow key or 1/2 and move the mouse over an element to read its size in px; click imprints it; Opt+S/D guides | — |

## Selection / crop
Dragging in Select mode makes a selection (size label, "Hit Enter to crop"). The bar becomes: Crop · copy-area ·
zoom-to-selection · text recognition in the selection · … · erase · cancel. Arrow keys nudge 1 px (Shift 10),
⌘+arrows resize, `[`/`]` grow by 1 px per side, Shift = square, smart selection snaps to edges (Option previews),
⌘-click selects a flat-coloured object. Q / W zoom to the selection's top-left / bottom-right. Edit ▸ Reset Crop.

## Menus (File / Edit / Draw / Zoom)
File: Copy Image ⇧⌘C · Save ⌘S · Save As ⇧⌘S · Upload ⌘E · Pin ⌘P · Print ⇧⌘P · Open File ⇧⌘O · Open From Clipboard ⇧⌘V ·
Close ⌘W · Close All ⌥⌘W. Edit: Undo/Redo · Reset Crop · **Rasterize (Merge) Image** · standard text edits.
Draw: Arrow A · Text T · Rectangle R · Freehand D · Magnifier M · Highlighter H · Blur B · Spotlight S · Counter C ·
Oval O · Line L · **Add Capture** · Snap to Objects · Snap to Similar Objects. Zoom: ⌘+ ⌘- · Fit ⌘1 · 100% ⌘0 ·
To Selection ⌘2 · Full Screen F.

## Preferences
- **General:** window-screenshot background (Wallpaper / Transparent / Solid colour / Trim shadow) · screenshots folder ·
  save format (PNG / Auto PNG-JPEG) · downscale retina to 1× when saving · scrolling max height (20,000 px, up to
  200,000) · scrolling speed slider · launch at startup · after screenshot (Show / Copy / Save) · after area crop
  (Thumbnail / Editor) · hide thumbnail (manually…).
- **Hotkeys:** Fullscreen ⇧⌘1 · Area ⇧⌘2 · Instant text/QR recognition ⌃⌥⌘O; repeat-area, any-window, active-window,
  scrolling, show-Shottr are unassigned by default. (Advice shown: take over the system ⌘⇧3/⌘⇧4.)
- **Advanced:** primary OCR language · remove OCR line breaks · hide menubar icon · no splash · main window always on
  top · reverse scroll direction (zoom, scrolling capture) · prefer 100% zoom · Esc action (copy / save) ·
  confirmation style (custom notification) · URL-scheme API (deep links) · diagnostics collection.
- **Uploading:** S3-compatible (needs activation). **License** tab not examined.

## URL scheme (from the binary's strings; needs "Enable deep links")
`shottr://grab/area` · `fullscreen` · `window` · `window/active` · `delayed` · `repeat` · `scrolling` · `scrolling/reverse`.

## Full toolbar (wide window)
`shottr` logo · Copy · Save · Pin · drag-out handle (dotted, confirmed: highlights on click, opens nothing) ·
Select · Arrow · Text · Ruler · Rectangle · Spotlight(▣) · Freehand · Magnifier · Add Capture · Blur/Erase ·
Highlighter · Spotlight(dashed) · Counter · Oval · Line · Paste Image. In a narrow window the last items collapse into
"…" and the slot before "…" shows the most recently used overflow tool. Window can be resized by dragging its corner
(it grew 836×552 → 1436×609); the "F" key did not enter full screen.
No Backdrop button was found in the toolbar or menus (release notes: gradient, shadow, rounded corners; the binary
mentions "Window already has backdrop"/"WindowBG", so it is probably tied to window captures — unverified).

## Documented URL scheme (shottr.cc/kb/urlschemes; works when "Enable deep links" is on)
`show` · `grab/fullscreen|area|repeat|window|scrolling|scrolling/reverse|delayed|delayed=<s>|append` · `ocr` ·
`load/clipboard` · `load/file` · `uploads` · `settings`. Every `grab/…` accepts `?then=copy,save,edit,pin,thumbnail`.
Note: sending `shottr://grab/area` and the ⇧⌘2 hotkey as synthetic input produced no visible overlay in this test.

## Not examined live (and why)
- Capture overlays (area/window/scrolling), thumbnail, pinned windows, Add Capture, Paste Image, overlay/GIF: the
  capture overlay is not a window that can be screenshotted by id, and other apps (LINE, Teams) kept taking focus.
- Backdrop panel, hand-drawn style (⌘R), freehand/line/oval panels, Save As / Print dialogs, uploading tab.
