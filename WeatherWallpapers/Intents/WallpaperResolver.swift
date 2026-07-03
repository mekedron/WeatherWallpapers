import Foundation
import os

/// Shared logic behind the "Get Current Wallpaper" intent: figures out the
/// current weather + time of day and picks the matching file from a set.
/// Heavily logged — the intent runs in the background where debugging is hard:
///   log stream --predicate 'subsystem == "com.mekedron.WeatherWallpapers"'
enum WallpaperResolver {
    static let logger = Logger(subsystem: "com.mekedron.WeatherWallpapers", category: "intent")

    struct Resolved {
        let data: Data
        let fileName: String
    }

    static func currentWallpaper(setID: String) async throws -> Resolved {
        logger.info("Resolving current wallpaper for set “\(setID, privacy: .public)”")

        let root = WallpaperFileSystem.resolveRoot()
        logger.info("Storage root: \(root.url.path, privacy: .public), iCloud: \(root.isICloud)")

        let folderURL = root.url.appendingPathComponent(setID, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            logger.error("Set folder not found")
            throw IntentError.setNotFound(setID)
        }
        let set = WallpaperFileSystem.loadSet(folderURL: folderURL)
        logger.info("Set loaded, \(set.existingFiles.count) files present")

        guard let coordinate = await LocationProvider.shared.currentCoordinate() else {
            logger.error("No location (fresh nor cached)")
            throw IntentError.noLocation
        }
        logger.info("Location acquired")

        let conditions: CurrentConditions
        do {
            conditions = try await WeatherService().currentConditions(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        } catch {
            logger.error("Weather fetch failed: \(error.localizedDescription, privacy: .public)")
            throw IntentError.weatherUnavailable
        }
        logger.info("Conditions: \(conditions.weather.rawValue, privacy: .public) / \(conditions.time.rawValue, privacy: .public)")
        await WeatherStatsStore.shared.record(conditions.weather)

        guard let variant = bestVariant(for: conditions, in: set) else {
            // Last resort: the set has no generated images at all — return the
            // original artwork so the automation still produces a wallpaper.
            if let originalURL = set.originalURL, let originalFileName = set.originalFileName {
                logger.info("No variants at all, falling back to the original image")
                try await WallpaperFileSystem.ensureDownloaded(originalURL)
                let data = try Data(contentsOf: originalURL)
                return Resolved(data: data, fileName: originalFileName)
            }
            logger.error("Set has no images at all")
            throw IntentError.noImages(setID)
        }
        let exact = WallpaperVariant(weather: conditions.weather, time: conditions.time)
        if variant != exact {
            logger.info("Exact variant \(exact.fileName, privacy: .public) missing, falling back to \(variant.fileName, privacy: .public)")
        } else {
            logger.info("Picked variant: \(variant.fileName, privacy: .public)")
        }

        let fileName = set.existingFileName(for: variant) ?? variant.fileName
        let url = set.url(for: variant)
        do {
            try await WallpaperFileSystem.ensureDownloaded(url)
            let data = try Data(contentsOf: url)
            logger.info("Returning \(data.count) bytes (\(fileName, privacy: .public))")
            return Resolved(data: data, fileName: fileName)
        } catch {
            logger.error("Reading file failed: \(error.localizedDescription, privacy: .public)")
            throw IntentError.fileUnavailable(fileName)
        }
    }

    /// Picks the closest existing wallpaper. Time of day dominates (a night
    /// image with slightly wrong weather beats a day image at night):
    /// 1. right time, walking the weather down the "milder condition" chain;
    /// 2. right time, any other weather;
    /// 3. the visually closest other times, same two passes;
    /// 4. anything the set has.
    static func bestVariant(for conditions: CurrentConditions, in set: WallpaperSet) -> WallpaperVariant? {
        for time in [conditions.time] + conditions.time.fallbackOrder {
            var weather: WeatherCondition? = conditions.weather
            while let current = weather {
                let variant = WallpaperVariant(weather: current, time: time)
                if set.hasImage(for: variant) { return variant }
                weather = current.fallback
            }
            for other in WeatherCondition.allCases {
                let variant = WallpaperVariant(weather: other, time: time)
                if set.hasImage(for: variant) { return variant }
            }
        }
        return WallpaperVariant.all.first { set.hasImage(for: $0) }
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case setNotFound(String)
    case noSets
    case noLocation
    case weatherUnavailable
    case noImages(String)
    case fileUnavailable(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .setNotFound(let name):
            return "Wallpaper set “\(name)” was not found."
        case .noSets:
            return "No wallpaper sets yet. Create one in Weather Wallpapers first."
        case .noLocation:
            return "Location is unavailable. Open Weather Wallpapers once and allow location access."
        case .weatherUnavailable:
            return "Could not load the weather. Check your internet connection and try again."
        case .noImages(let name):
            return "Wallpaper set “\(name)” has no generated images yet."
        case .fileUnavailable(let file):
            return "Could not read “\(file)”. Make sure it is downloaded from iCloud."
        }
    }
}
