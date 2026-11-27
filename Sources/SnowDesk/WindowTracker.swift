import AppKit
import CoreGraphics

/// A visible app window, in global Cocoa coordinates (origin bottom-left of the main screen).
struct VisibleWindow {
    let id: CGWindowID
    let rect: CGRect
    var pid: pid_t = 0
}

enum WindowTracker {
    private static let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Normal app windows on the current Space, front-most first.
    /// Window bounds are readable without Screen Recording permission.
    static func snapshot() -> [VisibleWindow] {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result: [VisibleWindow] = []
        for info in list {
            // Layer 0 = normal windows; 1...8 = floating windows such as Picture-in-Picture
            // (Google Meet / YouTube PiP, Chrome layer 3) and utility panels. Dock/menu bar are 20+.
            guard let layer = info[kCGWindowLayer as String] as? Int, (0...8).contains(layer),
                  (info[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  let num = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            if alpha < 0.05 || cg.width < 80 || cg.height < 40 { continue }
            // CG global coords are top-left origin; flip into the main screen's bottom-left space.
            let rect = CGRect(x: cg.minX, y: screenHeight - cg.maxY, width: cg.width, height: cg.height)
            result.append(VisibleWindow(id: num, rect: rect, pid: info[kCGWindowOwnerPID as String] as? pid_t ?? 0))
        }
        return result
    }
}
