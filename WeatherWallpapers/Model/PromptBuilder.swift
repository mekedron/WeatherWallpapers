import Foundation

enum PromptBuilder {
    /// Builds the image-edit prompt for one variant, following the modular blueprint:
    /// time-of-day lighting module + weather condition module + style preservation rules.
    static func editPrompt(for variant: WallpaperVariant, extraInstructions: String? = nil) -> String {
        var prompt = """
        Change the time of day and the weather of this image. \
        The time of day: \(variant.time.promptModule). \
        The weather: \(variant.weather.promptModule). \
        Keep the exact composition and every element of the original image in place. \
        Preserve the original artistic style, technique, color language and level of detail exactly. \
        Do not write any text, labels, filenames, or watermarks on the image.
        """
        if let extraInstructions, !extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += " Additional instructions: \(extraInstructions)"
        }
        return prompt
    }
}
