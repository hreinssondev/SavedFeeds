import Foundation

/// Sign-ins the Safari extension hands over. It copies Safari's cookies for each site, so passkey logins work;
/// the app picks them up and deletes the file. Compiled into the app and the extension.
nonisolated enum SharedSessions {
    static let changed = Notification.Name("com.hreinsson.SavedFeeds.sessionsChanged")

    struct Handoff: Codable {
        /// Service raw value → every cookie Safari has for that site.
        let cookies: [String: [Cookie]]
        let userAgent: String?
    }

    /// The fields of a WebExtension `cookies.Cookie`.
    struct Cookie: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let secure: Bool?
        let httpOnly: Bool?
        /// Seconds since 1970; absent for session cookies.
        let expirationDate: Double?

        var httpCookie: HTTPCookie? {
            var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
            if secure == true { properties[.secure] = "TRUE" }
            if httpOnly == true { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if let expirationDate { properties[.expires] = Date(timeIntervalSince1970: expirationDate) }
            return HTTPCookie(properties: properties)
        }
    }

    private static var file: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SessionGroup") as? String else { return nil }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appending(path: "sessions.json")
    }

    /// Extension side: a `Handoff` as JSON, straight from background.js.
    static func hand(_ json: Data) {
        guard let file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? json.write(to: file, options: .atomic)
        #if os(macOS)
        DistributedNotificationCenter.default().postNotificationName(changed, object: nil, userInfo: nil, deliverImmediately: true)
        #endif
    }

    /// App side: whatever was handed over since last time.
    static func take() -> Handoff? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        try? FileManager.default.removeItem(at: file)
        return try? JSONDecoder().decode(Handoff.self, from: data)
    }
}
