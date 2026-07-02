import SwiftUI
import UniformTypeIdentifiers

/// The wallpaper catalog: a grid of sets plus the "add" card.
struct LibraryView: View {
    @EnvironmentObject private var store: WallpaperStore
    @EnvironmentObject private var center: GenerationCenter

    @State private var showNewSet = false
    @State private var showSettings = false
    @State private var showGuide = false
    @State private var setToDelete: WallpaperSet?

    @State private var exportDocument: ZipDocument?
    @State private var exportName = ""
    @State private var isExporting = false
    @State private var showImporter = false
    @State private var isTransferring = false
    @State private var transferError: String?

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                addCard
                ForEach(store.sets) { set in
                    NavigationLink(value: set.id) {
                        SetCard(set: set)
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .contextMenu {
                        Button {
                            export(set)
                        } label: {
                            Label("Export as ZIP…", systemImage: "square.and.arrow.up")
                        }
                        #if os(macOS)
                        Button("Reveal in Finder") {
                            Platform.revealInFinder(set.folderURL)
                        }
                        #endif
                        Divider()
                        Button("Delete", role: .destructive) {
                            setToDelete = set
                        }
                    }
                }
            }
            .padding()

            if store.isReady {
                storageFooter
            }
        }
        .navigationTitle("Weather Wallpapers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewSet = true
                } label: {
                    Label("New Wallpaper Set", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button {
                    showImporter = true
                } label: {
                    Label("Import Set…", systemImage: "square.and.arrow.down")
                }
            }
            ToolbarItem {
                Button {
                    showGuide = true
                } label: {
                    Label("Shortcuts Guide", systemImage: "sparkles.rectangle.stack")
                }
            }
            ToolbarItem {
                #if os(macOS)
                // Opens the native Settings window (same as ⌘,).
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                #else
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                #endif
            }
        }
        .sheet(isPresented: $showNewSet) {
            NewSetFlow()
        }
        #if os(iOS)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        #endif
        .sheet(isPresented: $showGuide) {
            ShortcutsGuideView()
        }
        .alert(
            Text("Delete “\(setToDelete?.name ?? "")”?"),
            isPresented: Binding(get: { setToDelete != nil }, set: { if !$0 { setToDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let set = setToDelete {
                    center.cancelAll(setID: set.id)
                    store.deleteSet(set)
                }
                setToDelete = nil
            }
            Button("Cancel", role: .cancel) { setToDelete = nil }
        } message: {
            Text("All 120 images of this set will be deleted.")
        }
        .refreshable {
            store.refresh()
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .zip,
            defaultFilename: exportName
        ) { _ in
            if let url = exportDocument?.url {
                try? FileManager.default.removeItem(at: url)
            }
            exportDocument = nil
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result {
                importZip(from: url)
            }
        }
        .alert(
            Text("Import/Export Error"),
            isPresented: Binding(get: { transferError != nil }, set: { if !$0 { transferError = nil } })
        ) {
            Button("OK", role: .cancel) { transferError = nil }
        } message: {
            Text(transferError ?? "")
        }
        .overlay {
            if isTransferring {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView()
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - ZIP transfer

    private func export(_ set: WallpaperSet) {
        isTransferring = true
        Task {
            do {
                let folderURL = set.folderURL
                let zipURL = try await Task.detached(priority: .userInitiated) {
                    try ZipArchive.zip(folder: folderURL)
                }.value
                exportDocument = ZipDocument(url: zipURL)
                exportName = set.name
                isExporting = true
            } catch {
                transferError = error.localizedDescription
            }
            isTransferring = false
        }
    }

    private func importZip(from url: URL) {
        guard let rootURL = store.rootURL else { return }
        isTransferring = true
        Task {
            do {
                let importedName = try await Task.detached(priority: .userInitiated) {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    let fm = FileManager.default
                    let staging = fm.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString)")
                    defer { try? fm.removeItem(at: staging) }
                    try ZipArchive.unzip(url, to: staging)

                    // A folder zip usually contains a single top-level folder — use it.
                    let items = (try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isDirectoryKey]))
                        .filter { !$0.lastPathComponent.hasPrefix(".") }
                    var source = staging
                    var name = url.deletingPathExtension().lastPathComponent
                    if items.count == 1,
                       (try? items[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        source = items[0]
                        name = items[0].lastPathComponent
                    }

                    var folderName = name
                    var counter = 2
                    while fm.fileExists(atPath: rootURL.appendingPathComponent(folderName).path) {
                        folderName = "\(name) \(counter)"
                        counter += 1
                    }
                    try fm.moveItem(at: source, to: rootURL.appendingPathComponent(folderName))
                    return folderName
                }.value
                store.refresh()
                // A foreign set may reference the exporter's custom prompt
                // template — restore it from the embedded snapshot into the
                // library, or fall back to the default.
                store.adoptImportedTemplate(setID: importedName)
            } catch {
                transferError = error.localizedDescription
            }
            isTransferring = false
        }
    }

    private var addCard: some View {
        Button {
            showNewSet = true
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("New Wallpaper Set")
                    .font(.headline)
                Text("120 variants for every weather and time of day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(.tertiary)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private var storageFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: store.isUsingICloud ? "icloud.fill" : "internaldrive")
            if store.isUsingICloud {
                Text("Synced with iCloud Drive")
            } else {
                Text("Stored locally — sign in to iCloud to sync across devices")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom)
    }
}

/// Wraps an already-created zip file for the system save dialog.
struct ZipDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.zip]

    let url: URL

    init(url: URL) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url)
    }
}

private struct SetCard: View {
    @EnvironmentObject private var center: GenerationCenter
    let set: WallpaperSet

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let originalURL = set.originalURL {
                    ThumbnailView(url: originalURL)
                } else {
                    Rectangle().fill(.quaternary)
                        .overlay(Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary))
                }
            }
            .frame(height: 160)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(set.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if center.isActive(setID: set.id) {
                        ProgressView().controlSize(.small)
                    }
                }
                if let device = set.meta.device {
                    Text("\(device.name) · \(device.resolutionText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ProgressView(value: Double(set.completedCount), total: Double(WallpaperVariant.all.count))
                    .progressViewStyle(.linear)
                Text("\(set.completedCount)/\(WallpaperVariant.all.count) images")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
