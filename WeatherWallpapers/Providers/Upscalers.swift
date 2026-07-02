import Foundation
import CoreGraphics

/// An upscaling backend. The native one is free and local; AI upscalers
/// reconstruct detail and need their own API key.
protocol UpscaleProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var requiresAPIKey: Bool { get }
    var apiKeyURL: URL? { get }

    /// Returns image data at (or above) the target size. The storage pipeline
    /// does the final exact-fit crop, so overshooting is fine.
    func upscale(_ image: Data, to target: CGSize, apiKey: String?) async throws -> Data
}

enum UpscalerRegistry {
    static let defaultsKey = "upscalerID"

    static let all: [any UpscaleProvider] = [
        NativeUpscaler(),
        StabilityUpscaler(),
    ]

    static var currentID: String {
        UserDefaults.standard.string(forKey: defaultsKey) ?? NativeUpscaler().id
    }

    static func provider(id: String?) -> (any UpscaleProvider)? {
        all.first { $0.id == id }
    }
}

/// Local Lanczos resampling — the exact-fit pass in the storage pipeline
/// already does it, so this provider just passes the data through.
struct NativeUpscaler: UpscaleProvider {
    let id = "native"
    let displayName = String(localized: "Native (Lanczos)")
    let requiresAPIKey = false
    let apiKeyURL: URL? = nil

    func upscale(_ image: Data, to target: CGSize, apiKey: String?) async throws -> Data {
        image
    }
}

/// Stability AI Fast Upscaler — 4× AI upscale with a single synchronous call.
struct StabilityUpscaler: UpscaleProvider {
    let id = "stability"
    let displayName = String(localized: "Stability AI (4×)")
    let requiresAPIKey = true
    let apiKeyURL: URL? = URL(string: "https://platform.stability.ai/account/keys")

    private let endpoint = URL(string: "https://api.stability.ai/v2beta/stable-image/upscale/fast")!

    func upscale(_ image: Data, to target: CGSize, apiKey: String?) async throws -> Data {
        guard let apiKey, !apiKey.isEmpty else {
            throw ProviderError.missingKey(providerName: "Stability AI")
        }
        // The fast upscaler accepts up to ~1 MP of input.
        let prepared = ImageUtil.limited(toMegapixels: 1.0, data: image)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"input.png\"\r\n".utf8))
        body.append(Data("Content-Type: \(ImageUtil.mimeType(for: prepared))\r\n\r\n".utf8))
        body.append(prepared)
        body.append(Data("\r\n--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"output_format\"\r\n\r\n".utf8))
        body.append(Data("png\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))
        request.httpBody = body

        struct APIError: Decodable {
            let errors: [String]?
            let message: String?
        }
        return try await ProviderHTTP.data(for: request) { data in
            let decoded = try? JSONDecoder().decode(APIError.self, from: data)
            return decoded?.errors?.joined(separator: "; ") ?? decoded?.message
        }
    }
}
