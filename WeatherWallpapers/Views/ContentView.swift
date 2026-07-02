import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WallpaperStore
    @State private var path = NavigationPath()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView()
                .navigationDestination(for: String.self) { setID in
                    SetDetailView(setID: setID)
                }
        }
        .onAppear {
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                showOnboarding = false
            }
        }
        #else
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        #endif
        #if DEBUG
        .onChange(of: store.isReady) { _, ready in
            guard ready else { return }
            let arguments = ProcessInfo.processInfo.arguments
            // Test hook: `-openSet <Name>` jumps straight into a set.
            if let index = arguments.firstIndex(of: "-openSet"),
               arguments.indices.contains(index + 1) {
                path.append(arguments[index + 1])
            }
            // Test hook: `-testIntent <Name>` runs the intent logic and logs the outcome.
            if let index = arguments.firstIndex(of: "-testIntent"),
               arguments.indices.contains(index + 1) {
                let setID = arguments[index + 1]
                Task {
                    do {
                        let resolved = try await WallpaperResolver.currentWallpaper(setID: setID)
                        WallpaperResolver.logger.info("TEST INTENT OK: \(resolved.fileName, privacy: .public)")
                    } catch {
                        WallpaperResolver.logger.error("TEST INTENT FAILED: \(String(describing: error), privacy: .public)")
                    }
                }
            }
        }
        #endif
    }
}

#Preview {
    ContentView()
        .environmentObject(WallpaperStore.shared)
        .environmentObject(GenerationCenter.shared)
}
