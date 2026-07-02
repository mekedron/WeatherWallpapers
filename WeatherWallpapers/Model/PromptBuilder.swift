import Foundation

enum PromptBuilder {
    /// Builds the image-edit prompt for one variant from a prompt template
    /// (the built-in Classic one by default). The no-text rule is appended
    /// outside the template so user templates can't accidentally drop it.
    static func editPrompt(
        for variant: WallpaperVariant,
        template: PromptTemplate? = nil,
        extraInstructions: String? = nil
    ) -> String {
        var prompt = (template ?? .defaultTemplate).render(for: variant)
        prompt += " Do not write any text, labels, filenames, or watermarks on the image."
        if let extraInstructions, !extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += " Additional instructions: \(extraInstructions)"
        }
        return prompt
    }
}
