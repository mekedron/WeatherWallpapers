import Foundation

/// An image-generation backend (OpenAI, Nano Banana, …).
protocol ImageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// Where the user can create an API key.
    var apiKeyURL: URL { get }

    /// Text → image, for creating the source artwork.
    func generate(prompt: String, targetSize: CGSize, apiKey: String) async throws -> Data
    /// Image + text → image, for producing the 120 weather/time variants.
    func edit(image: Data, prompt: String, targetSize: CGSize, apiKey: String) async throws -> Data
}

enum ProviderRegistry {
    static let all: [any ImageProvider] = [
        OpenAIProvider(),
        NanoBananaProvider(),
    ]

    static func provider(id: String?) -> (any ImageProvider)? {
        all.first { $0.id == id }
    }

    static let defaultProviderID = NanoBananaProvider().id
}

struct ProviderError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    static func missingKey(providerName: String) -> ProviderError {
        ProviderError(message: String(localized: "No API key for \(providerName). Add it in Settings."))
    }
}

enum ProviderHTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    /// Executes the request and returns the body, converting non-2xx into a readable error.
    static func data(for request: URLRequest, apiErrorMessage: (Data) -> String?) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let message = apiErrorMessage(data) ?? String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw ProviderError(message: "HTTP \(http.statusCode): \(message)")
        }
        return data
    }
}
