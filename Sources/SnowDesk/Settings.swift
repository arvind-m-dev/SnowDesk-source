import Foundation

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
        switch self {
        case .light: return 160
        case .medium: return 380
        case .heavy: return 800
        }
    }

    /// Multiplier for other weather (rain drops, leaves...).
    var factor: CGFloat {
        switch self {
        case .light: return 0.5
        case .medium: return 1
        case .heavy: return 1.8
        }
    }
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
        get { Intensity(rawValue: d.integer(forKey: "intensity")) ?? .medium }
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
