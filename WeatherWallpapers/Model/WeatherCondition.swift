import Foundation

/// The 24 weather conditions our data source (Open-Meteo/WMO codes, refined
/// with cloud cover, wind and daylight) can actually distinguish. Named and
/// worded to match Apple Weather's own condition set where they overlap.
enum WeatherCondition: String, CaseIterable, Codable, Identifiable, Hashable {
    case clear
    case mostlyClear = "mostly_clear"
    case partlyCloudy = "partly_cloudy"
    case mostlyCloudy = "mostly_cloudy"
    case cloudy
    case foggy
    case breezy
    case windy
    case drizzle
    case rain
    case sunShowers = "sun_showers"
    case heavyRain = "heavy_rain"
    case thunderstorms
    case flurries
    case sunFlurries = "sun_flurries"
    case snow
    case heavySnow = "heavy_snow"
    case blowingSnow = "blowing_snow"
    case blizzard
    case freezingDrizzle = "freezing_drizzle"
    case freezingRain = "freezing_rain"
    case frigid
    case hail
    case hot

    var id: String { rawValue }

    /// English label, used for canonical file names ("Partly Cloudy Night.png").
    var englishLabel: String {
        switch self {
        case .clear: return "Clear"
        case .mostlyClear: return "Mostly Clear"
        case .partlyCloudy: return "Partly Cloudy"
        case .mostlyCloudy: return "Mostly Cloudy"
        case .cloudy: return "Cloudy"
        case .foggy: return "Foggy"
        case .breezy: return "Breezy"
        case .windy: return "Windy"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .sunShowers: return "Sun Showers"
        case .heavyRain: return "Heavy Rain"
        case .thunderstorms: return "Thunderstorms"
        case .flurries: return "Flurries"
        case .sunFlurries: return "Sun Flurries"
        case .snow: return "Snow"
        case .heavySnow: return "Heavy Snow"
        case .blowingSnow: return "Blowing Snow"
        case .blizzard: return "Blizzard"
        case .freezingDrizzle: return "Freezing Drizzle"
        case .freezingRain: return "Freezing Rain"
        case .frigid: return "Frigid"
        case .hail: return "Hail"
        case .hot: return "Hot"
        }
    }

    var localizedName: String {
        String(localized: String.LocalizationValue(englishLabel))
    }

    var symbolName: String {
        switch self {
        case .clear: return "sun.max"
        case .mostlyClear: return "sun.min"
        case .partlyCloudy: return "cloud.sun"
        case .mostlyCloudy: return "cloud"
        case .cloudy: return "cloud.fill"
        case .foggy: return "cloud.fog"
        case .breezy: return "wind"
        case .windy: return "wind"
        case .drizzle: return "cloud.drizzle"
        case .rain: return "cloud.rain"
        case .sunShowers: return "cloud.sun.rain"
        case .heavyRain: return "cloud.heavyrain"
        case .thunderstorms: return "cloud.bolt.rain"
        case .flurries: return "cloud.snow"
        case .sunFlurries: return "sun.snow"
        case .snow: return "snowflake"
        case .heavySnow: return "cloud.snow.fill"
        case .blowingSnow: return "wind.snow"
        case .blizzard: return "wind.snow"
        case .freezingDrizzle: return "cloud.hail"
        case .freezingRain: return "cloud.hail.fill"
        case .frigid: return "thermometer.snowflake"
        case .hail: return "cloud.hail"
        case .hot: return "thermometer.sun.fill"
        }
    }

