import SwiftUI

/// The Storage section of Settings: where wallpapers live (iCloud vs local)
/// plus a per-component breakdown of the space used on this device.
struct StorageSection: View {
    @EnvironmentObject private var store: WallpaperStore

    @State private var breakdown: StorageBreakdown?
    @State private var clearingCaches = false

    var body: some View {
        Section {
            locationRow
                // Anchored to an always-present row: modifiers directly on
                // Section don't reliably survive Form's section handling.
                .task { await audit() }
                .onReceive(NotificationCenter.default.publisher(for: .weatherStatsDidChange)) { _ in
                    Task { await audit() }
                }

            if let breakdown {
                LabeledContent("Total on This Device", value: UsageFormat.fileSize(breakdown.totalBytes))

                if !breakdown.sets.isEmpty {
                    DisclosureGroup {
                        ForEach(breakdown.sets) { set in
                            LabeledContent(set.name, value: UsageFormat.fileSize(set.bytes))
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        LabeledContent("Wallpaper Sets", value: UsageFormat.fileSize(breakdown.setsBytes))
                    }
                }
                LabeledContent("Weather Statistics", value: UsageFormat.fileSize(breakdown.weatherStatsBytes))
                LabeledContent("Caches", value: UsageFormat.fileSize(breakdown.cachesBytes))
                if breakdown.metadataBytes > 0 {
                    LabeledContent("Metadata", value: UsageFormat.fileSize(breakdown.metadataBytes))
                }
            } else {
                HStack {
                    Text("Calculating…")
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Button("Clear Caches") {
                clearingCaches = true
                Task {
                    await StorageAuditor.clearCaches()
                    await audit()
                    clearingCaches = false
                }
            }
            .disabled(breakdown == nil || clearingCaches)

            #if os(macOS)
            if let rootURL = store.rootURL {
                Button("Reveal Wallpapers Folder in Finder") {
                    Platform.revealInFinder(rootURL)
                }
            }
            #endif
        } header: {
            Text("Storage")
        } footer: {
            Text("Sizes reflect space used on this device. Wallpapers not yet downloaded from iCloud take almost no space. Caches hold only regenerable data and are safe to clear.")
        }
    }

    private var locationRow: some View {
        HStack {
            Image(systemName: store.isUsingICloud ? "icloud.fill" : "internaldrive")
                .foregroundStyle(.tint)
            VStack(alignment: .leading) {
                if store.isUsingICloud {
                    Text("iCloud Drive")
                    Text("Wallpapers sync automatically across all your devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Local Storage")
                    Text("Sign in to iCloud to sync wallpapers across devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func audit() async {
        breakdown = await StorageAuditor.audit(root: store.rootURL)
    }
}
