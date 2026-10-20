# Tenix-ChaeDiew — design system (native macOS, AppKit)

Source of truth in code: `Sources/ChaeDiewKit/Brand.swift` (palette, logo images), `Chrome.swift` (ChromeButton, ChoiceBar), `StylePanel.swift`, `BackdropPanel.swift`. The window chrome is always dark (`NSAppearance.darkAqua`).

## Colour
| Token | Hex | Use |
|---|---|---|
| ink | #15171C | window and title-bar background (the brand ink) |
| inkRaised | #1D2027 | panels, fields |
| inkHover | #2A2E37 | hovered control |
| line | #2D323C | hairlines, panel borders |
| text | #F5F7FA | primary text and active icons |
| textMuted | #A3ABBA | labels, idle icons (7.4:1 on ink) |
| textFaint | #7C8494 | hints (4.6:1 on ink) |
| accent | #1FA0FF | the active tool, the selected choice, primary buttons; ink text on it (6.3:1) |
| positive / caution | #4ADE80 / #FBBF24 | licensed ✓ / needs attention; never red for "fail" on non-errors |
The canvas surround is one step darker than ink (#101215) so the picture leads.

## Type
SF Pro (system). Labels 11 pt medium, values 12–13 pt, panel titles 13 pt semibold. Numerals that change (size, zoom, hex) are monospaced-digit so they do not jitter. No second typeface; the wordmark is an image.

## Components
- **ChromeButton** — 30 pt square, SF Symbol 14 pt regular, radius 7. Idle muted, hover raised, active = accent icon on 20 % accent. Never takes keyboard focus (the canvas keeps the single-key shortcuts).
- **ChoiceBar** — segmented choice; selected = accent fill with ink text; replaces the system segmented control, whose selected state cannot be branded readably.
- **Panels** (style, backdrop) — solid inkRaised, 1 pt line border, radius 12, draggable by the background so they never cover what you draw.
- **Toolbar** — one unified title-bar toolbar: wordmark · file actions · history · tools · PII/OCR/Image · flexible space · colour readout · size · zoom. Low-priority groups fold into the » menu on narrow windows.
- **Icons** — SF Symbols only, one weight; no emoji or text glyphs as icons.

## Motion
None decorative. State changes are immediate (live style, live backdrop).

## Rules
Follow Impeccable's craft floor (`.claude/skills/impeccable/reference/craft-floor.md`): contrast ≥ 4.5:1 for text, states for hover/disabled/active/focus, copy that names the action, no gradient text, no glass-as-decoration, no card grids as structure.
