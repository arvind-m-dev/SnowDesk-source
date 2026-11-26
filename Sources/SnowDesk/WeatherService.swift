import Foundation

/// Follows the current weather in a city via Open-Meteo (free, no API key, no account).
/// Only the city name the user typed (for lookup) and its coordinates are sent.
final class WeatherService {
    static let shared = WeatherService()

    var onChange: ((WeatherKind) -> Void)?
    private(set) var lastSummary: String?
    private var timer: Timer?

    var isFollowing: Bool { Settings.shared.cityName != nil }

    func start() {
        guard isFollowing else { return }
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        Settings.shared.cityName = nil
        lastSummary = nil
    }

    func follow(city: String, completion: @escaping (Result<String, Error>) -> Void) {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1")]
        fetchJSON(c.url!) { json in
            guard let r = (json?["results"] as? [[String: Any]])?.first,
                  let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else {
                completion(.failure(NSError(domain: "SnowDesk", code: 1,
                                            userInfo: [NSLocalizedDescriptionKey: "Couldn't find a place called “\(city)”."])))
                return
            }
            let name = [r["name"] as? String, r["country"] as? String].compactMap { $0 }.joined(separator: ", ")
            Settings.shared.cityName = name
            Settings.shared.cityLat = lat
            Settings.shared.cityLon = lon
            self.start()
            completion(.success(name))
        }
    }

    func refresh() {
        let s = Settings.shared
        guard let name = s.cityName else { return }
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [.init(name: "latitude", value: String(s.cityLat)),
                        .init(name: "longitude", value: String(s.cityLon)),
                        .init(name: "current", value: "weather_code,is_day")]
        fetchJSON(c.url!) { json in
            guard Settings.shared.cityName == name,
                  let cur = json?["current"] as? [String: Any], let code = cur["weather_code"] as? Int else { return }
            let day = (cur["is_day"] as? Int ?? 1) == 1
            let month = Calendar.current.component(.month, from: Date())
            let kind = WeatherService.kind(code: code, isDay: day, lat: s.cityLat, month: month)
            self.lastSummary = "\(name): \(kind.title)"
            self.onChange?(kind)
        }
    }

    /// WMO weather code → one of our scenes. Clear skies pick a seasonal scene.
    static func kind(code: Int, isDay: Bool, lat: Double, month: Int) -> WeatherKind {
        switch code {
        case 71...77, 85, 86: return .snow
        case 95...99: return .storm
        case 51...67, 80...82: return .rain
        case 45, 48: return .mist
        case 2, 3: return .cloud
        default:
            let north = lat >= 0
            let spring = north ? (3...5).contains(month) : (9...11).contains(month)
            let summer = north ? (6...8).contains(month) : [12, 1, 2].contains(month)
            let autumn = north ? (9...11).contains(month) : (3...5).contains(month)
            if !isDay { return summer ? .fireflies : .meteors }
            if autumn { return .leaves }
            if spring { return .petals }
            return .clear
        }
    }

    private func fetchJSON(_ url: URL, _ done: @escaping ([String: Any]?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async { done(json) }
        }.resume()
    }
}
