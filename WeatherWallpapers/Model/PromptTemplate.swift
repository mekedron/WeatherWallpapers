import Foundation

/// A reusable prompt template for variant generation. The text can reference
/// placeholders that are filled in for each of the 120 variants:
/// - `{time}` / `{weather}` — the detailed lighting and weather prompt modules,
/// - `{time_name}` / `{weather_name}` — plain English labels ("Sunset", "Heavy Rain").
///
/// Built-in presets live in code and can't be edited or deleted; user templates
/// are stored as `prompts.json` in the storage root and sync via iCloud Drive.
struct PromptTemplate: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    /// Short description shown in pickers and the library.
    var summary: String
    /// Prompt body with placeholders.
    var text: String
    /// Extra instructions applied only to specific weather conditions,
    /// keyed by `WeatherCondition` rawValue. nil/absent for most templates.
    var weatherNotes: [String: String]?
    /// Extra instructions applied only to specific times of day,
    /// keyed by `TimeOfDay` rawValue.
    var timeNotes: [String: String]?

    var isBuiltIn: Bool { Self.builtIn(id: id) != nil }

    /// Fills the placeholders for one variant and appends the
    /// weather/time-specific notes when set for its condition.
    func render(for variant: WallpaperVariant) -> String {
        var result = text
            .replacingOccurrences(of: "{time}", with: variant.time.promptModule)
            .replacingOccurrences(of: "{weather}", with: variant.weather.promptModule)
            .replacingOccurrences(of: "{time_name}", with: variant.time.englishLabel)
            .replacingOccurrences(of: "{weather_name}", with: variant.weather.englishLabel)
        if let note = trimmedNote(weatherNotes?[variant.weather.rawValue]) {
            result += " For \(variant.weather.englishLabel) weather specifically: \(note)"
        }
        if let note = trimmedNote(timeNotes?[variant.time.rawValue]) {
            result += " For \(variant.time.englishLabel.lowercased()) specifically: \(note)"
        }
        return result
    }

    private func trimmedNote(_ note: String?) -> String? {
        guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

// MARK: - Validation

extension PromptTemplate {
    static let knownPlaceholders: Set<String> = ["time", "weather", "time_name", "weather_name"]

    /// `{tokens}` in the text that won't be substituted — almost always typos
    /// ("{wether}") that would be sent to the model literally.
    var unknownPlaceholders: [String] {
        let matches = text.matches(of: #/\{([a-zA-Z_]+)\}/#)
        var seen = Set<String>()
        return matches.compactMap { match in
            let token = String(match.1)
            guard !Self.knownPlaceholders.contains(token), seen.insert(token).inserted else { return nil }
            return token
        }
    }

    /// Without a weather placeholder all 120 variants come out nearly identical.
    var mentionsWeather: Bool {
        text.contains("{weather}") || text.contains("{weather_name}")
    }

    /// Without a time placeholder the four times of day look the same.
    var mentionsTime: Bool {
        text.contains("{time}") || text.contains("{time_name}")
    }
}

// MARK: - Built-in presets

extension PromptTemplate {
    static let defaultID = "builtin.classic"

    /// The non-deletable default: sets that never chose a template use this.
    static var defaultTemplate: PromptTemplate { presets[0] }

    static func builtIn(id: String) -> PromptTemplate? {
        presets.first { $0.id == id }
    }

    static let presets: [PromptTemplate] = [
        PromptTemplate(
            id: defaultID,
            name: String(localized: "Classic"),
            summary: String(localized: "The weather transforms the whole scene while the composition and style stay recognizable."),
            text: """
            Change the time of day and the weather of this image. \
            The time of day: {time}. \
            The weather: {weather}. \
            Let the weather visibly transform the entire scene: the sky, the lighting, the color palette and \
            every surface should respond to it — a wet sheen in rain, snow settling over surfaces in snowfall, \
            mist softening the distance in fog. \
            Keep the composition and all key elements of the original image recognizable and in their places, \
            and stay true to the original artistic style, technique and level of detail.
            """
        ),
        PromptTemplate(
            id: "builtin.character",
            name: String(localized: "Character Scene"),
            summary: String(localized: "For images with a hero: the character reacts to the weather with clothing, pose and mood."),
            text: """
            Change the time of day and the weather of this image. \
            The time of day: {time}. \
            The weather: {weather}. \
            The main character must stay recognizably the same — identical face, hairstyle, body proportions \
            and overall design — and remain in the same spot of the composition, but let them react naturally \
            to the conditions: weather-appropriate clothing (a warm coat, scarf and visible breath in cold \
            weather, an umbrella or raincoat in the rain, light clothes in warm clear weather), and a matching \
            pose, expression and mood (sheltering from storms, sleepy and cozy at night, energetic in bright \
            daylight). Preserve the original artistic style, technique, color language and level of detail exactly.
            """
        ),
        PromptTemplate(
            id: "builtin.living-world",
            name: String(localized: "Living World"),
            summary: String(localized: "Keeps the scene intact but adds small signs of life that match the weather."),
            text: """
            Change the time of day and the weather of this image. \
            The time of day: {time}. \
            The weather: {weather}. \
            Keep the composition and all major elements of the original image in place, but you may add small, \
            subtle, weather-appropriate signs of life: birds riding the wind, gentle puddle reflections in the \
            rain, warm glowing windows and soft street lights at night, fresh footprints in snow, butterflies \
            or drifting petals on clear warm days. Keep these touches minimal so the image stays a clean \
            wallpaper. Preserve the original artistic style, technique, color language and level of detail exactly.
            """
        ),
        PromptTemplate(
            id: "builtin.cinematic",
            name: String(localized: "Cinematic"),
            summary: String(localized: "Dramatic, movie-still lighting and atmosphere."),
            text: """
            Change the time of day and the weather of this image and light it like a dramatic cinematic movie still. \
            The time of day: {time}. \
            The weather: {weather}. \
            Emphasize volumetric light, atmospheric depth and a tasteful filmic color grade that suits \
            {weather_name} at {time_name}, with strong but controlled contrast. \
            Keep the exact composition and every element of the original image in place, and preserve the \
            original artistic style, technique and level of detail.
            """
        ),
        PromptTemplate(
            id: "builtin.seasonal",
            name: String(localized: "Seasonal Shift"),
            summary: String(localized: "Vegetation and landscape shift season to match the weather."),
            text: """
            Change the time of day, the weather and the season of this image so they feel coherent together. \
            The time of day: {time}. \
            The weather: {weather}. \
            Let the vegetation and landscape follow the weather: snow and frost turn the scene into deep winter \
            with bare or snow-covered branches, hot clear weather feels like lush high summer, rain and wind may \
            bring moody autumn colors and falling leaves. \
            Keep the composition, all major elements and any characters in place, and preserve the original \
            artistic style, technique and level of detail.
            """
        ),
        PromptTemplate(
            id: "builtin.photoreal",
            name: String(localized: "Photoreal Weather"),
            summary: String(localized: "Renders the sky and weather effects with photographic realism."),
            text: """
            Change the time of day and the weather of this image, rendering the sky, lighting and weather \
            effects with photographic realism — physically plausible light, believable clouds, rain, snow or \
            fog with natural density and falloff. \
            The time of day: {time}. \
            The weather: {weather}. \
            Keep the exact composition and every element of the original image in place, and keep the subjects \
            themselves in the original artistic style so the artwork remains recognizable.
            """
        ),
        PromptTemplate(
            id: "builtin.dreamy",
            name: String(localized: "Dreamy Pastel"),
            summary: String(localized: "Soft, calm, pastel take on the weather — peaceful even in storms."),
            text: """
            Change the time of day and the weather of this image with a soft, dreamy, calming mood. \
            The time of day: {time}. \
            The weather: {weather}. \
            Render the weather gently: soft pastel gradients in the sky, delicate haze, smooth diffused light \
            and no harsh contrast, so the wallpaper feels peaceful even in storms. \
            Keep the exact composition and every element of the original image in place, and preserve the \
            original artistic style, technique and level of detail.
            """
        ),
    ]
}
