import Foundation
import AppIntents
import UniformTypeIdentifiers

/// The Shortcuts block: returns the wallpaper image matching the current
/// weather and time of day at the user's location.
struct GetCurrentWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Current Wallpaper"
    static var description = IntentDescription(
        "Returns the image from the chosen wallpaper set that matches the current weather and time of day at your location.",
        categoryName: "Wallpapers"
    )

    // Optional on purpose: entity resolution at run time is blocked in some
    // environments (e.g. ad-hoc-signed simulator builds get rejected by linkd,
    // producing "internal error"). With no value the intent falls back to the
    // set named in `setName`, or to the only existing set.
    @Parameter(title: "Wallpaper Set")
    var wallpaperSet: WallpaperSetEntity?

    @Parameter(title: "Set Name (if the picker fails)")
    var setName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Get the current wallpaper from \(\.$wallpaperSet)") {
            \.$setName
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let setID = try Self.resolveSetID(entity: wallpaperSet, name: setName)
        let resolved = try await WallpaperResolver.currentWallpaper(setID: setID)
        let ext = (resolved.fileName as NSString).pathExtension
        let type = UTType(filenameExtension: ext) ?? .png
        let file = IntentFile(data: resolved.data, filename: resolved.fileName, type: type)
        return .result(value: file)
    }

    static func resolveSetID(entity: WallpaperSetEntity?, name: String?) throws -> String {
        if let entity {
            return entity.id
        }
        let root = WallpaperFileSystem.resolveRoot()
        let sets = WallpaperFileSystem.listSets(root: root.url)

        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            if let match = sets.first(where: { $0.id.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                return match.id
            }
            WallpaperResolver.logger.error("No set named “\(name, privacy: .public)”")
            throw IntentError.setNotFound(name)
        }

        guard let only = sets.first else {
            throw IntentError.noSets
        }
        if sets.count > 1 {
            WallpaperResolver.logger.info("No set specified, using the most recent: \(only.id, privacy: .public)")
        }
        return only.id
    }
}

struct WeatherWallpapersShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetCurrentWallpaperIntent(),
            phrases: [
                "Get current wallpaper from \(.applicationName)",
                "Актуальные обои из \(.applicationName)",
            ],
            shortTitle: "Current Wallpaper",
            systemImageName: "photo.on.rectangle.angled"
        )
    }
}
