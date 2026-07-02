import SwiftUI

/// One wallpaper set: 30 weather groups, each a row of 4 times of day.
/// Supports multi-select regeneration of any subset.
struct SetDetailView: View {
    @EnvironmentObject private var store: WallpaperStore
    @EnvironmentObject private var center: GenerationCenter
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    let setID: String

    @State private var selecting = false
    @State private var selection = Set<WallpaperVariant>()
    @State private var previewVariant: WallpaperVariant?
    @State private var confirmRegenerateAll = false
    @State private var showBudget = false

    private var set: WallpaperSet? { store.set(id: setID) }

    var body: some View {
        Group {
            if let set {
                content(for: set)
            } else {
                ContentUnavailableView("Wallpaper set not found", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(setID)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func content(for set: WallpaperSet) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header(for: set)
                    .padding(.horizontal)

                ForEach(WeatherCondition.allCases) { weather in
                    Section {
                        weatherRow(weather, in: set)
                            .padding(.horizontal)
                    } header: {
                        weatherHeader(weather, in: set)
                    }
                }
            }
            .padding(.vertical)
        }
        .toolbar { toolbarContent(for: set) }
        #if os(iOS)
        .fullScreenCover(item: $previewVariant) { variant in
            VariantPreviewView(setID: set.id, variant: variant)
        }
        #endif
        .sheet(isPresented: $showBudget) {
            SetBudgetView(set: set)
        }
        .confirmationDialog(
            "Regenerate all 120 images?",
            isPresented: $confirmRegenerateAll,
            titleVisibility: .visible
        ) {
            Button("Regenerate All", role: .destructive) {
                center.enqueue(set: set, variants: WallpaperVariant.all)
            }
        } message: {
            Text("Existing images will be replaced. This may take a while and uses your API credits.")
        }
    }

    // MARK: - Header

    private func header(for set: WallpaperSet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                if let originalURL = set.originalURL {
                    ThumbnailView(url: originalURL, maxPixel: 300)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { previewVariant = nil }
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let device = set.meta.device {
                        Label("\(device.name) · \(device.resolutionText)", systemImage: "display")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let provider = ProviderRegistry.provider(id: set.meta.providerID) {
                        Label(provider.displayName, systemImage: "wand.and.stars")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Menu {
                        templateButtons(for: set)
                    } label: {
                        HStack(spacing: 3) {
                            Label(store.template(id: set.meta.promptTemplateID).name, systemImage: "text.quote")
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    if !set.usage.records.isEmpty {
                        Button {
                            showBudget = true
                        } label: {
                            Label {
                                Text(verbatim: "\(UsageFormat.cost(set.usage.totalCost)) · \(UsageFormat.tokens(set.usage.totalTokens)) tokens")
                                    .underline()
                            } icon: {
                                Image(systemName: "dollarsign.circle")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("\(set.completedCount)/\(WallpaperVariant.all.count) images")
                        .font(.title3.bold())
                    ProgressView(value: Double(set.completedCount), total: Double(WallpaperVariant.all.count))
                }
            }

            HStack(spacing: 10) {
                if center.isActive(setID: set.id) {
                    Label("Generating… \(center.activeCount(setID: set.id)) left", systemImage: "hourglass")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Stop", role: .destructive) {
                        center.cancelAll(setID: set.id)
                    }
                    .buttonStyle(.bordered)
                } else {
                    if !set.missingVariants.isEmpty {
                        Button {
                            center.enqueue(set: set, variants: set.missingVariants)
                        } label: {
                            Label("Generate Missing (\(set.missingVariants.count))", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if !center.failedVariants(setID: set.id).isEmpty {
                        Button {
                            let failed = center.failedVariants(setID: set.id)
                            center.clearFailures(setID: set.id)
                            center.enqueue(set: set, variants: failed)
                        } label: {
                            Label("Retry Failed (\(center.failedVariants(setID: set.id).count))", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    /// One entry per template; the current one is resolved (dangling IDs from
    /// imported sets show as Classic) so the checkmark never disappears.
    @ViewBuilder
    private func templateButtons(for set: WallpaperSet) -> some View {
        let currentID = store.template(id: set.meta.promptTemplateID).id
        ForEach(store.allTemplates) { template in
            Button {
                store.setPromptTemplate(template.id, for: set)
            } label: {
                if currentID == template.id {
                    Label(template.name, systemImage: "checkmark")
                } else {
                    Text(template.name)
                }
            }
        }
    }

    // MARK: - Weather group

    private func weatherHeader(_ weather: WeatherCondition, in set: WallpaperSet) -> some View {
        HStack(spacing: 8) {
            Image(systemName: weather.symbolName)
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(weather.localizedName)
                .font(.headline)
            Spacer()
            let done = WallpaperVariant.variants(for: weather).filter { set.hasImage(for: $0) }.count
            Text("\(done)/4")
                .font(.caption)
                .foregroundStyle(.secondary)
            if selecting {
                let variants = Set(WallpaperVariant.variants(for: weather))
                let allSelected = variants.isSubset(of: selection)
                Button {
                    if allSelected {
                        selection.subtract(variants)
                    } else {
                        selection.formUnion(variants)
                    }
                } label: {
                    if allSelected {
                        Text("Deselect Row")
                    } else {
                        Text("Select Row")
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func weatherRow(_ weather: WeatherCondition, in set: WallpaperSet) -> some View {
        let aspect = cellAspect(for: set)
        return HStack(spacing: 10) {
            ForEach(WallpaperVariant.variants(for: weather)) { variant in
                VariantCell(
                    set: set,
                    variant: variant,
                    aspect: aspect,
                    selecting: selecting,
                    isSelected: selection.contains(variant)
                ) {
                    if selecting {
                        if selection.contains(variant) {
                            selection.remove(variant)
                        } else {
                            selection.insert(variant)
                        }
                    } else {
                        #if os(macOS)
                        openWindow(id: "gallery", value: GalleryTarget(setID: set.id, variantID: variant.id))
                        #else
                        previewVariant = variant
                        #endif
                    }
                }
            }
        }
    }

    private func cellAspect(for set: WallpaperSet) -> CGFloat {
        guard let device = set.meta.device, device.height > 0 else { return 9.0 / 16.0 }
        return CGFloat(device.width) / CGFloat(device.height)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbarContent(for set: WallpaperSet) -> some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let variants = Array(selection)
                    selection.removeAll()
                    selecting = false
                    center.enqueue(set: set, variants: variants)
                } label: {
                    Label("Regenerate (\(selection.count))", systemImage: "arrow.clockwise")
                }
                .disabled(selection.isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    selection.removeAll()
                    selecting = false
                }
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        selecting = true
                    } label: {
                        Label("Select Images…", systemImage: "checkmark.circle")
                    }
                    Menu {
                        ForEach(TimeOfDay.allCases) { time in
                            Button(time.localizedName) {
                                selecting = true
                                selection = Set(WeatherCondition.allCases.map {
                                    WallpaperVariant(weather: $0, time: time)
                                })
                            }
                        }
                    } label: {
                        Label("Select Time of Day", systemImage: "clock")
                    }
                    Menu {
                        ForEach(ProviderRegistry.all, id: \.id) { provider in
                            Button {
                                store.setProvider(provider.id, for: set)
                            } label: {
                                if (set.meta.providerID ?? ProviderRegistry.defaultProviderID) == provider.id {
                                    Label(provider.displayName, systemImage: "checkmark")
                                } else {
                                    Text(provider.displayName)
                                }
                            }
                        }
                    } label: {
                        Label("Provider", systemImage: "wand.and.stars")
                    }
                    Menu {
                        templateButtons(for: set)
                    } label: {
                        Label("Prompt Style", systemImage: "text.quote")
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmRegenerateAll = true
                    } label: {
                        Label("Regenerate All", systemImage: "arrow.clockwise.circle")
                    }
                    #if os(macOS)
                    Divider()
                    Button("Reveal in Finder") {
                        Platform.revealInFinder(set.folderURL)
                    }
                    #endif
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
        }
    }
}

// MARK: - Cell

private struct VariantCell: View {
    @EnvironmentObject private var center: GenerationCenter

    let set: WallpaperSet
    let variant: WallpaperVariant
    let aspect: CGFloat
    let selecting: Bool
    let isSelected: Bool
    let action: () -> Void

    private var jobState: GenerationCenter.JobState? {
        center.state(setID: set.id, variant: variant)
    }

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    ZStack {
                        if set.hasImage(for: variant) {
                            ThumbnailView(url: set.url(for: variant), maxPixel: 400)
                        } else {
                            Rectangle()
                                .fill(.quaternary.opacity(0.5))
                                .overlay(
                                    Image(systemName: variant.time.symbolName)
                                        .font(.title3)
                                        .foregroundStyle(.tertiary)
                                )
                        }

                        switch jobState {
                        case .running:
                            Color.black.opacity(0.35)
                            ProgressView().tint(.white)
                        case .queued:
                            Color.black.opacity(0.35)
                            Image(systemName: "clock").foregroundStyle(.white)
                        case .failed:
                            Color.red.opacity(0.25)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.white, .red)
                        case nil:
                            EmptyView()
                        }
                    }
                }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                if selecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .white)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Label(variant.time.localizedName, systemImage: variant.time.symbolName)
                    .font(.caption2)
                    .labelStyle(.titleOnly)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.45), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(5)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }
}
