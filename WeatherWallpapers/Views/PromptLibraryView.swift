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
            weatherNotes: template.weatherNotes
        ))
    }
}

// MARK: - Editor

private struct PromptTemplateEditor: View {
    @EnvironmentObject private var store: WallpaperStore
    @Environment(\.dismiss) private var dismiss
    @State var template: PromptTemplate

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
                    } header: {
                        Text("Prompt")
                    } footer: {
                        placeholdersFooter
                    }
                    weatherNotesSection
                }
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
                            store.saveTemplate(PromptTemplate(
                                id: UUID().uuidString,
                                name: String(localized: "\(template.name) Copy"),
                                summary: template.summary,
                                text: template.text,
                                weatherNotes: template.weatherNotes
                            ))
                            dismiss()
                        }
                    } else {
                        Button("Save") {
                            var cleaned = template
                            let notes = (cleaned.weatherNotes ?? [:]).filter {
                                !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            }
                            cleaned.weatherNotes = notes.isEmpty ? nil : notes
                            store.saveTemplate(cleaned)
                            dismiss()
                        }
                        .disabled(template.name.trimmingCharacters(in: .whitespaces).isEmpty
                            || template.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    private var placeholdersFooter: some View {
        Text("Placeholders: {time} and {weather} insert the detailed lighting and weather descriptions, {time_name} and {weather_name} the plain labels (\"Sunset\", \"Heavy Rain\"). The no-text-on-image rule is always appended automatically.")
    }

    // MARK: - Weather-specific additions

    /// Conditions that already have a note, in the canonical weather order.
    private var notedConditions: [WeatherCondition] {
        WeatherCondition.allCases.filter { template.weatherNotes?[$0.rawValue] != nil }
    }

    private var weatherNotesSection: some View {
        Section {
            ForEach(notedConditions) { weather in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(weather.localizedName, systemImage: weather.symbolName)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button {
                            template.weatherNotes?[weather.rawValue] = nil
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    TextField("e.g. keep the tornado far away…", text: Binding(
                        get: { template.weatherNotes?[weather.rawValue] ?? "" },
                        set: { template.weatherNotes?[weather.rawValue] = $0 }
                    ))
                    #if os(macOS)
                    .textFieldStyle(.roundedBorder)
                    #endif
                }
                .padding(.vertical, 2)
            }
            Menu {
                ForEach(WeatherCondition.allCases.filter { template.weatherNotes?[$0.rawValue] == nil }) { weather in
                    Button {
                        var notes = template.weatherNotes ?? [:]
                        notes[weather.rawValue] = ""
                        template.weatherNotes = notes
                    } label: {
                        Label(weather.localizedName, systemImage: weather.symbolName)
                    }
                }
            } label: {
                Label("Add Weather Condition", systemImage: "plus")
            }
        } header: {
            Text("Weather-Specific Additions")
        } footer: {
            Text("Appended to the prompt only for the selected weather conditions. Other conditions use just the prompt above.")
        }
    }
}
