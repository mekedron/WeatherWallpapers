import SwiftUI
#if os(macOS)
import AppKit
#endif

/// In-app UI language override, backed by the standard `AppleLanguages`
/// user default. `system` clears the override and follows the OS setting.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }

    /// Each language names itself, so the row stays readable no matter
    /// which language the app is currently displayed in.
    var displayName: Text {
        switch self {
        case .system: Text("System")
        case .english: Text(verbatim: "English")
        case .russian: Text(verbatim: "Русский")
        }
    }

    static let overrideKey = "appLanguageOverride"

    static var current: AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: overrideKey),
              let language = AppLanguage(rawValue: raw) else { return .system }
        return language
    }

    /// Persists the override. Localized strings are resolved once at process
    /// start, so the change fully applies on the next launch.
    static func apply(_ language: AppLanguage) {
        let defaults = UserDefaults.standard
        if language == .system {
            defaults.removeObject(forKey: overrideKey)
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set(language.rawValue, forKey: overrideKey)
            defaults.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    /// Relaunches the app so the new language takes effect immediately.
    /// No-op on iOS, where processes cannot restart themselves.
    static func relaunch() {
        #if os(macOS)
        // Flush the AppleLanguages write before dying — exit() skips the
        // usual defaults persistence.
        UserDefaults.standard.synchronize()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            // Not NSApp.terminate: an onboarding sheet with interactive
            // dismissal disabled makes it cancel, leaving two instances.
            DispatchQueue.main.async { exit(0) }
        }
        #endif
    }
}

/// "Language" picker row for Settings and onboarding. Changing the value
/// relaunches the app on the Mac; on iOS the footer asks for a restart.
struct LanguagePicker: View {
    @State private var selection = AppLanguage.current

    var body: some View {
        Picker("Language", selection: $selection) {
            ForEach(AppLanguage.allCases) { language in
                language.displayName.tag(language)
            }
        }
        .onChange(of: selection) {
            guard selection != AppLanguage.current else { return }
            AppLanguage.apply(selection)
            AppLanguage.relaunch()
        }
    }
}
