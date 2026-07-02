import Foundation

/// The four times of day a wallpaper set covers.
enum TimeOfDay: String, CaseIterable, Codable, Identifiable, Hashable {
    case sunrise
    case day
    case sunset
    case night

    var id: String { rawValue }

    /// English label, used for canonical file names ("Clear Day.png").
    var englishLabel: String {
        switch self {
        case .sunrise: return "Sunrise"
        case .day: return "Day"
        case .sunset: return "Sunset"
        case .night: return "Night"
        }
    }

    var localizedName: String {
        String(localized: String.LocalizationValue(englishLabel))
    }

    var symbolName: String {
        switch self {
        case .sunrise: return "sunrise.fill"
        case .day: return "sun.max.fill"
        case .sunset: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }

    /// Visually closest times of day, best first — used when a wallpaper
    /// for the exact time is missing.
    var fallbackOrder: [TimeOfDay] {
        switch self {
        case .sunrise: return [.day, .sunset, .night]
        case .day: return [.sunrise, .sunset, .night]
        case .sunset: return [.day, .sunrise, .night]
        case .night: return [.sunset, .sunrise, .day]
        }
    }

    /// Lighting baseline appended to the generation prompt.
    var promptModule: String {
        switch self {
        case .sunrise:
            return "a beautiful warm sunrise gradient of rose and gold, casting soft, warm light across the scene and cool reflections"
        case .day:
            return "a bright, natural daylight sky, casting natural ambient light and crisp, soft realistic shadows across the scene"
        case .sunset:
            return "a brilliant, fiery sunset gradient of orange, crimson, and deep purple-gold, casting long, dramatic warm light across the scene"
        case .night:
            return "a gorgeous deep indigo night sky filled with a scattering of twinkling white stars and a glowing moon, casting a gentle, cool silver moonlight"
        }
    }
}
