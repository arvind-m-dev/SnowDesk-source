import Foundation

/// Living things and scenery that can be switched on independently of the weather.
enum Scenery: String, CaseIterable {
    case birds, butterflies, bats, skiers, sledders, river

    var title: String {
        switch self {
        case .birds: return "Birds"
        case .butterflies: return "Butterflies"
        case .bats: return "Bats"
        case .skiers: return "Skiers"
        case .sledders: return "Sledders"
        case .river: return "River Along the Bottom"
        }
    }
}

/// A season is a preset: a mix of weathers, scenery, tree colours and a matching wallpaper.
enum Season: String, CaseIterable {
    case winter, spring, summer, autumn, monsoon

    var title: String {
        switch self {
        case .winter: return "Winter"
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .autumn: return "Autumn"
        case .monsoon: return "Monsoon"
        }
    }

    var weathers: Set<WeatherKind> {
        switch self {
        case .winter: return [.snow]
        case .spring: return [.petals]
        case .summer: return [.fireflies]
        case .autumn: return [.leaves, .mist]
        case .monsoon: return [.rain, .cloud]
        }
    }

    var scenery: Set<Scenery> {
        switch self {
        case .winter: return [.birds, .skiers, .sledders]
        case .spring: return [.birds, .butterflies, .river]
        case .summer: return [.birds, .butterflies, .river]
        case .autumn: return [.birds, .river]
        case .monsoon: return [.river]
        }
    }

    /// Index into Wallpapers.names.
    var wallpaper: Int {
        switch self {
        case .winter: return 0
        case .spring: return Wallpapers.index(of: "Spring Meadow")
        case .summer: return Wallpapers.index(of: "Summer Beach")
        case .autumn: return Wallpapers.index(of: "Autumn Forest")
        case .monsoon: return Wallpapers.index(of: "Monsoon River")
        }
    }

    /// Season from the calendar; the southern hemisphere is flipped.
    static func current(on date: Date = Date(), latitude: Double = 1) -> Season {
        var m = Calendar.current.component(.month, from: date)
        if latitude < 0 { m = (m + 5) % 12 + 1 }
        switch m {
        case 12, 1, 2: return .winter
        case 3, 4, 5: return .spring
        case 6, 7, 8: return .summer
        default: return .autumn
        }
    }
}

/// Holidays and festivals with their own decorations.
enum EventKind: String, CaseIterable {
    case christmas, newYear, valentines, easter, holi, halloween, diwali

    var title: String {
        switch self {
        case .christmas: return "Christmas"
        case .newYear: return "New Year"
        case .valentines: return "Valentine's Day"
        case .easter: return "Easter"
        case .holi: return "Holi"
        case .halloween: return "Halloween"
        case .diwali: return "Diwali"
        }
    }

    var greeting: String {
        switch self {
        case .christmas: return "Merry Christmas"
        case .newYear:
            let y = Calendar.current.component(.year, from: Date())
            let m = Calendar.current.component(.month, from: Date())
            return "Happy New Year \(m >= 7 ? y + 1 : y)"
        case .valentines: return "Happy Valentine's Day"
        case .easter: return "Happy Easter"
        case .holi: return "Happy Holi"
        case .halloween: return "Happy Halloween"
        case .diwali: return "Happy Diwali"
        }
    }

    /// Weather that suits the event (nil keeps the user's own).
    var weathers: Set<WeatherKind>? {
        switch self {
        case .christmas: return [.snow]
        case .newYear: return [.snow]
        case .valentines: return [.petals]
        case .easter: return [.petals]
        case .halloween: return [.leaves, .mist]
        case .holi, .diwali: return nil
        }
    }

    var wallpaper: Int? {
        switch self {
        case .christmas: return 0
        case .newYear: return Wallpapers.index(of: "New Year Fireworks")
        case .valentines: return Wallpapers.index(of: "Valentine Sunset")
        case .halloween: return Wallpapers.index(of: "Halloween Night")
        case .diwali: return Wallpapers.index(of: "Diwali Night")
        case .easter: return Wallpapers.index(of: "Spring Meadow")
        case .holi: return Wallpapers.index(of: "Spring Meadow")
        }
    }

