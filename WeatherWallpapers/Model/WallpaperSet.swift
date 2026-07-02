import Foundation

/// Metadata stored as `set.json` inside each wallpaper set folder.
struct SetMetadata: Codable, Hashable {
    var device: DeviceSpec?
    var providerID: String?
    var createdAt: Date?
    var sourcePrompt: String?
    /// ID of the prompt template used for variant generation; nil = Classic default.
    var promptTemplateID: String?

    static let fileName = "set.json"
}

/// A wallpaper set: one folder in the storage root containing the original
/// image, `set.json` and up to 120 generated variant PNGs.
struct WallpaperSet: Identifiable, Hashable {
    let folderURL: URL
    var meta: SetMetadata
    /// Names of image files currently present in the folder.
    var existingFiles: Set<String>
    /// File name of the original/source image ("!Original.png" etc.), if present.
    var originalFileName: String?
    /// Billable API calls made for this set (`usage.json`).
    var usage = UsageLedger()

    var id: String { name }
    var name: String { folderURL.lastPathComponent }

    var originalURL: URL? {
        originalFileName.map { folderURL.appendingPathComponent($0) }
    }

    /// Variants may be stored as .png, .heic or .jpg depending on the
    /// optimization setting at generation time.
    static let imageExtensions = ["png", "heic", "jpg", "jpeg"]

    func existingFileName(for variant: WallpaperVariant) -> String? {
        let base = variant.baseName
        for ext in Self.imageExtensions {
            let name = "\(base).\(ext)"
            if existingFiles.contains(name) { return name }
        }
        return nil
    }

    func url(for variant: WallpaperVariant) -> URL {
        folderURL.appendingPathComponent(existingFileName(for: variant) ?? variant.fileName)
    }

    func hasImage(for variant: WallpaperVariant) -> Bool {
        existingFileName(for: variant) != nil
    }

    var completedCount: Int {
        WallpaperVariant.all.filter { hasImage(for: $0) }.count
    }

    var missingVariants: [WallpaperVariant] {
        WallpaperVariant.all.filter { !hasImage(for: $0) }
    }

    static let originalBaseName = "!Original"
}
