import Foundation
import Security

/// Secrets the user pastes in, kept in the Keychain.
enum Credentials {
    private static let service = Bundle.main.bundleIdentifier ?? "SavedFeeds"

    /// Reddit's private "saved links" JSON feed, from old.reddit.com/prefs/feeds.
    static var redditFeedURL: String? {
        get { read("redditFeedURL") }
        set { write(newValue, for: "redditFeedURL") }
    }

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read(_ account: String) -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String?, for account: String) {
        SecItemDelete(query(account) as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var item = query(account)
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}
