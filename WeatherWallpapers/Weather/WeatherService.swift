import Foundation

/// Current conditions mapped onto the wallpaper grid.
struct CurrentConditions {
    let weather: WeatherCondition
    let time: TimeOfDay
}

/// Fetches current weather from Open-Meteo (free, no API key, no account)
/// and maps WMO weather codes onto the 24 wallpaper conditions.
struct WeatherService {
    func currentConditions(latitude: Double, longitude: Double) async throws -> CurrentConditions {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,cloud_cover,wind_speed_10m,is_day"),
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

        let weather = Self.mapWeather(
            code: decoded.current.weather_code,
            cloudCover: decoded.current.cloud_cover ?? 0,
            windSpeed: decoded.current.wind_speed_10m ?? 0,
            temperature: decoded.current.temperature_2m,
            isDay: decoded.current.is_day == 1
        )
        let time = Self.mapTime(
            now: Date(),
            sunriseString: decoded.daily?.sunrise.first,
            sunsetString: decoded.daily?.sunset.first,
            utcOffsetSeconds: decoded.utc_offset_seconds,
            isDay: decoded.current.is_day == 1
        )
        return CurrentConditions(weather: weather, time: time)
    }

    // MARK: - Mapping

    /// WMO weather interpretation codes → wallpaper conditions, refined with
    /// cloud cover, wind, temperature and daylight for states WMO does not encode.
    static func mapWeather(code: Int, cloudCover: Double, windSpeed: Double, temperature: Double, isDay: Bool) -> WeatherCondition {
        // Sun peeking through while snow or rain still falls — Apple's own
        // "visible sun" definition for these two conditions.
        let sunVisible = isDay && cloudCover < 35

        switch code {
        case 45, 48: return .foggy
        case 51, 53, 55: return .drizzle
        case 56, 57: return .freezingDrizzle
        case 61: return .rain
        case 63: return .rain
        case 65: return .heavyRain
        case 66, 67: return .freezingRain
        case 71, 77:
            if windSpeed >= 50 { return .blizzard }
            if windSpeed >= 29 { return .blowingSnow }
            return sunVisible ? .sunFlurries : .flurries
        case 73:
            if windSpeed >= 50 { return .blizzard }
            if windSpeed >= 29 { return .blowingSnow }
            return .snow
        case 75, 86:
            if windSpeed >= 50 { return .blizzard }
            if windSpeed >= 29 { return .blowingSnow }
            return .heavySnow
        case 80, 81: return sunVisible ? .sunShowers : .rain
        case 82: return .heavyRain
        case 85:
            if windSpeed >= 50 { return .blizzard }
            if windSpeed >= 29 { return .blowingSnow }
            return sunVisible ? .sunFlurries : .flurries
        case 95: return .thunderstorms
        case 96, 99: return .hail
        default:
            break
        }

        // No precipitation (codes 0–3): refine by temperature, wind and clouds.
        if temperature >= 35 { return .hot }
        if temperature <= -15 { return .frigid }
        if windSpeed >= 50 { return .windy }
        if windSpeed >= 29 { return .breezy }

        switch cloudCover {
        case ..<12: return .clear
        case ..<35: return .mostlyClear
        case ..<65: return .partlyCloudy
        case ..<88: return .mostlyCloudy
        default: return .cloudy
        }
    }

    static func mapTime(now: Date, sunriseString: String?, sunsetString: String?, utcOffsetSeconds: Int, isDay: Bool) -> TimeOfDay {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds)
        formatter.locale = Locale(identifier: "en_US_POSIX")

        guard
            let sunriseString, let sunsetString,
            let sunrise = formatter.date(from: sunriseString),
            let sunset = formatter.date(from: sunsetString)
        else {
            return isDay ? .day : .night
        }

        // Golden-hour windows around the actual sunrise/sunset.
        if now >= sunrise.addingTimeInterval(-30 * 60), now <= sunrise.addingTimeInterval(60 * 60) {
            return .sunrise
        }
        if now >= sunset.addingTimeInterval(-60 * 60), now <= sunset.addingTimeInterval(30 * 60) {
            return .sunset
        }
        if now > sunrise, now < sunset {
            return .day
        }
        return .night
    }
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let cloud_cover: Double?
        let wind_speed_10m: Double?
        let is_day: Int
    }
    struct Daily: Decodable {
        let sunrise: [String]
        let sunset: [String]
    }
    let current: Current
    let daily: Daily?
    let utc_offset_seconds: Int
}
