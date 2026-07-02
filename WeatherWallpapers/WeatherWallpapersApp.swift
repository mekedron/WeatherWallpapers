import SwiftUI

@main
struct WeatherWallpapersApp: App {
    @StateObject private var store = WallpaperStore.shared
    @StateObject private var generationCenter = GenerationCenter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(generationCenter)
                .task {
                    await store.bootstrap()
                    // Keep a recent coordinate cached so the Shortcuts intent
                    // has a fallback when Core Location is slow in the background.
                    LocationProvider.shared.warmUpCache()
                }
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 600)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1150, height: 760)
        #endif

        #if os(macOS)
        // Native Settings window, opens with ⌘, as expected on the Mac.
        Settings {
            SettingsView()
                .environmentObject(store)
        }

        // The gallery viewer lives in its own resizable, full-screen-capable window.
        WindowGroup(id: "gallery", for: GalleryTarget.self) { $target in
            if let target {
                VariantPreviewView(
                    setID: target.setID,
                    variant: WallpaperVariant.all.first { $0.id == target.variantID } ?? WallpaperVariant.all[0]
                )
                // Re-create the view when the window is reused for another
                // target, so it opens on the tapped image, not a stale one.
                .id(target)
                .environmentObject(store)
                .environmentObject(generationCenter)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 800)
        #endif
    }
}

/// Identifies what the standalone gallery window shows.
struct GalleryTarget: Codable, Hashable {
    var setID: String
    var variantID: String
}
