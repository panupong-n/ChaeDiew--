import AppKit

/// Help ▸ Keyboard Shortcuts: a readable cheat sheet of everything the editor does.
@MainActor
public final class ShortcutsWindowController {
    public static let shared = ShortcutsWindowController()
    private var window: NSWindow?

    private static let sections: [(title: String, rows: [(keys: String, what: String)])] = [
        ("Tools", [
            ("V", "Select / move — drag on empty space to select an area"), ("C", "Crop tool"), ("R  O  A  L  P", "Rectangle · Ellipse · Arrow · Line · Pen"),
            ("T", "Text label"), ("B", "Blur / Erase"), ("N", "Numbered marker"), ("H", "Highlight"), ("S", "Spotlight (1–9 = darkness)"),
            ("M", "Ruler — measures by itself, click to keep"), ("G", "Magnifier"),
        ]),
        ("Ruler", [
            ("1 / ↑ ↓", "Hold: measure height only"), ("2 / ← →", "Hold: measure width only"), ("⌥S / ⌥D", "Hold: vertical / horizontal guide line"),
            ("Click", "Keep the measurement on the image"), ("Drag", "Draw a manual measuring line"),
        ]),
        ("Selecting an area", [
            ("Enter", "Crop to the selection"), ("Esc", "Clear the selection"), ("← ↑ → ↓", "Move 1 px (⇧ = 10 px)"),
            ("⌘ + arrows", "Resize 1 px (⇧ = 10 px)"), ("[  ]", "Shrink / grow by 1 px per side"), ("Q  W", "Zoom to its top-left / bottom-right"),
            ("C", "Copy its average colour"), ("⌘2", "Zoom to the selection"),
        ]),
        ("Colours", [("Tab", "Copy the colour under the pointer"), ("⇧Tab", "Copy the darkest nearby pixel (text colour)")]),
        ("Marks", [
            ("Delete", "Remove the selected mark"), ("⌥ + drag", "Duplicate a mark"), ("⌘C  ⌘V", "Copy / paste a selected mark"),
            ("Double-click text", "Edit it"), ("Drag the round handle", "Bend an arrow · rotate a counter's pointer"),
            ("1–9", "Pasted picture: opacity"), ("⇧", "Snap lines to 45° and boxes to squares"),
        ]),
        ("View", [("⌘+  ⌘−", "Zoom in / out"), ("⌘1", "Fit"), ("⌘0", "100%"), ("Space + drag  ·  right-drag", "Pan")]),
        ("Files", [
            ("⌘S  ⇧⌘S", "Save · Save as"), ("⇧⌘C", "Copy the image"), ("⌘V", "Paste a picture as an overlay"), ("⌘E", "Upload"),
            ("⌘P", "Pin"), ("⇧⌘P", "Print"), ("⇧⌘H", "Hide personal data"), ("⇧⌘T", "Recognise text"), ("⌥⌘A", "Add another capture"),
            ("⇧⌘R", "Merge marks into the image"),
        ]),
    ]

    public func show() {
        if window == nil {
            let text = NSMutableAttributedString()
            let heading: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: Brand.text]
            let keyAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: Brand.accent]
            let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Brand.textMuted]
            let tabs = NSMutableParagraphStyle()
            tabs.tabStops = [NSTextTab(textAlignment: .left, location: 190)]
            tabs.headIndent = 190
            tabs.paragraphSpacing = 3
            for section in Self.sections {
                text.append(NSAttributedString(string: "\n" + t(section.title) + "\n", attributes: heading))
                for row in section.rows {
                    let line = NSMutableAttributedString(string: row.keys, attributes: keyAttrs)
                    line.append(NSAttributedString(string: "\t" + t(row.what) + "\n", attributes: body))
                    line.addAttribute(.paragraphStyle, value: tabs, range: NSRange(location: 0, length: line.length))
                    text.append(line)
                }
            }
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 620))
            let view = NSTextView(frame: scroll.bounds)
            view.isEditable = false
            view.backgroundColor = Brand.ink
            view.drawsBackground = true
            view.textContainerInset = NSSize(width: 16, height: 8)
            view.textStorage?.setAttributedString(text)
            view.autoresizingMask = [.width]
            scroll.documentView = view
            scroll.hasVerticalScroller = true
            let w = NSWindow(contentRect: scroll.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = Brand.ink
            w.title = "Tenix-ChaeDiew — " + t("Keyboard Shortcuts")
            w.contentView = scroll
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    public func reset() { window?.close(); window = nil }
}
