import SwiftUI
import CoreLocation

struct SettingsView: View {
    @EnvironmentObject private var store: WallpaperStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ImageUtil.formatDefaultsKey) private var imageFormat = "heic"
    @AppStorage(ImageUtil.upscaleDefaultsKey) private var upscaleEnabled = true
    @AppStorage(UpscalerRegistry.defaultsKey) private var upscalerID = "native"

    var body: some View {
        #if os(macOS)
        settingsForm
            .formStyle(.grouped)
            .frame(width: 560, height: 620)
        #else
        NavigationStack {
            settingsForm
                .formStyle(.grouped)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #endif
    }

    private var settingsForm: some View {
            Form {
                Section {
                    ForEach(ProviderRegistry.all, id: \.id) { provider in
                        APIKeyRow(keyID: provider.id, name: provider.displayName, keyURL: provider.apiKeyURL)
                    }
                    ForEach(UpscalerRegistry.all.filter(\.requiresAPIKey), id: \.id) { upscaler in
                        APIKeyRow(keyID: upscaler.id, name: upscaler.displayName, keyURL: upscaler.apiKeyURL)
                    }
                } header: {
                    Text("API Keys")
                } footer: {
                    Text("Keys are stored in the Keychain and never leave your devices. The app has no backend and no analytics.")
                }

                Section {
                    Picker("Image Format", selection: $imageFormat) {
                        Text("HEIC — compact (recommended)").tag("heic")
                        Text("PNG — original").tag("png")
                    }
                    Toggle("Upscale to device resolution", isOn: $upscaleEnabled)
                    if upscaleEnabled {
                        Picker("Upscaler", selection: $upscalerID) {
                            ForEach(UpscalerRegistry.all, id: \.id) { upscaler in
                                Text(upscaler.displayName).tag(upscaler.id)
                            }
                        }
                    }
                } header: {
                    Text("Generation")
                } footer: {
                    Text("HEIC keeps wallpapers 5–8× smaller with no visible quality loss. Providers generate ~1.5 MP images; upscaling brings them to the exact screen resolution of the chosen device. Applies to newly generated images.")
                }

                GlobalSpendingSection(sets: store.sets)

                WeatherStatsSection()

                Section("Location") {
                    LocationRow()
                }

                StorageSection()

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Link(destination: URL(string: "https://github.com/mekedron/WeatherWallpapers")!) {
                        Label("Source Code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Text("Free & open source. Your images and API keys stay on your devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
    }
}

private struct APIKeyRow: View {
    let keyID: String
    let name: String
    let keyURL: URL?

    @State private var key = ""
    @State private var hasStoredKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.headline)
                Spacer()
                if hasStoredKey {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            HStack {
                SecureField("API Key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { save() }
                Button("Save") { save() }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                if hasStoredKey {
                    Button("Remove", role: .destructive) {
                        KeychainStore.removeAPIKey(for: keyID)
                        key = ""
                        hasStoredKey = false
                    }
                }
            }
            if hasStoredKey {
                Text("Key saved — enter a new one to replace it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let keyURL {
                Link(destination: keyURL) {
                    Label("Get an API key", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            // UserDefaults flag only — never reads the Keychain.
            hasStoredKey = KeychainStore.hasAPIKey(for: keyID)
        }
    }

    private func save() {
        KeychainStore.setAPIKey(key, for: keyID)
        hasStoredKey = KeychainStore.hasAPIKey(for: keyID)
        key = ""
    }
}

private struct LocationRow: View {
    @State private var status = LocationProvider.shared.authorizationStatus

    private var statusText: LocalizedStringKey {
        switch status {
        case .notDetermined: return "Not requested yet"
        case .denied, .restricted: return "Denied — enable in System Settings"
        default: return "Allowed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "location.fill").foregroundStyle(.tint)
                Text(statusText)
            }
            if status == .notDetermined {
                Button("Allow Location Access") {
                    LocationProvider.shared.requestAuthorization()
                    Task { @MainActor in
                        for _ in 0..<30 {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            let current = LocationProvider.shared.authorizationStatus
                            if current != .notDetermined {
                                status = current
                                LocationProvider.shared.warmUpCache()
                                return
                            }
                        }
                    }
                }
            }
            Text("Used by the Shortcuts action to pick the wallpaper for the weather at your location. Weather comes from Open-Meteo, no account needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
