import Foundation
import Security

/// Image bytes plus the API usage billed to produce them.
struct ProviderResult: Sendable {
    let data: Data
    var usage: APICallUsage?
}

/// An image-generation backend (OpenAI, Nano Banana, …).
protocol ImageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// Where the user can create an API key.
    var apiKeyURL: URL { get }

    /// Text → image, for creating the source artwork.
    func generate(prompt: String, targetSize: CGSize, apiKey: String) async throws -> ProviderResult
    /// Image + text → image, for producing the 96 weather/time variants.
    func edit(image: Data, prompt: String, targetSize: CGSize, apiKey: String) async throws -> ProviderResult
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
    /// Usage billed by the failed call(s) — some providers charge tokens even
    /// when no image comes back (e.g. Gemini safety blocks).
    var usage: APICallUsage? = nil
    var errorDescription: String? { message }

    static func keyUnavailable(providerName: String, reason: KeychainStore.KeyReadError) -> ProviderError {
        switch reason {
        case .notFound(flagWasSet: false):
            return ProviderError(message: String(localized: "No API key for \(providerName). Add it in Settings."))
        case .notFound(flagWasSet: true):
            return ProviderError(message: String(localized: "The \(providerName) API key was saved earlier but is now missing from the Keychain — it may have been removed or hasn't synced via iCloud yet. Re-enter it in Settings."))
        case .failed(let status):
            let detail = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
            return ProviderError(message: String(localized: "Couldn't read the \(providerName) API key from the Keychain: \(detail) (code \(status)). Try re-entering it in Settings."))
        }
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
            let hint: String?
            switch http.statusCode {
            case 401, 403:
                hint = String(localized: "The API key was rejected — check it in Settings.")
            case 429:
                hint = String(localized: "Rate limit or quota exceeded — wait a moment or check your plan and billing.")
            default:
                hint = nil
            }
            let prefix = hint.map { $0 + " " } ?? ""
            throw ProviderError(message: "\(prefix)HTTP \(http.statusCode): \(message)")
        }
        return data
    }
}
