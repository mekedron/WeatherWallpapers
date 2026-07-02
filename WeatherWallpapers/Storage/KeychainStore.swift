import Foundation
import Security

/// Stores provider API keys in the Keychain (synced via iCloud Keychain).
///
/// Reads are kept to an absolute minimum: every SecItemCopyMatching can pop a
/// system permission dialog (especially for ad-hoc-signed dev builds), so the
/// UI never reads keys — it checks a plain UserDefaults flag instead, and the
/// actual key is read once per generation batch.
enum KeychainStore {
    private static let service = "com.mekedron.WeatherWallpapers.apikeys"

    private static func flagKey(for providerID: String) -> String {
        "hasAPIKey_\(providerID)"
    }

    /// Cheap check that never touches the Keychain.
    static func hasAPIKey(for providerID: String) -> Bool {
        UserDefaults.standard.bool(forKey: flagKey(for: providerID))
    }

    /// Why a Keychain read produced no key — kept distinct so the UI can tell
    /// "no key entered" apart from "key exists but could not be read".
    enum KeyReadError: Error, Sendable {
        /// Nothing stored. `flagWasSet` means UserDefaults claims a key was
        /// saved earlier — likely removed elsewhere or not yet synced via iCloud.
        case notFound(flagWasSet: Bool)
        /// SecItemCopyMatching failed (access denied, keychain locked, …).
        case failed(OSStatus)
    }

    /// Reads the key. May prompt the user once — call only right before use.
    static func readAPIKey(for providerID: String) -> Result<String, KeyReadError> {
        var query = baseQuery(for: providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = String(data: data, encoding: .utf8), !key.isEmpty else {
                return .failure(.notFound(flagWasSet: hasAPIKey(for: providerID)))
            }
            return .success(key)
        case errSecItemNotFound:
            return .failure(.notFound(flagWasSet: hasAPIKey(for: providerID)))
        default:
            return .failure(.failed(status))
        }
    }

    /// Convenience for callers that can proceed without the key (e.g. upscalers).
    static func apiKey(for providerID: String) -> String? {
        try? readAPIKey(for: providerID).get()
    }

    static func setAPIKey(_ key: String?, for providerID: String) {
        // Delete + add (instead of update) so the item's access control always
        // belongs to the current build — avoids repeated permission dialogs
        // after rebuilds with a different signature.
        SecItemDelete(baseQuery(for: providerID) as CFDictionary)

        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            UserDefaults.standard.set(false, forKey: flagKey(for: providerID))
            return
        }

        var attributes = baseQuery(for: providerID)
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        UserDefaults.standard.set(status == errSecSuccess, forKey: flagKey(for: providerID))
    }

    static func removeAPIKey(for providerID: String) {
        setAPIKey(nil, for: providerID)
    }

    private static func baseQuery(for providerID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }
}
