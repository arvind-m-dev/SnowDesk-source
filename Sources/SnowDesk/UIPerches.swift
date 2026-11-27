import AppKit
import ApplicationServices

/// A ledge inside an app window (a button, row, toolbar, divider...) where a bird can sit or a bat can hang.
/// Coordinates are global Cocoa (origin bottom-left of the main screen).
struct UISpot {
    let windowID: CGWindowID
    let minX: CGFloat
    let maxX: CGFloat
    let top: CGFloat
    let bottom: CGFloat
}

/// Finds ledges inside other apps' windows using the Accessibility API (needs the user's permission).
/// Results are cached per window and refreshed in the background, so the scene never waits on another app.
enum UIPerches {
    static var wanted: Bool {
        get { UserDefaults.standard.bool(forKey: "birdsOnUI") }
        set { UserDefaults.standard.set(newValue, forKey: "birdsOnUI") }
    }
    static var allowed: Bool { wanted && AXIsProcessTrusted() }

    /// Shows the system prompt (System Settings › Privacy & Security › Accessibility).
    @discardableResult
    static func requestAccess() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    private static let queue = DispatchQueue(label: "snowdesk.uiperches", qos: .utility)
    private static var cache: [CGWindowID: (time: Date, rect: CGRect, spots: [UISpot])] = [:]
    private static var pending = Set<CGWindowID>()

    /// Cached ledges for these windows (front-most first); stale ones are refreshed for next time.
    static func spots(in windows: [VisibleWindow]) -> [UISpot] {
        guard allowed else { return [] }
        var out: [UISpot] = []
        let now = Date()
        for w in windows.prefix(4) where w.pid > 0 {
            if let c = cache[w.id], c.rect == w.rect { out += c.spots }
            let stale = cache[w.id].map { now.timeIntervalSince($0.time) > 6 || $0.rect != w.rect } ?? true
            if stale && !pending.contains(w.id) {
                pending.insert(w.id)
                queue.async {
                    let found = scan(w)
                    DispatchQueue.main.async {
                        cache[w.id] = (Date(), w.rect, found)
                        pending.remove(w.id)
                    }
                }
            }
        }
        let live = Set(windows.map(\.id))
        cache = cache.filter { live.contains($0.key) }
        return out
    }

    private static let roles: Set<String> = [
        "AXRow", "AXCell", "AXGroup", "AXSplitter", "AXToolbar", "AXButton", "AXPopUpButton", "AXMenuButton",
        "AXTextField", "AXTextArea", "AXScrollArea", "AXTabGroup", "AXImage", "AXTable", "AXOutline", "AXList",
        "AXStaticText", "AXHeading", "AXCheckBox", "AXRadioButton", "AXSlider", "AXLink", "AXComboBox", "AXSegmentedControl",
    ]

    private static func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }

    /// Frame in AX coordinates (top-left origin).
    private static func frame(_ e: AXUIElement) -> CGRect? {
        guard let p = attr(e, kAXPositionAttribute), let s = attr(e, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt)
        AXValueGetValue(s as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }

    /// Walks one window's element tree (bounded) and collects ledges.
    private static func scan(_ w: VisibleWindow) -> [UISpot] {
        let app = AXUIElementCreateApplication(w.pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        // The window in AX coordinates, to match against.
        let want = CGRect(x: w.rect.minX, y: primaryH - w.rect.maxY, width: w.rect.width, height: w.rect.height)
        guard let wins = attr(app, kAXWindowsAttribute) as? [AXUIElement],
              let win = wins.first(where: { frame($0).map { abs($0.minX - want.minX) < 6 && abs($0.minY - want.minY) < 6 && abs($0.width - want.width) < 6 } ?? false })
        else { return [] }

        var spots: [UISpot] = []
        var seen = Set<Int>()
        var budget = 700
        func visit(_ e: AXUIElement, depth: Int) {
            guard budget > 0, depth < 14, spots.count < 160 else { return }
            budget -= 1
            if let role = attr(e, kAXRoleAttribute) as? String, roles.contains(role), let f = frame(e),
               f.width >= 30, f.height >= 3, f.width <= want.width + 2,
               f.minY > want.minY + 24, f.minY < want.maxY - 8, f.minX >= want.minX - 2, f.maxX <= want.maxX + 2 {
                let key = Int(f.minY / 3) * 10_000 + Int(f.minX / 20)
                if seen.insert(key).inserted {
                    spots.append(UISpot(windowID: w.id, minX: f.minX + 6, maxX: f.maxX - 6,
                                        top: primaryH - f.minY, bottom: primaryH - f.maxY))
                }
            }
            guard let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] else { return }
            for k in kids.prefix(60) { visit(k, depth: depth + 1) }
        }
        visit(win, depth: 0)
        return spots
    }
}
