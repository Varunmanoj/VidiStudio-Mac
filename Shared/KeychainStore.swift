import Foundation
import Security

/// Stores the Gemini API key in the macOS Keychain, the OS-managed credential store.
///
/// The key is therefore owned by the user's login keychain rather than the application
/// bundle or its config file: it survives app updates and reinstalls, is protected by the
/// system, and is never written to `config.json` in plaintext. The engine receives the key
/// through the `VIDISTUDIO_API_KEY` process environment variable instead of reading it
/// from disk.
enum KeychainStore {
    /// Stable identifiers so every build of the app addresses the same Keychain item.
    static let service = "com.vidistudio.gemini-api"
    static let account = "gemini-api-key"

    private static let lock = NSLock()
    /// `nil` means "not read yet"; `.some(nil)` means "known to be absent".
    private nonisolated(unsafe) static var cache: String??

    /// Returns the stored API key, or `nil` when none is present.
    static func read() -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let cache { return cache }
        let value = loadFromKeychain()
        cache = .some(value)
        return value
    }

    /// Returns true when a non-empty key is available without requiring the key itself.
    static func containsValue() -> Bool {
        guard let value = read() else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Stores (or clears, for an empty value) the API key. Returns true on success.
    @discardableResult
    static func write(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let desired: String? = normalized.isEmpty ? nil : normalized
        lock.lock()
        defer { lock.unlock() }
        if let cache, cache == desired { return true }
        if let desired {
            guard saveToKeychain(desired) else { return false }
        } else {
            guard removeFromKeychain() else { return false }
        }
        cache = .some(desired)
        return true
    }

    /// Removes the stored API key from the Keychain.
    static func delete() {
        lock.lock()
        defer { lock.unlock() }
        _ = removeFromKeychain()
        cache = .some(nil)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func loadFromKeychain() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    private static func saveToKeychain(_ value: String) -> Bool {
        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: "VidiStudio Gemini API Key",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound {
            // The stored item can belong to a different code signature — an earlier build or an
            // external tool. Replace it so this build owns it and macOS stops prompting on access.
            SecItemDelete(baseQuery() as CFDictionary)
        }
        var add = baseQuery()
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrLabel as String] = "VidiStudio Gemini API Key"
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    private static func removeFromKeychain() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
