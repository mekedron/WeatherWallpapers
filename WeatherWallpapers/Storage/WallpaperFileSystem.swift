import Foundation

/// Low-level, thread-agnostic file system helpers shared by the UI store and
/// the App Intents entity query. Wallpapers live as plain folders of PNGs so
/// they sync через iCloud Drive and stay usable without the app.
enum WallpaperFileSystem {
    static let ubiquityContainerID = "iCloud.com.mekedron.WeatherWallpapers"
    static let rootFolderName = "Wallpapers"

    struct Root {
        let url: URL
        let isICloud: Bool
    }

    /// Resolves the storage root, preferring the iCloud Drive container.
    /// Blocking — call off the main thread.
    static func resolveRoot() -> Root {
        let fm = FileManager.default
        if let container = fm.url(forUbiquityContainerIdentifier: ubiquityContainerID) {
            let url = container.appendingPathComponent("Documents", isDirectory: true)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            return Root(url: url, isICloud: true)
        }
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = documents.appendingPathComponent(rootFolderName, isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return Root(url: url, isICloud: false)
    }

    /// Lists all wallpaper set folders in the root.
    static func listSets(root: URL) -> [WallpaperSet] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { loadSet(folderURL: $0) }
            .sorted { lhs, rhs in
                (lhs.meta.createdAt ?? .distantPast) > (rhs.meta.createdAt ?? .distantPast)
            }
    }

    /// Reads one set folder: metadata + which variant files exist.
    static func loadSet(folderURL: URL) -> WallpaperSet {
        let fm = FileManager.default
        var meta = SetMetadata()
        let metaURL = folderURL.appendingPathComponent(SetMetadata.fileName)
        if let data = try? Data(contentsOf: metaURL),
           let decoded = try? metadataDecoder().decode(SetMetadata.self, from: data) {
            meta = decoded
        }

        var files = Set<String>()
        var original: String?
        let names = (try? fm.contentsOfDirectory(atPath: folderURL.path)) ?? []
        for rawName in names {
            // Not-yet-downloaded iCloud files appear as ".Name.png.icloud" placeholders.
            let name = normalizedName(rawName)
            let lower = name.lowercased()
            guard lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".heic") else { continue }
            files.insert(name)
            if name.hasPrefix(WallpaperSet.originalBaseName) {
                original = name
            }
        }
        let usage = loadLedger(folderURL: folderURL)
        return WallpaperSet(folderURL: folderURL, meta: meta, existingFiles: files, originalFileName: original, usage: usage)
    }

    static func normalizedName(_ rawName: String) -> String {
        if rawName.hasPrefix("."), rawName.hasSuffix(".icloud") {
            return String(rawName.dropFirst().dropLast(".icloud".count))
        }
        return rawName
    }

    static func saveMetadata(_ meta: SetMetadata, in folderURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(meta)
        try data.write(to: folderURL.appendingPathComponent(SetMetadata.fileName), options: .atomic)
    }

    /// Reads the per-set ledger of billable API calls (`usage.json`).
    static func loadLedger(folderURL: URL) -> UsageLedger {
        let url = folderURL.appendingPathComponent(UsageLedger.fileName)
        guard let data = try? Data(contentsOf: url),
              let ledger = try? metadataDecoder().decode(UsageLedger.self, from: data) else {
            return UsageLedger()
        }
        return ledger
    }

    static func saveLedger(_ ledger: UsageLedger, in folderURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(ledger)
        try data.write(to: folderURL.appendingPathComponent(UsageLedger.fileName), options: .atomic)
    }

    /// Makes sure an iCloud file is actually on disk, triggering a download if needed.
    static func ensureDownloaded(_ url: URL, timeout: TimeInterval = 60) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return }

        try fm.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if fm.fileExists(atPath: url.path) { return }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        throw CocoaError(.fileReadNoSuchFile)
    }

    /// Atomically writes image data into a set folder.
    static func writeImage(_ data: Data, to destination: URL) throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + destination.pathExtension)
        try data.write(to: tmp)
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: destination)
        }
    }

    // MARK: - Custom devices (devices.json in the root, synced with the wallpapers)

    static func loadCustomDevices(root: URL) -> [DeviceSpec] {
        let url = root.appendingPathComponent("devices.json")
        guard let data = try? Data(contentsOf: url),
              let devices = try? JSONDecoder().decode([DeviceSpec].self, from: data) else { return [] }
        return devices
    }

    static func saveCustomDevices(_ devices: [DeviceSpec], root: URL) {
        let url = root.appendingPathComponent("devices.json")
        if let data = try? JSONEncoder().encode(devices) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// JSON de/encoder date strategy helper for set.json.
    static func metadataDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
