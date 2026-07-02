import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WallpaperStore
    @State private var path = NavigationPath()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var tab: HomeTab = .wallpapers

    private enum HomeTab {
        case wallpapers, prompts
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch tab {
                case .wallpapers: LibraryView()
                case .prompts: PromptLibraryView()
                }
            }
            // Floating switcher between the wallpaper grid and the prompt
            // library; only on the root screen — pushed views cover it.
            .safeAreaInset(edge: .bottom) {
                tabSwitcher
            }
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
            // Test hook: `-tab prompts` starts on the prompt library tab.
            if let index = arguments.firstIndex(of: "-tab"),
               arguments.indices.contains(index + 1),
               arguments[index + 1] == "prompts" {
                tab = .prompts
            }
            // Test hook: `-regenOne <Name>` queues the first missing variant
            // of a set — exercises the full generation pipeline once.
            if let index = arguments.firstIndex(of: "-regenOne"),
               arguments.indices.contains(index + 1),
               let set = store.set(id: arguments[index + 1]),
               let variant = set.missingVariants.first {
                GenerationCenter.shared.enqueue(set: set, variants: [variant])
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

    private var tabSwitcher: some View {
        HStack(spacing: 4) {
            tabButton(.wallpapers, "Wallpapers", icon: "photo.stack")
            tabButton(.prompts, "Prompts", icon: "text.quote")
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        .padding(.bottom, 10)
    }

    private func tabButton(_ value: HomeTab, _ title: LocalizedStringKey, icon: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { tab = value }
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(tab == value ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: Capsule())
                .foregroundStyle(tab == value ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(tab == value ? .isSelected : [])
    }
}

#Preview {
    ContentView()
        .environmentObject(WallpaperStore.shared)
        .environmentObject(GenerationCenter.shared)
}
