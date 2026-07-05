import Foundation

/// One of the 96 weather × time combinations of a wallpaper set.
struct WallpaperVariant: Hashable, Identifiable, Codable {
    let weather: WeatherCondition
    let time: TimeOfDay

    var id: String { "\(weather.rawValue)_\(time.rawValue)" }

    /// Base file name inside a set folder, e.g. "Partly Cloudy Night".
    var baseName: String { "\(weather.englishLabel) \(time.englishLabel)" }

    /// Canonical file name with the default extension.
    var fileName: String { "\(baseName).png" }

    var localizedTitle: String { "\(weather.localizedName) · \(time.localizedName)" }

    /// All 96 variants grouped by weather, times in fixed order.
    static let all: [WallpaperVariant] = WeatherCondition.allCases.flatMap { weather in
        TimeOfDay.allCases.map { WallpaperVariant(weather: weather, time: $0) }
    }

    static func variants(for weather: WeatherCondition) -> [WallpaperVariant] {
        TimeOfDay.allCases.map { WallpaperVariant(weather: weather, time: $0) }
    }
}