    /// The event on (or a few days around) this date, if any.
    static func on(_ date: Date = Date()) -> EventKind? {
        let cal = Calendar.current
        let y = cal.component(.year, from: date), m = cal.component(.month, from: date), d = cal.component(.day, from: date)
        func near(_ month: Int, _ day: Int, before: Int, after: Int) -> Bool {
            guard let target = cal.date(from: DateComponents(year: y, month: month, day: day)),
                  let today = cal.date(from: DateComponents(year: y, month: m, day: d)),
                  let diff = cal.dateComponents([.day], from: target, to: today).day else { return false }
            return diff >= -before && diff <= after
        }
        if (m == 12 && d >= 31) || (m == 1 && d <= 2) { return .newYear }
        if m == 12 && d >= 10 { return .christmas }
        if near(2, 14, before: 3, after: 0) { return .valentines }
        if near(10, 31, before: 6, after: 0) { return .halloween }
        if let (em, ed) = easter(y), near(em, ed, before: 2, after: 1) { return .easter }
        if let (hm, hd) = holiDates[y], near(hm, hd, before: 2, after: 1) { return .holi }
        if let (dm, dd) = diwaliDates[y], near(dm, dd, before: 3, after: 2) { return .diwali }
        return nil
    }

    // Lunar-calendar festivals (main day).
    private static let holiDates: [Int: (Int, Int)] = [2026: (3, 4), 2027: (3, 22), 2028: (3, 11), 2029: (3, 1), 2030: (3, 20)]
    private static let diwaliDates: [Int: (Int, Int)] = [2026: (11, 8), 2027: (10, 29), 2028: (10, 17), 2029: (11, 5), 2030: (10, 26)]

    /// Western Easter Sunday (anonymous Gregorian algorithm).
    static func easter(_ y: Int) -> (Int, Int)? {
        let a = y % 19, b = y / 100, c = y % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31, day = (h + l - 7 * m + 114) % 31 + 1
        return (month, day)
    }
}

/// Settings for seasons, events, scenery and mixed weather.
extension Settings {
    private var ud: UserDefaults { .standard }

    /// Several weathers at once. Falls back to the older single `weather` setting.
    var weathers: Set<WeatherKind> {
        get {
            if let raw = ud.array(forKey: "weathers") as? [String] {
                return Set(raw.compactMap(WeatherKind.init(rawValue:)))
            }
            return weather == .clear ? [] : [weather]
        }
        set {
            ud.set(newValue.map(\.rawValue).sorted(), forKey: "weathers")
            weather = newValue.first ?? .clear
        }
    }

    /// Off: picking a weather replaces the others. On: picking toggles it in the mix.
    var mixWeathers: Bool {
        get { ud.object(forKey: "mixWeathers") as? Bool ?? false }
        set { ud.set(newValue, forKey: "mixWeathers") }
    }

    var scenery: Set<Scenery> {
        get {
            guard let raw = ud.array(forKey: "scenery") as? [String] else { return [.birds] }
            return Set(raw.compactMap(Scenery.init(rawValue:)))
        }
        set { ud.set(newValue.map(\.rawValue).sorted(), forKey: "scenery") }
    }

    /// The season the trees and river are dressed for.
    var season: Season {
        get { Season(rawValue: ud.string(forKey: "season") ?? "") ?? .winter }
        set { ud.set(newValue.rawValue, forKey: "season") }
    }

    /// Follow the calendar's season automatically.
    var autoSeason: Bool {
        get { ud.object(forKey: "autoSeason") as? Bool ?? false }
        set { ud.set(newValue, forKey: "autoSeason") }
    }

    /// Change the desktop wallpaper when the season or event changes.
    var themeWallpaper: Bool {
        get { ud.object(forKey: "themeWallpaper") as? Bool ?? false }
        set { ud.set(newValue, forKey: "themeWallpaper") }
    }

    /// "" = no event, "auto" = by date, otherwise an EventKind raw value.
    var eventChoice: String {
        get { ud.string(forKey: "eventChoice") ?? "auto" }
        set { ud.set(newValue, forKey: "eventChoice") }
    }

    var activeEvent: EventKind? {
        switch eventChoice {
        case "": return nil
        case "auto": return EventKind.on()
        default: return EventKind(rawValue: eventChoice)
        }
    }
}
