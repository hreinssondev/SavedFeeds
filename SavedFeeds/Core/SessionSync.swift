import Foundation
import Security

/// The Mac app's sign-ins, shared with the iPhone app through iCloud Keychain: the Mac publishes each service's
/// cookies after they've loaded a feed; the iPhone takes any it hasn't seen. Sessions are made on the Mac (Safari,
/// passkeys) and only copied to the phone.
enum SessionSync {
    struct Session: Codable {
        let cookies: [SharedSessions.Cookie]
        let userAgent: String?
    }

    /// Mac: shares the current session for `service` when it's new (its session cookie changed).
    static func publish(_ service: Service) async {
        let cookies = await WebSession.cookies(for: service.cookieDomain)
        guard let current = cookies.first(where: { $0.name == service.sessionCookie })?.value,
              current != stored(service)?.sessionValue(for: service)
        else { return }
        let session = Session(cookies: cookies.map(SharedSessions.Cookie.init), userAgent: WebSession.userAgent)
        guard let data = try? JSONEncoder().encode(session) else { return }
        write(data, account: service.rawValue)
        log.info("Shared the \(service.rawValue, privacy: .public) session with iCloud Keychain")
    }

    /// iPhone: the Mac's session for `service`, if it's one not taken yet, or the phone has none.
    static func take(_ service: Service, phoneSignedIn: Bool) -> Session? {
        guard let session = stored(service), let value = session.sessionValue(for: service) else { return nil }
        let key = "takenSession.\(service.rawValue)"
        guard value != UserDefaults.standard.string(forKey: key) || !phoneSignedIn else { return nil }
        UserDefaults.standard.set(value, forKey: key)
        return session
    }

    private static func stored(_ service: Service) -> Session? {
        read(account: service.rawValue).flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
    }

    // MARK: Keychain

    private static let keychainService = "com.hreinsson.SavedFeeds.sessions"

    /// Both apps' shared access group, from Info.plist (`$(AppIdentifierPrefix)com.hreinsson.SavedFeeds.sessions`).
    private static var accessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "KeychainGroup") as? String
    }

    private static func query(_ account: String) -> [String: Any]? {
        guard let accessGroup else { return nil }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrSynchronizable as String: true,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private static func read(account: String) -> Data? {
        guard var query = query(account) else { return nil }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess, status != errSecItemNotFound {
            log.error("Keychain read \(account, privacy: .public): \(status)")
        }
        return result as? Data
    }

    private static func write(_ data: Data, account: String) {
        guard var item = query(account) else { return }
        SecItemDelete(item as CFDictionary)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            log.error("Keychain write \(account, privacy: .public): \(status)")
        }
    }
}

private extension SessionSync.Session {
    func sessionValue(for service: Service) -> String? {
        cookies.first { $0.name == service.sessionCookie }?.value
    }
}
