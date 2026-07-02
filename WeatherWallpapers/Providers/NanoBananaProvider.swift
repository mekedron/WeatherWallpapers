import Foundation

/// Nano Banana — Google Gemini 2.5 Flash Image.
struct NanoBananaProvider: ImageProvider {
    let id = "nanobanana"
    let displayName = "Nano Banana (Gemini)"
    let apiKeyURL = URL(string: "https://aistudio.google.com/apikey")!

    private let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent")!

    private static let supportedAspects: [(String, Double)] = [
        ("1:1", 1.0), ("2:3", 2.0 / 3.0), ("3:2", 3.0 / 2.0),
        ("3:4", 3.0 / 4.0), ("4:3", 4.0 / 3.0), ("4:5", 4.0 / 5.0),
        ("5:4", 5.0 / 4.0), ("9:16", 9.0 / 16.0), ("16:9", 16.0 / 9.0),
        ("21:9", 21.0 / 9.0),
    ]

    private func aspectRatio(for targetSize: CGSize) -> String {
        guard targetSize.width > 0, targetSize.height > 0 else { return "1:1" }
        let ratio = Double(targetSize.width / targetSize.height)
        return Self.supportedAspects.min { abs($0.1 - ratio) < abs($1.1 - ratio) }!.0
    }

    func generate(prompt: String, targetSize: CGSize, apiKey: String) async throws -> ProviderResult {
        try await request(parts: [["text": prompt]], targetSize: targetSize, apiKey: apiKey)
    }

    func edit(image: Data, prompt: String, targetSize: CGSize, apiKey: String) async throws -> ProviderResult {
        let parts: [[String: Any]] = [
            ["text": prompt],
            ["inlineData": ["mimeType": ImageUtil.mimeType(for: image), "data": image.base64EncodedString()]],
        ]
        return try await request(parts: parts, targetSize: targetSize, apiKey: apiKey)
    }

    /// IMAGE_OTHER failures are often transient (the safety filter fires
    /// nondeterministically on borderline images) — retry a couple of times
    /// before giving up. Failed attempts still bill tokens, so their usage is
    /// folded into whatever this request ultimately returns or throws.
    private func request(parts: [[String: Any]], targetSize: CGSize, apiKey: String) async throws -> ProviderResult {
        var lastError: ProviderError?
        var billedFailures: APICallUsage?
        for attempt in 0..<3 {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000)
            }
            do {
                var result = try await requestOnce(parts: parts, targetSize: targetSize, apiKey: apiKey)
                result.usage = APICallUsage.merge(billedFailures, result.usage)
                return result
            } catch let error as ProviderError where error.message.contains("IMAGE_") {
                billedFailures = APICallUsage.merge(billedFailures, error.usage)
                lastError = error
                continue
            }
        }
        var final = lastError ?? ProviderError(message: String(localized: "The provider returned no image."))
        final.usage = billedFailures
        throw final
    }

    private func usage(from meta: GeminiUsageMetadata?) -> APICallUsage? {
        guard let meta else { return nil }
        let input = meta.promptTokenCount ?? 0
        let output = meta.candidatesTokenCount ?? 0
        return APICallUsage(
            provider: id,
            inputTokens: meta.promptTokenCount,
            outputTokens: meta.candidatesTokenCount,
            cost: Double(input) * ProviderPricing.geminiInputPerMTok / 1_000_000
                + Double(output) * ProviderPricing.geminiOutputPerMTok / 1_000_000
        )
    }

    private struct GeminiUsageMetadata: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
    }

    private func requestOnce(parts: [[String: Any]], targetSize: CGSize, apiKey: String) async throws -> ProviderResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": [
                "imageConfig": ["aspectRatio": aspectRatio(for: targetSize)],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        struct APIError: Decodable {
            struct Inner: Decodable { let message: String }
            let error: Inner
        }
        let data = try await ProviderHTTP.data(for: request) { body in
            (try? JSONDecoder().decode(APIError.self, from: body))?.error.message
        }

        struct Response: Decodable {
            struct Candidate: Decodable {
                let content: Content?
                let finishReason: String?
            }
            struct Content: Decodable { let parts: [Part]? }
            struct Part: Decodable {
                let inlineData: Inline?
                let text: String?
            }
            struct Inline: Decodable { let data: String }
            struct PromptFeedback: Decodable { let blockReason: String? }
            let candidates: [Candidate]?
            let promptFeedback: PromptFeedback?
            let usageMetadata: GeminiUsageMetadata?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let billed = usage(from: decoded.usageMetadata)
        let parts = decoded.candidates?.compactMap { $0.content?.parts }.flatMap { $0 } ?? []
        if let inline = parts.compactMap({ $0.inlineData }).first,
           let image = Data(base64Encoded: inline.data) {
            return ProviderResult(data: image, usage: billed)
        }

        // No image — surface whatever the model said instead, so the failure
        // is actionable (safety blocks, refusals, etc.).
        var details: [String] = []
        let text = parts.compactMap { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { details.append(text) }
        if let reason = decoded.candidates?.first?.finishReason, reason != "STOP" {
            if reason.hasPrefix("IMAGE") || reason == "SAFETY" || reason == "PROHIBITED_CONTENT" {
                details.append(String(localized: "Gemini declined to process this image — this usually happens with photos of people or recognizable copyrighted artwork. Try a different source image or switch the set to the OpenAI provider."))
            }
            details.append("finishReason: \(reason)")
        }
        if let blocked = decoded.promptFeedback?.blockReason {
            details.append("blocked: \(blocked)")
        }
        let suffix = details.isEmpty ? "" : " — " + details.joined(separator: "; ").prefix(400)
        throw ProviderError(message: String(localized: "The provider returned no image.") + suffix, usage: billed)
    }
}
