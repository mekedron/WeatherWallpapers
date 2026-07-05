import SwiftUI

/// Library of prompt templates: built-in presets plus the user's own templates.
/// Presets can be viewed and duplicated but never edited or deleted.
struct PromptLibraryView: View {
    @EnvironmentObject private var store: WallpaperStore
    @State private var editing: PromptTemplate?

    var body: some View {
        Form {
            Section {
                ForEach(PromptTemplate.presets) { template in
                    row(template)
                }
            } header: {
                Text("Presets")
            } footer: {
                Text("Presets are built in and can't be changed or deleted. Open one and duplicate it to use as a starting point.")
            }

            Section {
                ForEach(store.customTemplates) { template in
                    row(template)
                }
                Button {
                    editing = PromptTemplate(
                        id: UUID().uuidString,
                        name: "",
                        summary: "",
                        text: PromptTemplate.defaultTemplate.text
                    )
                } label: {
                    Label("New Template", systemImage: "plus")
                }
            } header: {
                Text("My Templates")
            } footer: {
                Text("Templates can use {time}, {weather}, {time_name} and {weather_name} — they are filled in for every generated image.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Prompt Library")
        .sheet(item: $editing) { template in
            PromptTemplateEditor(template: template)
        }
        #if DEBUG
        // Test hook: `-editTemplate <id|new>` opens the editor directly.
        .onAppear {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-editTemplate"),
                  arguments.indices.contains(index + 1) else { return }
            let arg = arguments[index + 1]
            if arg == "new" {
                editing = PromptTemplate(id: UUID().uuidString, name: "", summary: "", text: PromptTemplate.defaultTemplate.text)
            } else {
                editing = PromptTemplate.builtIn(id: arg)
            }
        }
        #endif
    }

    private func row(_ template: PromptTemplate) -> some View {
        Button {
            editing = template
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(template.name)
                    if template.id == PromptTemplate.defaultID {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.tint.opacity(0.15), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                }
                let subtitle = template.summary.isEmpty ? template.text : template.summary
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                duplicate(template)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            if !template.isBuiltIn {
                Button(role: .destructive) {
                    store.deleteTemplate(template)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func duplicate(_ template: PromptTemplate) {
        store.saveTemplate(PromptTemplate(
            id: UUID().uuidString,
            name: String(localized: "\(template.name) Copy"),
            summary: template.summary,
            text: template.text,
            weatherNotes: template.weatherNotes,
            timeNotes: template.timeNotes
        ))
    }
}

// MARK: - Editor

private struct PromptTemplateEditor: View {
    @EnvironmentObject private var store: WallpaperStore
    @Environment(\.dismiss) private var dismiss
    @State var template: PromptTemplate

    // Preview + test target: one variant the user dials in.
    @State private var previewWeather: WeatherCondition = .rain
    @State private var previewTime: TimeOfDay = .sunset

    // Test generation.
    @State private var testSetID: String?
    @State private var isTesting = false
    @State private var testImage: CGImage?
    @State private var testError: String?
    @State private var testCost: String?

    private var isBuiltIn: Bool { template.isBuiltIn }

    var body: some View {
        NavigationStack {
            Form {
                if isBuiltIn {
                    // Read-only view of a preset: plain selectable text, so the
                    // prompt can be copied (disabled editors block selection).
                    Section("Description") {
                        Text(template.summary)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Section {
                        Text(template.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } header: {
                        Text("Prompt")
                    } footer: {
                        placeholdersFooter
                    }
                } else {
                    Section("Name") {
                        TextField("My Prompt Style", text: $template.name)
                            #if os(macOS)
                            .textFieldStyle(.roundedBorder)
                            #endif
                    }
                    Section("Description") {
                        TextField("Optional short description", text: $template.summary)
                            #if os(macOS)
                            .textFieldStyle(.roundedBorder)
                            #endif
                    }
                    Section {
                        PromptTextArea(
                            placeholder: "Change the weather of this image to {weather}…",
                            text: $template.text,
                            minHeight: 160,
                            maxHeight: 320
                        )
                        validationWarnings
                    } header: {
                        Text("Prompt")
                    } footer: {
                        placeholdersFooter
                    }
                    notesSection(
                        title: "Weather-Specific Additions",
                        addLabel: "Add Weather Condition",
                        placeholder: String(localized: "e.g. keep the lightning far away…"),
                        cases: WeatherCondition.allCases.map { ($0.rawValue, $0.localizedName, $0.symbolName) },
                        notes: $template.weatherNotes
                    )
                    notesSection(
                        title: "Time-Specific Additions",
                        addLabel: "Add Time of Day",
                        placeholder: String(localized: "e.g. lit windows and street lamps…"),
                        cases: TimeOfDay.allCases.map { ($0.rawValue, $0.localizedName, $0.symbolName) },
                        notes: $template.timeNotes
                    )
                }
                previewSection
                testSection
            }
            .formStyle(.grouped)
            .navigationTitle(isBuiltIn ? Text(template.name) : Text("Edit Template"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isBuiltIn ? "Close" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isBuiltIn {
                        Button("Duplicate") {
                            store.saveTemplate(duplicateOf(template))
                            dismiss()
                        }
                    } else {
                        Button("Save") {
                            var cleaned = template
                            cleaned.weatherNotes = cleanedNotes(cleaned.weatherNotes)
                            cleaned.timeNotes = cleanedNotes(cleaned.timeNotes)
                            store.saveTemplate(cleaned)
                            dismiss()
                        }
                        .disabled(template.name.trimmingCharacters(in: .whitespaces).isEmpty
                            || template.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear {
                if testSetID == nil {
                    testSetID = store.sets.first { $0.originalFileName != nil }?.id
                }
                #if DEBUG
                // Test hook: `-autoTest` runs a test generation immediately.
                if ProcessInfo.processInfo.arguments.contains("-autoTest"), !isTesting {
                    runTest()
                }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 640)
        #endif
    }

    private var placeholdersFooter: some View {
        Text("Placeholders: {time} and {weather} insert the detailed lighting and weather descriptions, {time_name} and {weather_name} the plain labels (\"Sunset\", \"Heavy Rain\"). The no-text-on-image rule is always appended automatically.")
    }

    private func cleanedNotes(_ notes: [String: String]?) -> [String: String]? {
        let kept = (notes ?? [:]).filter {
            !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return kept.isEmpty ? nil : kept
    }

    private func duplicateOf(_ template: PromptTemplate) -> PromptTemplate {
        PromptTemplate(
            id: UUID().uuidString,
            name: String(localized: "\(template.name) Copy"),
            summary: template.summary,
            text: template.text,
            weatherNotes: template.weatherNotes,
            timeNotes: template.timeNotes
        )
    }

    // MARK: - Validation

    @ViewBuilder
    private var validationWarnings: some View {
        let unknown = template.unknownPlaceholders
        if !unknown.isEmpty {
            warning("Unknown placeholders sent to the model as-is: \(unknown.map { "{\($0)}" }.joined(separator: ", "))")
        }
        if !template.mentionsWeather {
            warning("No {weather} or {weather_name} — all 24 weather conditions will look nearly identical.")
        }
        if !template.mentionsTime {
            warning("No {time} or {time_name} — the four times of day will look nearly identical.")
        }
    }

    private func warning(_ message: String) -> some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Per-condition additions

    /// One section for weather or time-of-day notes: existing rows in
    /// canonical order plus a menu with the remaining conditions.
    private func notesSection(
        title: LocalizedStringKey,
        addLabel: LocalizedStringKey,
        placeholder: String,
        cases: [(key: String, name: String, symbol: String)],
        notes: Binding<[String: String]?>
    ) -> some View {
        Section {
            ForEach(cases.filter { notes.wrappedValue?[$0.key] != nil }, id: \.key) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(item.name, systemImage: item.symbol)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button {
                            notes.wrappedValue?[item.key] = nil
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    TextField(placeholder, text: Binding(
                        get: { notes.wrappedValue?[item.key] ?? "" },
                        set: { notes.wrappedValue?[item.key] = $0 }
                    ))
                    #if os(macOS)
                    .textFieldStyle(.roundedBorder)
                    #endif
                }
                .padding(.vertical, 2)
            }
            Menu {
                ForEach(cases.filter { notes.wrappedValue?[$0.key] == nil }, id: \.key) { item in
                    Button {
                        var updated = notes.wrappedValue ?? [:]
                        updated[item.key] = ""
                        notes.wrappedValue = updated
                    } label: {
                        Label(item.name, systemImage: item.symbol)
                    }
                }
            } label: {
                Label(addLabel, systemImage: "plus")
            }
        } header: {
            Text(title)
        } footer: {
            Text("Appended to the prompt only for the selected conditions.")
        }
    }

    // MARK: - Preview

    private var previewVariant: WallpaperVariant {
        WallpaperVariant(weather: previewWeather, time: previewTime)
    }

    private var previewSection: some View {
        Section {
            Picker("Weather", selection: $previewWeather) {
                ForEach(WeatherCondition.allCases) { weather in
                    Text(weather.localizedName).tag(weather)
                }
            }
            Picker("Time of Day", selection: $previewTime) {
                ForEach(TimeOfDay.allCases) { time in
                    Text(time.localizedName).tag(time)
                }
            }
            Text(PromptBuilder.editPrompt(for: previewVariant, template: template))
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            Text("Preview")
        } footer: {
            Text("The exact prompt that will be sent for this weather and time.")
        }
    }

    // MARK: - Test generation

    private var testSection: some View {
        Section {
            Picker("Test On", selection: $testSetID) {
                Text("Choose a set…").tag(String?.none)
                ForEach(store.sets.filter { $0.originalFileName != nil }) { set in
                    Text(set.name).tag(String?.some(set.id))
                }
            }
            Button {
                runTest()
            } label: {
                if isTesting {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Generating…")
                    }
                } else {
                    Label("Generate Test Image", systemImage: "wand.and.stars")
                }
            }
            .disabled(isTesting || testSetID == nil)
            if let testError {
                Text(testError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let testImage {
                HStack {
                    Spacer()
                    Image(testImage, scale: 1, label: Text("Test image"))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Spacer()
                }
                if let testCost {
                    Text("Cost: \(testCost), recorded in the set's budget.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Try It")
        } footer: {
            Text("Generates one image from the chosen set's original with the preview weather and time — a cheap check before regenerating all 96. The result is not saved into the set; the API call is billed.")
        }
    }

    private func runTest() {
        guard let set = store.sets.first(where: { $0.id == testSetID }),
              let originalURL = set.originalURL else { return }
        let providerID = set.meta.providerID ?? ProviderRegistry.defaultProviderID
        guard let provider = ProviderRegistry.provider(id: providerID) else { return }
        let variant = previewVariant
        let prompt = PromptBuilder.editPrompt(for: variant, template: template)
        let targetSize = set.meta.device?.pixelSize ?? CGSize(width: 1024, height: 1024)
        let folderURL = set.folderURL
        isTesting = true
        testError = nil
        testImage = nil
        testCost = nil
        Task {
            do {
                let apiKey: String
                switch KeychainStore.readAPIKey(for: providerID) {
                case .success(let key):
                    apiKey = key
                case .failure(let reason):
                    throw ProviderError.keyUnavailable(providerName: provider.displayName, reason: reason)
                }
                try await WallpaperFileSystem.ensureDownloaded(originalURL)
                let original = try Data(contentsOf: originalURL)
                let result = try await provider.edit(image: original, prompt: prompt, targetSize: targetSize, apiKey: apiKey)
                testImage = ImageUtil.downsampled(data: result.data, maxPixel: 900)
                if let usage = result.usage {
                    testCost = UsageFormat.cost(usage.cost)
                    await UsageLedgerStore.shared.append(
                        [UsageRecord(category: .variantImage, variant: variant.baseName, usage: usage)],
                        folderURL: folderURL
                    )
                    WallpaperStore.shared.refresh()
                }
            } catch {
                // Failed calls can still bill tokens — keep them on the books.
                if let usage = (error as? ProviderError)?.usage {
                    await UsageLedgerStore.shared.append(
                        [UsageRecord(category: .variantImage, variant: variant.baseName, usage: usage, failed: true)],
                        folderURL: folderURL
                    )
                    WallpaperStore.shared.refresh()
                }
                testError = error.localizedDescription
            }
            isTesting = false
        }
    }
}
