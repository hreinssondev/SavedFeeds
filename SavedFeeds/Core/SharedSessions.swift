import Foundation

/// Sign-ins the Safari extension hands over. It reads Safari's session cookies, so passkey logins work;
/// the app picks them up and deletes the file. Compiled into the app and the extension.
nonisolated enum SharedSessions {
    static let changed = Notification.Name("com.hreinsson.SavedFeeds.sessionsChanged")

    private static var file: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SessionGroup") as? String else { return nil }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appending(path: "sessions.json")
    }

    /// Extension side: service raw value → session cookie value.
    static func hand(_ sessions: [String: String]) {
        guard let file, let data = try? JSONEncoder().encode(sessions) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        #if os(macOS)
        DistributedNotificationCenter.default().postNotificationName(changed, object: nil, userInfo: nil, deliverImmediately: true)
        #endif
    }

    /// App side: whatever was handed over since last time.
    static func take() -> [String: String] {
        guard let file, let data = try? Data(contentsOf: file) else { return [:] }
        try? FileManager.default.removeItem(at: file)
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
}
