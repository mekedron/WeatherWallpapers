import SwiftUI
import ImageIO

/// "Title — $X" row with a "N calls · M tokens" caption, shared by the
/// budget breakdowns in Settings and the per-set sheet.
struct UsageBreakdownRow: View {
    let title: String
    let records: [UsageRecord]

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(UsageFormat.cost(records.totalCost))
                    .monospacedDigit()
                Text("\(records.count) calls · \(UsageFormat.tokens(records.totalTokens)) tokens")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(title)
        }
    }
}

/// Total spending across every set — a Form section for Settings.
struct GlobalSpendingSection: View {
    let sets: [WallpaperSet]

    private var spendingSets: [WallpaperSet] {
        sets.filter { !$0.usage.records.isEmpty }
    }

    private var records: [UsageRecord] {
        spendingSets.flatMap { $0.usage.records }
    }

    private var providerIDs: [String] {
        var seen = Set<String>()
        return records.compactMap { seen.insert($0.provider).inserted ? $0.provider : nil }
    }

    var body: some View {
        Section {
            if records.isEmpty {
                Text("No billed API calls yet.")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Total Cost", value: UsageFormat.cost(records.totalCost))
                LabeledContent("API Calls", value: "\(records.count)")
                LabeledContent("Tokens", value: "\(UsageFormat.tokens(records.totalInputTokens)) in · \(UsageFormat.tokens(records.totalOutputTokens)) out")

                ForEach(providerIDs, id: \.self) { providerID in
                    UsageBreakdownRow(
                        title: SetBudgetView.providerName(providerID),
                        records: records.filter { $0.provider == providerID }
                    )
                }

                DisclosureGroup("By Set") {
                    ForEach(spendingSets.sorted { $0.usage.totalCost > $1.usage.totalCost }) { set in
                        UsageBreakdownRow(title: set.name, records: set.usage.records)
                    }
                }
            }
        } header: {
            Text("Spending")
        } footer: {
            Text("Estimated from provider price lists and the token usage reported by each API call, across all wallpaper sets on this device.")
        }
    }
}

/// Full generation budget of a set: totals, then breakdowns by category
/// and by provider. Every billed API call is on the books, including
/// failed attempts and discarded regenerations.
struct SetBudgetView: View {
    @Environment(\.dismiss) private var dismiss

    let set: WallpaperSet

    private var ledger: UsageLedger { self.set.usage }

    var body: some View {
        NavigationStack {
            Form {
                Section("Total") {
                    LabeledContent("Cost", value: UsageFormat.cost(ledger.totalCost))
                    LabeledContent("API Calls", value: "\(ledger.records.count)")
                    if ledger.failedCount > 0 {
                        LabeledContent("Failed (billed)", value: "\(ledger.failedCount)")
                    }
                    LabeledContent("Input Tokens", value: UsageFormat.tokens(ledger.totalInputTokens))
                    LabeledContent("Output Tokens", value: UsageFormat.tokens(ledger.totalOutputTokens))
                }

                Section("By Category") {
                    ForEach(UsageRecord.Category.allCases, id: \.self) { category in
                        let records = ledger.records(category: category)
                        if !records.isEmpty {
                            UsageBreakdownRow(title: category.localizedName, records: records)
                        }
                    }
                }

                Section("By Provider") {
                    ForEach(ledger.providerIDs, id: \.self) { providerID in
                        UsageBreakdownRow(
                            title: Self.providerName(providerID),
                            records: ledger.records(provider: providerID)
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Generation Budget")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 460)
        #endif
    }

    static func providerName(_ id: String) -> String {
        ProviderRegistry.provider(id: id)?.displayName
            ?? UpscalerRegistry.provider(id: id)?.displayName
            ?? id
    }
}

/// Everything about one variant image: file facts (size, dimensions, format)
/// and its generation bill (cost, tokens, call history). Presented as a
/// bottom sheet on iPhone and a regular sheet elsewhere.
struct VariantDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    let set: WallpaperSet
    let variant: WallpaperVariant

    @State private var fileSize: Int?
    @State private var pixelSize: CGSize?

    private var records: [UsageRecord] { self.set.usage.records(variant: variant.baseName) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Image") {
                    LabeledContent("Position") {
                        Text(verbatim: "\((WallpaperVariant.all.firstIndex(of: variant) ?? 0) + 1) / \(WallpaperVariant.all.count)")
                    }
                    if let fileName = set.existingFileName(for: variant) {
                        LabeledContent("File", value: fileName)
                        if let fileSize {
                            LabeledContent("Size", value: UsageFormat.fileSize(fileSize))
                        }
                        if let pixelSize {
                            LabeledContent("Dimensions", value: "\(Int(pixelSize.width)) × \(Int(pixelSize.height)) px")
                        }
                    } else {
                        Text("Not generated yet")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Generation") {
                    if records.isEmpty {
                        Text("No billed API calls recorded for this image.")
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Total Cost", value: UsageFormat.cost(records.totalCost))
                        LabeledContent("Tokens", value: "\(UsageFormat.tokens(records.totalInputTokens)) in · \(UsageFormat.tokens(records.totalOutputTokens)) out")
                        LabeledContent("API Calls", value: "\(records.count)")
                    }
                }

                if !records.isEmpty {
                    Section("History") {
                        ForEach(records.sorted { $0.date > $1.date }) { record in
                            historyRow(record)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(variant.localizedTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 460)
        #endif
        .task(id: set.existingFileName(for: variant)) {
            loadFileFacts()
        }
    }

    private func historyRow(_ record: UsageRecord) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(UsageFormat.cost(record.cost))
                    .monospacedDigit()
                if record.inputTokens != nil || record.outputTokens != nil {
                    Text("\(UsageFormat.tokens(record.inputTokens ?? 0)) in · \(UsageFormat.tokens(record.outputTokens ?? 0)) out")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.category.localizedName)
                    if record.failed == true {
                        Text("failed")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.red.opacity(0.2), in: Capsule())
                            .foregroundStyle(.red)
                    }
                }
                Text("\(SetBudgetView.providerName(record.provider)) · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadFileFacts() {
        guard set.hasImage(for: variant) else {
            fileSize = nil
            pixelSize = nil
            return
        }
        let url = set.url(for: variant)
        fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = props[kCGImagePropertyPixelWidth] as? Int,
           let height = props[kCGImagePropertyPixelHeight] as? Int {
            pixelSize = CGSize(width: width, height: height)
        } else {
            pixelSize = nil
        }
    }
}
