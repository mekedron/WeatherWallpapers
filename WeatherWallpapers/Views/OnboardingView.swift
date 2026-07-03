import SwiftUI
import CoreLocation

/// First-launch onboarding: what the app does, how the Shortcuts automation
/// works, and the location permission request.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0
    @State private var locationGranted = false
    @State private var language = AppLanguage.current
    #if os(iOS)
    @State private var languageChanged = false
    #endif

    private let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Group {
                switch page {
                case 0: welcomePage
                case 1: howItWorksPage
                default: locationPage
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 28)
            Spacer()
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 560)
        #endif
        .background(.background)
        .overlay(alignment: .topTrailing) {
            languageSwitcher
                .padding(16)
        }
        .onAppear {
            locationGranted = Self.isAuthorized(LocationProvider.shared.authorizationStatus)
        }
    }

    /// Compact language menu in the corner of the first screen. On the Mac
    /// the app relaunches straight back into onboarding in the new language.
    private var languageSwitcher: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Menu {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        option.displayName.tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label {
                    language.displayName
                } icon: {
                    Image(systemName: "globe")
                }
                .font(.subheadline)
            }
            .fixedSize()
            .onChange(of: language) {
                guard language != AppLanguage.current else { return }
                AppLanguage.apply(language)
                #if os(iOS)
                languageChanged = true
                #else
                AppLanguage.relaunch()
                #endif
            }
            #if os(iOS)
            if languageChanged {
                Text("Applies after the app restarts.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            #endif
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("onboarding.welcome.title")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("onboarding.welcome.body")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var howItWorksPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("onboarding.how.title")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 8)
            bullet(icon: "photo.badge.plus", text: "onboarding.how.step1")
            bullet(icon: "wand.and.stars", text: "onboarding.how.step2")
            bullet(icon: "sparkles.rectangle.stack", text: "onboarding.how.step3")
        }
    }

    private func bullet(icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 34)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var locationPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("onboarding.location.title")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("onboarding.location.body")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if locationGranted {
                Label("Location access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .padding(.top, 8)
            } else {
                Button {
                    requestLocation()
                } label: {
                    Label("Allow Location Access", systemImage: "location.fill")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }
        }
    }

    private func requestLocation() {
        LocationProvider.shared.requestAuthorization()
        // The system dialog has no completion callback — poll briefly.
        Task { @MainActor in
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Self.isAuthorized(LocationProvider.shared.authorizationStatus) {
                    locationGranted = true
                    LocationProvider.shared.warmUpCache()
                    return
                }
            }
        }
    }

    private static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        #if os(macOS)
        return status == .authorized || status == .authorizedAlways
        #else
        return status == .authorizedWhenInUse || status == .authorizedAlways
        #endif
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            HStack {
                if page == pageCount - 1, !locationGranted {
                    Button("Not Now") { onFinish() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if page < pageCount - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Group {
                        if page < pageCount - 1 {
                            Text("Next")
                        } else {
                            Text("Get Started")
                        }
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
    }
}
