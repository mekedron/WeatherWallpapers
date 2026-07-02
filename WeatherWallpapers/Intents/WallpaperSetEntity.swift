import Foundation
import AppIntents

/// A wallpaper set as it appears inside the Shortcuts app.
struct WallpaperSetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Wallpaper Set")
    static var defaultQuery = WallpaperSetQuery()

    /// The folder name of the set.
    var id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

struct WallpaperSetQuery: EntityQuery {
    private func allEntities() -> [WallpaperSetEntity] {
        let root = WallpaperFileSystem.resolveRoot()
        return WallpaperFileSystem.listSets(root: root.url).map { WallpaperSetEntity(id: $0.id) }
    }

    func entities(for identifiers: [String]) async throws -> [WallpaperSetEntity] {
        let result = allEntities().filter { identifiers.contains($0.id) }
        WallpaperResolver.logger.info("Query entities(for: \(identifiers, privacy: .public)) -> \(result.map(\.id), privacy: .public)")
        return result
    }

    func suggestedEntities() async throws -> [WallpaperSetEntity] {
        let result = allEntities()
        WallpaperResolver.logger.info("Query suggestedEntities() -> \(result.map(\.id), privacy: .public)")
        return result
    }
}
