import AppKit
import ChaeDiewKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    let args = CommandLine.arguments

    if let i = args.firstIndex(of: "--ui-smoke"), args.count > i + 1 {
        // Developer aid: render the real windows with sample data to PNGs and quit.
        app.setActivationPolicy(.accessory)
        let language: Lang = args.contains("th") ? .th : .en
        UISmoke.run(outputDir: URL(fileURLWithPath: args[i + 1]), language: language)
    } else if let i = args.firstIndex(of: "--ui-tour"), args.count > i + 1 {
        // Developer aid: drives the real editor with synthetic mouse/keyboard events and photographs every step.
        app.setActivationPolicy(.accessory)
        UITour.run(outputDir: URL(fileURLWithPath: args[i + 1]), language: args.contains("th") ? .th : .en)
    } else {
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
    }
    app.run()
}