    /// Weather description appended to the generation prompt.
    var promptModule: String {
        switch self {
        case .clear:
            return "a clean, completely clear sky, letting the natural ambient light cast clear, realistic soft shadows"
        case .mostlyClear:
            return "a bright sky with only a few tiny, wispy, soft clouds drifting high up"
        case .partlyCloudy:
            return "a beautiful scattering of soft, fluffy, white painterly clouds across the sky"
        case .mostlyCloudy:
            return "thick, layered painterly clouds covering most of the sky, with small openings letting dramatic beams of light filter through"
        case .cloudy:
            return "a fully cloudy and overcast sky covered in thick, soft, gray and white layered clouds, casting diffuse, shadowless ambient light"
        case .foggy:
            return "dense, atmospheric, mysterious fog drifting low across the scene, softening the foreground and making distant elements fade gracefully into the misty white air"
        case .breezy:
            return "a soft, gentle wind blowing clouds across the sky with light motion trails, and vegetation gently swaying"
        case .windy:
            return "a strong, powerful wind sweeping across the scene, with vegetation bending dramatically in one direction, and wind-blown clouds rushing across the sky"
        case .drizzle:
            return "a light, misty drizzle falling from a soft gray sky, adding a subtle wet gloss and reflective highlights to surfaces"
        case .rain:
            return "a soft, gentle rainy atmosphere with a quiet overcast sky, casting a damp light that deepens the colors, with a subtle wet sheen on surfaces, entirely avoiding any sharp or distinct vertical rain lines or streaks"
        case .sunShowers:
            return "bright, warm sunlight breaking through scattered clouds while a light rain falls at the same time, sunlit raindrops glinting on wet surfaces under clear golden light, entirely avoiding any sharp or distinct vertical rain lines or streaks"
        case .heavyRain:
            return "a dramatic, intense heavy rainstorm under a dark purple-gray stormy sky, with broad, soft, semi-transparent slanting sheets of rain rushing across the entire scene, heavily obscuring the distance in a dense, misty gray shroud of water"
        case .thunderstorms:
            return "a dramatic, heavy, dark purple-gray thunderous sky with bright lightning bolts striking in the distance, casting sudden cool highlights across the scene"
        case .flurries:
            return "a very light dusting of snow, with soft, sparse, gentle snowflakes drifting down, and light white frost highlights on surfaces"
        case .sunFlurries:
            return "a very light dusting of snow drifting down through bright, direct sunlight, delicate snowflakes sparkling as they catch the light against a mostly clear sky"
        case .snow:
            return "a peaceful winter scene with the ground and distant elements beautifully blanketed in clean white snow, with soft snowflakes falling"
        case .heavySnow:
            return "a heavy, thick blizzard with the entire scene blanketed in deep snow, and heavy swirls of white blowing snow obscuring the background in a winter tempest"
        case .blowingSnow:
            return "a strong wind lifting and sweeping loose snow low across the ground in swirling, hazy streams, partially obscuring the lower part of the scene while the sky above stays comparatively clear"
        case .blizzard:
            return "an extreme, blinding blizzard with violent gale-force winds driving thick, swirling snow sideways across the scene, near-white-out visibility, and deep drifting snowdrifts building up against every surface"
        case .freezingDrizzle:
            return "a cold, dreary overcast sky with a fine freezing mist, and a delicate, soft winter frost gently highlighting contours with flat, matte-white touches, without any shiny, glossy, or high-contrast reflections"
        case .freezingRain:
            return "a quiet, freezing atmosphere under a cold overcast sky, with a subtle matte ice glaze covering the scene, represented with soft, flat-painted white highlights, avoiding any vertical rain streaks or shiny, reflective gloss"
        case .frigid:
            return "an intense, serene cold under a clear frozen sky, with a soft, clean dusting of white frost lying gently across the scene, keeping details clean and peaceful"
        case .hail:
            return "dark, high-contrast hail storm clouds with small, white hail pellets bouncing off surfaces"
        case .hot:
            return "a shimmering heat haze rising from the ground, giving the air a parched, heavy, warm-toned quality under a bright, blazing light"
        }
    }

    /// A slightly milder condition to fall back to when a wallpaper file is missing.
    var fallback: WeatherCondition? {
        switch self {
        case .clear: return nil
        case .mostlyClear: return .clear
        case .partlyCloudy: return .mostlyClear
        case .mostlyCloudy: return .partlyCloudy
        case .cloudy: return .mostlyCloudy
        case .foggy: return .cloudy
        case .breezy: return .partlyCloudy
        case .windy: return .breezy
        case .drizzle: return .cloudy
        case .rain: return .drizzle
        case .sunShowers: return .rain
        case .heavyRain: return .rain
        case .thunderstorms: return .heavyRain
        case .flurries: return .cloudy
        case .sunFlurries: return .flurries
        case .snow: return .flurries
        case .heavySnow: return .snow
        case .blowingSnow: return .heavySnow
        case .blizzard: return .blowingSnow
        case .freezingDrizzle: return .drizzle
        case .freezingRain: return .freezingDrizzle
        case .frigid: return .clear
        case .hail: return .thunderstorms
        case .hot: return .clear
        }
    }
}
