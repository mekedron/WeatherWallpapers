import Foundation

/// Token counts and estimated USD cost of a single AI API call, as reported
/// by the provider's response (or its fixed price list).
struct APICallUsage: Sendable {
    var provider: String
    var inputTokens: Int?
    var outputTokens: Int?
    /// USD, estimated from the provider's published prices.
    var cost: Double

    /// Sums two usages — used to fold billed-but-failed retries into the
    /// final attempt of the same logical request.
    static func merge(_ lhs: APICallUsage?, _ rhs: APICallUsage?) -> APICallUsage? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        func add(_ a: Int?, _ b: Int?) -> Int? {
            a == nil && b == nil ? nil : (a ?? 0) + (b ?? 0)
        }
        return APICallUsage(
            provider: rhs.provider,
            inputTokens: add(lhs.inputTokens, rhs.inputTokens),
            outputTokens: add(lhs.outputTokens, rhs.outputTokens),
            cost: lhs.cost + rhs.cost
        )
    }
}

/// Published API prices in USD (as of July 2026) used to estimate costs.
/// Stability doesn't report usage in the response, so its price is flat.
enum ProviderPricing {
    /// Gemini 2.5 Flash Image, per 1M tokens.
    static let geminiInputPerMTok = 0.30
    static let geminiOutputPerMTok = 30.0
    /// OpenAI gpt-image-1, per 1M tokens.
    static let openAITextInputPerMTok = 5.0
    static let openAIImageInputPerMTok = 10.0
    static let openAIOutputPerMTok = 40.0
    /// Stability Fast Upscaler: 2 credits × $0.01 per call.
    static let stabilityFastUpscale = 0.02
}

/// One billable AI API call, persisted in `usage.json` inside the set folder.
struct UsageRecord: Codable, Hashable, Identifiable {
    enum Category: String, Codable, CaseIterable {
        /// Original artwork (text → image), including discarded regenerations.
        case sourceImage
        /// One of the 120 weather/time edits.
        case variantImage
        /// AI upscaling pass.
        case upscale

        var localizedName: String {
            switch self {
            case .sourceImage: String(localized: "Source Image")
            case .variantImage: String(localized: "Variants")
            case .upscale: String(localized: "Upscaling")
            }
        }
    }

    var id: UUID
    var date: Date
    var provider: String
    var category: Category
    /// Variant base name ("Rain Night"); nil for the source image.
    var variant: String?
    var inputTokens: Int?
    var outputTokens: Int?
    /// USD, estimated from the price list at the time of the call.
    var cost: Double
    /// The call was billed but produced no image.
    var failed: Bool?

    init(date: Date = Date(), category: Category, variant: String? = nil, usage: APICallUsage, failed: Bool = false) {
        self.id = UUID()
        self.date = date
        self.provider = usage.provider
        self.category = category
        self.variant = variant
        self.inputTokens = usage.inputTokens
        self.outputTokens = usage.outputTokens
        self.cost = usage.cost
        self.failed = failed ? true : nil
    }
}

/// Every billable API call made for one wallpaper set (`usage.json`).
struct UsageLedger: Codable, Hashable {
    var records: [UsageRecord] = []

    static let fileName = "usage.json"

    var totalCost: Double { records.reduce(0) { $0 + $1.cost } }
    var totalInputTokens: Int { records.reduce(0) { $0 + ($1.inputTokens ?? 0) } }
    var totalOutputTokens: Int { records.reduce(0) { $0 + ($1.outputTokens ?? 0) } }
    var totalTokens: Int { totalInputTokens + totalOutputTokens }
    var failedCount: Int { records.filter { $0.failed == true }.count }

    func records(variant: String) -> [UsageRecord] {
        records.filter { $0.variant == variant }
    }

    func records(category: UsageRecord.Category) -> [UsageRecord] {
        records.filter { $0.category == category }
    }

    /// Provider IDs in order of first appearance.
    var providerIDs: [String] {
        var seen = Set<String>()
        return records.compactMap { seen.insert($0.provider).inserted ? $0.provider : nil }
    }

    func records(provider: String) -> [UsageRecord] {
        records.filter { $0.provider == provider }
    }
}

extension [UsageRecord] {
    var totalCost: Double { reduce(0) { $0 + $1.cost } }
    var totalInputTokens: Int { reduce(0) { $0 + ($1.inputTokens ?? 0) } }
    var totalOutputTokens: Int { reduce(0) { $0 + ($1.outputTokens ?? 0) } }
    var totalTokens: Int { totalInputTokens + totalOutputTokens }
}

/// Serializes appends to per-set usage ledgers across concurrent generation jobs.
actor UsageLedgerStore {
    static let shared = UsageLedgerStore()

    func append(_ records: [UsageRecord], folderURL: URL) {
        guard !records.isEmpty else { return }
        var ledger = WallpaperFileSystem.loadLedger(folderURL: folderURL)
        ledger.records.append(contentsOf: records)
        try? WallpaperFileSystem.saveLedger(ledger, in: folderURL)
    }
}

enum UsageFormat {
    /// "$0.039" below a dollar, "$4.83" above.
    static func cost(_ value: Double) -> String {
        value < 0.9995 && value != 0
            ? String(format: "$%.3f", value)
            : String(format: "$%.2f", value)
    }

    /// "842", "12.5K", "1.20M".
    static func tokens(_ value: Int) -> String {
        switch value {
        case ..<1000: String(value)
        case ..<1_000_000: String(format: "%.1fK", Double(value) / 1000)
        default: String(format: "%.2fM", Double(value) / 1_000_000)
        }
    }

    static func fileSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
