import AppKit

enum Intensity: Int, CaseIterable {
    case light = 0, medium, heavy

    var title: String {
        switch self {
        case .light: return "Light"
        case .medium: return "Medium"
        case .heavy: return "Blizzard"
        }
    }

    var flakeCount: Int {
        let base: CGFloat
        switch self {
        case .light: base = 160
        case .medium: base = 380
        case .heavy: base = 800
        }
        return Int(base * Performance.current.particles)
    }

    /// Multiplier for other weather (rain drops, leaves...).
    var factor: CGFloat {
        let base: CGFloat
        switch self {
        case .light: base = 0.5
        case .medium: base = 1
        case .heavy: base = 1.8
        }
        return base * Performance.current.particles
    }
}

/// How hard SnowDesk works. Battery Saver is used automatically in macOS Low Power Mode.
enum Performance: Int, CaseIterable {
    case saver = 0, balanced, smooth

    var title: String {
        switch self {
        case .saver: return "Battery Saver (lightest)"
        case .balanced: return "Balanced"
        case .smooth: return "Extra Smooth (60 fps)"
        }
    }

    var fps: Int { self == .smooth ? 60 : 30 }
    /// How often window positions are read (a system call that isn't free).
    var poll: TimeInterval { self == .saver ? 1.0 / 8 : (self == .balanced ? 1.0 / 15 : 1.0 / 30) }
    /// Share of snowflakes, raindrops and leaves.
    var particles: CGFloat { self == .saver ? 0.5 : 1 }

    static var chosen: Performance {
        get { Performance(rawValue: UserDefaults.standard.object(forKey: "performance") as? Int ?? 1) ?? .balanced }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "performance") }
    }

    static var current: Performance { ProcessInfo.processInfo.isLowPowerModeEnabled ? .saver : chosen }
}

enum LightsMode: Int, CaseIterable {
    case off = 0, twinkle, chase, music

    var title: String {
        switch self {
        case .off: return "Off"
        case .twinkle: return "Slow Twinkle"
        case .chase: return "Chase"
        case .music: return "Flash to Music (uses microphone)"
        }
    }
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }

    var snowing: Bool {
        get { bool("snowing", true) }
        set { d.set(newValue, forKey: "snowing") }
    }

    var intensity: Intensity {
        get { Intensity(rawValue: d.object(forKey: "intensity") as? Int ?? Intensity.medium.rawValue) ?? .medium }
        set { d.set(newValue.rawValue, forKey: "intensity") }
    }

    var weather: WeatherKind {
        get { WeatherKind(rawValue: d.string(forKey: "weather") ?? "") ?? .snow }
        set { d.set(newValue.rawValue, forKey: "weather") }
    }

    var sounds: Bool {
        get { bool("sounds", true) }
        set { d.set(newValue, forKey: "sounds") }
    }

    var santaVisits: Bool {
        get { bool("santaVisits", true) }
        set { d.set(newValue, forKey: "santaVisits") }
    }

    var lightsMode: LightsMode {
        get { LightsMode(rawValue: d.integer(forKey: "lightsMode")) ?? .off }
        set { d.set(newValue.rawValue, forKey: "lightsMode") }
    }

    var fireplace: Bool {
        get { bool("fireplace", false) }
        set { d.set(newValue, forKey: "fireplace") }
    }

    /// 0 off, 1 a few trees, 2 a small forest along the bottom.
    var treeStyle: Int {
        get { d.object(forKey: "treeStyle") as? Int ?? 2 }
        set { d.set(newValue, forKey: "treeStyle") }
    }

    /// Display to use (CGDirectDisplayID), or 0 for all displays.
    var displayID: UInt32 {
        get { UInt32(truncatingIfNeeded: d.integer(forKey: "displayID")) }
        set { d.set(Int(newValue), forKey: "displayID") }
    }

    // Follow-the-weather city
    var cityName: String? {
        get { d.string(forKey: "cityName") }
        set { d.set(newValue, forKey: "cityName") }
    }
    var cityLat: Double {
        get { d.double(forKey: "cityLat") }
        set { d.set(newValue, forKey: "cityLat") }
    }
    var cityLon: Double {
        get { d.double(forKey: "cityLon") }
        set { d.set(newValue, forKey: "cityLon") }
    }

    // Cozy room
    var roomShown: Bool {
        get { bool("roomShown", false) }
        set { d.set(newValue, forKey: "roomShown") }
    }
    var roomTheme: Int {
        get { d.integer(forKey: "roomTheme") }
        set { d.set(newValue, forKey: "roomTheme") }
    }
    var ornaments: [[String: Any]] {
        get { d.array(forKey: "ornaments") as? [[String: Any]] ?? [] }
        set { d.set(newValue, forKey: "ornaments") }
    }
}

extension NSScreen {
    var displayID: UInt32 { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}

enum Displays {
    /// Screens SnowDesk draws on: the chosen display if it's connected, otherwise all of them.
    static var active: [NSScreen] {
        let id = Settings.shared.displayID
        if id != 0, let s = NSScreen.screens.first(where: { $0.displayID == id }) { return [s] }
        return NSScreen.screens
    }

    /// Where the fireplace, forest and cozy room go.
    static var home: NSScreen? { active.first }
}
