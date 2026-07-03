import Foundation

/// Disk usage of everything the app stores on this device, grouped by
/// component. Sizes are allocated bytes, so not-yet-downloaded iCloud files
/// count only their tiny placeholders.
struct StorageBreakdown: Sendable {
    struct SetUsage: Identifiable, Sendable {
        let name: String
        let bytes: Int
        var id: String { name }
    }

    /// Wallpaper set folders, largest first.
    var sets: [SetUsage] = []
    /// Loose files in the wallpapers root: devices.json, prompts.json, …
    var metadataBytes = 0
    var weatherStatsBytes = 0
    /// Library/Caches plus the temporary directory.
    var cachesBytes = 0

    var setsBytes: Int { sets.reduce(0) { $0 + $1.bytes } }
    var totalBytes: Int { setsBytes + metadataBytes + weatherStatsBytes + cachesBytes }
}

/// Walks the app's storage locations off the main thread and sums file sizes.
enum StorageAuditor {
    static func audit(root: URL?) async -> StorageBreakdown {
        await Task.detached(priority: .utility) {
            var breakdown = StorageBreakdown()
            let fm = FileManager.default

            if let root {
                var sets: [StorageBreakdown.SetUsage] = []
                let items = (try? fm.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: []
                )) ?? []
                for item in items {
                    if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        sets.append(.init(
                            name: WallpaperFileSystem.normalizedName(item.lastPathComponent),
                            bytes: directorySize(item)
                        ))
                    } else {
                        breakdown.metadataBytes += fileSize(item)
                    }
                }
                breakdown.sets = sets.sorted { $0.bytes > $1.bytes }
            }

            breakdown.weatherStatsBytes = fileSize(WeatherStatsStore.fileURL())

            if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
                breakdown.cachesBytes += directorySize(caches)
            }
            breakdown.cachesBytes += directorySize(fm.temporaryDirectory)

            return breakdown
        }.value
    }

    /// Removes everything in Caches and the temporary directory. Safe: both
    /// hold only regenerable data (network cache, export leftovers).
    static func clearCaches() async {
        await Task.detached(priority: .utility) {
            URLCache.shared.removeAllCachedResponses()
            let fm = FileManager.default
            var dirs = [fm.temporaryDirectory]
            if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
                dirs.append(caches)
            }
            for dir in dirs {
                let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])) ?? []
                for item in items {
                    try? fm.removeItem(at: item)
                }
            }
        }.value
    }

    // MARK: - Size helpers

    private static let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
    ]

    private static func fileSize(_ url: URL) -> Int {
        guard let values = try? url.resourceValues(forKeys: sizeKeys),
              values.isRegularFile == true else { return 0 }
        return values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
    }

    private static func directorySize(_ url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(sizeKeys),
            options: []
        ) else { return 0 }

        var total = 0
        for case let item as URL in enumerator {
            total += fileSize(item)
        }
        return total
    }
}
