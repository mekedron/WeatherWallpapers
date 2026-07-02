import Foundation
import UniformTypeIdentifiers

/// OpenAI image generation (gpt-image-1).
struct OpenAIProvider: ImageProvider {
    let id = "openai"
    let displayName = "ChatGPT (OpenAI)"
    let apiKeyURL = URL(string: "https://platform.openai.com/api-keys")!

    private let model = "gpt-image-1"

    /// gpt-image-1 supports a fixed set of output sizes; pick the closest by aspect ratio.
    private func apiSize(for targetSize: CGSize) -> String {
        guard targetSize.width > 0, targetSize.height > 0 else { return "1024x1024" }
        let ratio = targetSize.width / targetSize.height
        if ratio > 1.2 { return "1536x1024" }
        if ratio < 0.84 { return "1024x1536" }
        return "1024x1024"
    }

    func generate(prompt: String, targetSize: CGSize, apiKey: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "size": apiSize(for: targetSize),
            "n": 1,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await imageFromResponse(request: request)
    }

    func edit(image: Data, prompt: String, targetSize: CGSize, apiKey: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        appendField("model", model)
        appendField("prompt", prompt)
        appendField("size", apiSize(for: targetSize))
        appendField("n", "1")

        let mime = ImageUtil.mimeType(for: image)
        let ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? "png"
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"original.\(ext)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mime)\r\n\r\n".utf8))
        body.append(image)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        return try await imageFromResponse(request: request)
    }

    private func imageFromResponse(request: URLRequest) async throws -> Data {
        struct Response: Decodable {
            struct Item: Decodable { let b64_json: String? }
            let data: [Item]
        }
        struct APIError: Decodable {
            struct Inner: Decodable { let message: String }
            let error: Inner
        }
        let data = try await ProviderHTTP.data(for: request) { body in
            (try? JSONDecoder().decode(APIError.self, from: body))?.error.message
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let b64 = decoded.data.first?.b64_json, let image = Data(base64Encoded: b64) else {
            throw ProviderError(message: String(localized: "The provider returned no image."))
        }
        return image
    }
}
