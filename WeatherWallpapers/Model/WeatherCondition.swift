import Foundation

/// The 30 weather conditions matching Apple Weather condition set.
enum WeatherCondition: String, CaseIterable, Codable, Identifiable, Hashable {
    case clear
    case mostlyClear = "mostly_clear"
    case partlyCloudy = "partly_cloudy"
    case mostlyCloudy = "mostly_cloudy"
    case cloudy
    case foggy
    case haze
    case smoky
    case blowingDust = "blowing_dust"
    case breezy
    case windy
    case drizzle
    case rain
    case heavyRain = "heavy_rain"
    case isolatedThunderstorms = "isolated_thunderstorms"
    case scatteredThunderstorms = "scattered_thunderstorms"
    case strongStorms = "strong_storms"
    case thunderstorms
    case flurries
    case snow
    case heavySnow = "heavy_snow"
    case sleet
    case freezingDrizzle = "freezing_drizzle"
    case freezingRain = "freezing_rain"
    case frigid
    case hail
    case hot
    case tornado
    case tropicalStorm = "tropical_storm"
    case hurricane

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
        case .haze: return "Haze"
        case .smoky: return "Smoky"
        case .blowingDust: return "Blowing Dust"
        case .breezy: return "Breezy"
        case .windy: return "Windy"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .heavyRain: return "Heavy Rain"
        case .isolatedThunderstorms: return "Isolated Thunderstorms"
        case .scatteredThunderstorms: return "Scattered Thunderstorms"
        case .strongStorms: return "Strong Storms"
        case .thunderstorms: return "Thunderstorms"
        case .flurries: return "Flurries"
        case .snow: return "Snow"
        case .heavySnow: return "Heavy Snow"
        case .sleet: return "Sleet"
        case .freezingDrizzle: return "Freezing Drizzle"
        case .freezingRain: return "Freezing Rain"
        case .frigid: return "Frigid"
        case .hail: return "Hail"
        case .hot: return "Hot"
        case .tornado: return "Tornado"
        case .tropicalStorm: return "Tropical Storm"
        case .hurricane: return "Hurricane"
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
        case .cloudy: return "smoke"
        case .foggy: return "cloud.fog"
        case .haze: return "sun.haze"
        case .smoky: return "smoke.fill"
        case .blowingDust: return "sun.dust"
        case .breezy: return "wind"
        case .windy: return "wind"
        case .drizzle: return "cloud.drizzle"
        case .rain: return "cloud.rain"
        case .heavyRain: return "cloud.heavyrain"
        case .isolatedThunderstorms: return "cloud.bolt"
        case .scatteredThunderstorms: return "cloud.bolt.rain"
        case .strongStorms: return "cloud.bolt.rain.fill"
        case .thunderstorms: return "cloud.bolt.rain"
        case .flurries: return "cloud.snow"
        case .snow: return "snowflake"
        case .heavySnow: return "cloud.snow.fill"
        case .sleet: return "cloud.sleet"
        case .freezingDrizzle: return "cloud.hail"
        case .freezingRain: return "cloud.hail.fill"
        case .frigid: return "thermometer.snowflake"
        case .hail: return "cloud.hail"
        case .hot: return "thermometer.sun.fill"
        case .tornado: return "tornado"
        case .tropicalStorm: return "hurricane"
        case .hurricane: return "hurricane"
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
        case .haze:
            return "a warm, soft, dry atmospheric haze in the air, creating dreamlike soft-focus contours and giving the light a diffused quality"
        case .smoky:
            return "a thick, dark charcoal-orange smoke and heavy smog filling the air, with a dim, diffused sun or moon glowing faintly through, creating a dramatic, hazy air quality effect"
        case .blowingDust:
            return "a dry, dusty wind whipping fine sand and orange-brown dust across the scene, partially obscuring the distance in a warm, dusty windstorm"
        case .breezy:
            return "a soft, gentle wind blowing clouds across the sky with light motion trails, and vegetation gently swaying"
        case .windy:
            return "a strong, powerful wind sweeping across the scene, with vegetation bending dramatically in one direction, and wind-blown clouds rushing across the sky"
        case .drizzle:
            return "a light, misty drizzle falling from a soft gray sky, adding a subtle wet gloss and reflective highlights to surfaces"
        case .rain:
            return "a soft, gentle rainy atmosphere with a quiet overcast sky, casting a damp light that deepens the colors, with a subtle wet sheen on surfaces, entirely avoiding any sharp or distinct vertical rain lines or streaks"
        case .heavyRain:
            return "a dramatic, intense heavy rainstorm under a dark purple-gray stormy sky, with broad, soft, semi-transparent slanting sheets of rain rushing across the entire scene, heavily obscuring the distance in a dense, misty gray shroud of water"
        case .isolatedThunderstorms:
            return "a dark, stormy sky with a single localized, active thunderstorm cell and isolated lightning bolts striking far off in the distance, while the rest of the sky has softer clouds"
        case .scatteredThunderstorms:
            return "multiple scattered, dark storm clouds in the sky, with several lightning bolts discharging in different directions, casting a mix of intense highlights and heavy shadows"
        case .strongStorms:
            return "a highly violent, swirling storm sky with sheets of torrential rain, powerful gales of wind, and multiple blinding lightning bolts striking the ground"
        case .thunderstorms:
            return "a dramatic, heavy, dark purple-gray thunderous sky with bright lightning bolts striking in the distance, casting sudden cool highlights across the scene"
        case .flurries:
            return "a very light dusting of snow, with soft, sparse, gentle snowflakes drifting down, and light white frost highlights on surfaces"
        case .snow:
            return "a peaceful winter scene with the ground and distant elements beautifully blanketed in clean white snow, with soft snowflakes falling"
        case .heavySnow:
            return "a heavy, thick blizzard with the entire scene blanketed in deep snow, and heavy swirls of white blowing snow obscuring the background in a winter tempest"
        case .sleet:
            return "a chilly gray sky with sleet and freezing slush falling, creating a cold, wet, half-rain half-snow mixture with melting slush on surfaces"
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
        case .tornado:
            return "a spectacular and dramatic dark tornado funnel visible in the far distance touching down, under a churning, swirling dark sky"
        case .tropicalStorm:
            return "severe tropical storm gale-force winds, with dark swirling clouds and heavy slanting sheets of rain"
        case .hurricane:
            return "an extreme hurricane tempest with dark spiraling wall-clouds, torrential horizontal rain, and violent winds sweeping across the scene"
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
        case .haze: return .foggy
        case .smoky: return .haze
        case .blowingDust: return .windy
        case .breezy: return .partlyCloudy
        case .windy: return .breezy
        case .drizzle: return .cloudy
        case .rain: return .drizzle
        case .heavyRain: return .rain
        case .isolatedThunderstorms: return .thunderstorms
        case .scatteredThunderstorms: return .thunderstorms
        case .strongStorms: return .thunderstorms
        case .thunderstorms: return .heavyRain
        case .flurries: return .cloudy
        case .snow: return .flurries
        case .heavySnow: return .snow
        case .sleet: return .snow
        case .freezingDrizzle: return .drizzle
        case .freezingRain: return .sleet
        case .frigid: return .clear
        case .hail: return .thunderstorms
        case .hot: return .clear
        case .tornado: return .strongStorms
        case .tropicalStorm: return .strongStorms
        case .hurricane: return .tropicalStorm
        }
    }
}
