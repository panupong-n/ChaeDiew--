import AppKit
import ScreenCaptureKit

public enum CaptureError: LocalizedError {
    case displayNotFound
    case windowNotFound
    case permissionDenied

    public var errorDescription: String? {
        switch self {
        case .displayNotFound: return "Could not find the display to capture."
        case .windowNotFound: return "That window is no longer available."
        case .permissionDenied: return "Screen Recording permission is required."
        }
    }
}

/// A display prepared for capture. Tenix-ChaeDiew's own windows (toasts, HUDs) are excluded from every frame.
public struct GrabContext {
    let content: SCShareableContent
    let display: SCDisplay
    let filter: SCContentFilter
    public let pixelScale: CGFloat
    public var pixelSize: (width: Int, height: Int) {
        (Int((filter.contentRect.width * pixelScale).rounded()), Int((filter.contentRect.height * pixelScale).rounded()))
    }
}

public struct WindowInfo {
    public let id: CGWindowID
    /// Global coordinates, origin at the top-left of the primary display.
    public let frame: CGRect
    public let owner: String
    public let title: String
}

public enum WindowList {
    /// On-screen, normal-layer windows from front to back, excluding this app's own.
    public static func onScreen() -> [WindowInfo] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let me = getpid()
        return raw.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  (entry[kCGWindowOwnerPID as String] as? pid_t) != me,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict),
                  frame.width >= 40, frame.height >= 40 else { return nil }
            return WindowInfo(
                id: id, frame: frame,
                owner: entry[kCGWindowOwnerName as String] as? String ?? "",
                title: entry[kCGWindowName as String] as? String ?? "")
        }
    }

    /// Global top-left rect → coordinates local to `screen` (top-left origin), the space the selector uses.
    public static func localFrame(of global: CGRect, on screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenTopLeft = CGPoint(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY)
        return global.offsetBy(dx: -screenTopLeft.x, dy: -screenTopLeft.y)
    }
}

public enum ScreenGrabber {
    public static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    public static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    public static func screen(withDisplayID id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id }
    }

    public static func context(for screen: NSScreen) async throws -> GrabContext {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let id = displayID(of: screen), let display = content.displays.first(where: { $0.displayID == id })
        else { throw CaptureError.displayNotFound }
        let mine = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
        return GrabContext(content: content, display: display, filter: filter, pixelScale: CGFloat(filter.pointPixelScale))
    }

    /// One whole-display frame at native resolution, without the cursor.
    public static func capture(_ context: GrabContext) async throws -> CGImage {
        let config = SCStreamConfiguration()
        let size = context.pixelSize
        config.width = size.width
        config.height = size.height
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: context.filter, configuration: config)
    }

    public static func capture(screen: NSScreen) async throws -> (image: CGImage, pixelScale: CGFloat) {
        let context = try await context(for: screen)
        return (try await capture(context), context.pixelScale)
    }

    /// One window on its own, even if other windows overlap it.
    public static func captureWindow(id: CGWindowID, includeShadow: Bool) async throws -> (image: CGImage, pixelScale: CGFloat) {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.windowNotFound }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = Int((filter.contentRect.width * scale).rounded())
        config.height = Int((filter.contentRect.height * scale).rounded())
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = !includeShadow
        return (try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config), scale)
    }
}
