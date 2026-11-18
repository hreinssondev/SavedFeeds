import Foundation
import OSLog
import WebKit

/// `log stream --predicate 'subsystem == "com.hreinsson.SavedFeeds"'`
nonisolated let log = Logger(subsystem: "com.hreinsson.SavedFeeds", category: "feeds")

/// Sign-ins happen in a web view (or Safari); the feeds reuse its cookies.
enum WebSession {
    /// Sent by the sign-in web view and by every feed request, so both look like the same Safari.
    /// Safari's own once the extension has handed it over, since its sessions were made with it.
    static var userAgent: String {
        get { UserDefaults.standard.string(forKey: "safariUserAgent") ?? fallbackUserAgent }
        set { UserDefaults.standard.set(newValue, forKey: "safariUserAgent") }
    }

    private static let fallbackUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    static var store: WKWebsiteDataStore { .default() }

    static func cookies(for domain: String) async -> [HTTPCookie] {
        await store.httpCookieStore.allCookies().filter { cookie in
            let host = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host == domain || host.hasSuffix("." + domain)
        }
    }

    static func cookie(_ name: String, for domain: String) async -> String? {
        await cookies(for: domain)
            .first { $0.name == name && ($0.expiresDate ?? .distantFuture) > .now }?
            .value
    }

    static func setCookie(_ name: String, _ value: String, for domain: String) async {
        guard let cookie = HTTPCookie(properties: [
            .name: name,
            .value: value,
            .domain: "." + domain,
            .path: "/",
            .secure: "TRUE",
            .expires: Date.now.addingTimeInterval(365 * 24 * 3600),
        ]) else { return }
        await store.httpCookieStore.setCookie(cookie)
    }

    static func setCookies(_ cookies: [HTTPCookie]) async {
        for cookie in cookies {
            await store.httpCookieStore.setCookie(cookie)
        }
    }

    static func clear(_ domain: String) async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records.filter { $0.displayName.contains(domain) })
    }
}

extension Service {
    var loginURL: URL {
        switch self {
        case .reddit: URL(string: "https://www.reddit.com/login/")!
        case .instagram: URL(string: "https://www.instagram.com/accounts/login/")!
        }
    }

    var cookieDomain: String {
        switch self {
        case .reddit: "reddit.com"
        case .instagram: "instagram.com"
        }
    }

    /// The cookie that exists only while signed in.
    var sessionCookie: String {
        switch self {
        case .reddit: "reddit_session"
        case .instagram: "sessionid"
        }
    }

    func isSignedIn() async -> Bool {
        await WebSession.cookie(sessionCookie, for: cookieDomain) != nil
    }

    func signOut() async {
        await WebSession.clear(cookieDomain)
    }

    /// Adopts a session signed in elsewhere (Safari, with a passkey or Google), from its session cookie's value.
    func useSession(_ pasted: String) async {
        var value = pasted.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
        if value.hasPrefix(sessionCookie + "=") { value.removeFirst(sessionCookie.count + 1) }
        guard !value.isEmpty else { return }
        await WebSession.setCookie(sessionCookie, value, for: cookieDomain)
    }
}
