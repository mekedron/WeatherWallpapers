import Foundation
import SwiftUI

/// Observable source of truth for the UI. Wraps the plain-folder storage.
@MainActor
final class WallpaperStore: ObservableObject {
    static let shared = WallpaperStore()

    @Published private(set) var sets: [WallpaperSet] = []
    @Published private(set) var rootURL: URL?
    @Published private(set) var isUsingICloud = false
    @Published private(set) var isReady = false
    @Published var customDevices: [DeviceSpec] = []
    @Published var customTemplates: [PromptTemplate] = []

    private init() {}

    func bootstrap() async {
        guard rootURL == nil else {
            refresh()
            return
        }
        let root = await Task.detached(priority: .userInitiated) {
            WallpaperFileSystem.resolveRoot()
        }.value
        rootURL = root.url
        isUsingICloud = root.isICloud
        customDevices = WallpaperFileSystem.loadCustomDevices(root: root.url)
        customTemplates = WallpaperFileSystem.loadPromptTemplates(root: root.url)
        refresh()
        isReady = true
    }

    func refresh() {
        guard let rootURL else { return }
        sets = WallpaperFileSystem.listSets(root: rootURL)
    }

    func set(id: String) -> WallpaperSet? {
        sets.first { $0.id == id }
    }

    var allDevices: [DeviceSpec] {
        DeviceSpec.builtIn + customDevices
    }

    func addCustomDevice(_ device: DeviceSpec) {
        customDevices.append(device)
        if let rootURL {
            WallpaperFileSystem.saveCustomDevices(customDevices, root: rootURL)
        }
    }

    // MARK: - Prompt templates

    /// Built-in presets first, then the user's own templates.
    var allTemplates: [PromptTemplate] { PromptTemplate.presets + customTemplates }

    /// Resolves a template ID, falling back to the Classic default for nil
    /// or dangling IDs (e.g. a template deleted on another device).
    func template(id: String?) -> PromptTemplate {
        guard let id else { return .defaultTemplate }
        return allTemplates.first { $0.id == id } ?? .defaultTemplate
    }

    /// Adds a new custom template or updates an existing one in place.
    func saveTemplate(_ template: PromptTemplate) {
        guard !template.isBuiltIn else { return }
        if let index = customTemplates.firstIndex(where: { $0.id == template.id }) {
            customTemplates[index] = template
        } else {
            customTemplates.append(template)
        }
        persistTemplates()
    }

    func deleteTemplate(_ template: PromptTemplate) {
        guard !template.isBuiltIn else { return }
        customTemplates.removeAll { $0.id == template.id }
        persistTemplates()
    }

    private func persistTemplates() {
        if let rootURL {
            WallpaperFileSystem.savePromptTemplates(customTemplates, root: rootURL)
        }
    }

    /// Creates a new set folder with the original image and metadata.
    @discardableResult
    func createSet(name: String, originalData: Data, fileExtension: String, meta: SetMetadata) throws -> WallpaperSet {
        guard let rootURL else { throw CocoaError(.fileNoSuchFile) }
        let sanitized = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var folderName = sanitized.isEmpty ? String(localized: "New Wallpaper") : sanitized
        let fm = FileManager.default
        var counter = 2
        while fm.fileExists(atPath: rootURL.appendingPathComponent(folderName).path) {
            folderName = "\(sanitized) \(counter)"
            counter += 1
        }
        let folderURL = rootURL.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let originalURL = folderURL.appendingPathComponent("\(WallpaperSet.originalBaseName).\(fileExtension)")
        try originalData.write(to: originalURL, options: .atomic)
        try WallpaperFileSystem.saveMetadata(meta, in: folderURL)

        refresh()
        return WallpaperFileSystem.loadSet(folderURL: folderURL)
    }

    /// Switches the image provider used for future generations of a set.
    func setProvider(_ providerID: String, for set: WallpaperSet) {
        var meta = set.meta
        meta.providerID = providerID
        try? WallpaperFileSystem.saveMetadata(meta, in: set.folderURL)
        refresh()
    }

    /// Imported sets may reference a prompt template from someone else's
    /// library — reset such dangling references to the default so the stale
    /// ID doesn't linger in set.json.
    func resetUnknownTemplate(setID: String) {
        guard let set = set(id: setID),
              let id = set.meta.promptTemplateID,
              !allTemplates.contains(where: { $0.id == id }) else { return }
        var meta = set.meta
        meta.promptTemplateID = nil
        try? WallpaperFileSystem.saveMetadata(meta, in: set.folderURL)
        refresh()
    }

    /// Switches the prompt template used for future generations of a set.
    func setPromptTemplate(_ templateID: String, for set: WallpaperSet) {
        var meta = set.meta
        meta.promptTemplateID = templateID
        try? WallpaperFileSystem.saveMetadata(meta, in: set.folderURL)
        refresh()
    }

    func deleteSet(_ set: WallpaperSet) {
        try? FileManager.default.removeItem(at: set.folderURL)
        refresh()
    }

    func deleteImage(of set: WallpaperSet, variant: WallpaperVariant) {
        try? FileManager.default.removeItem(at: set.url(for: variant))
        refresh()
    }
}
