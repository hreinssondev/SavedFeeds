import Foundation
import WebKit

/// Sign-ins happen in a web view; the feeds reuse its cookies.
enum WebSession {
    /// Sent by the sign-in web view and by every feed request, so both look like the same Safari.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    static var store: WKWebsiteDataStore { .default() }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

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

    static func clear(_ domain: String) async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records.filter { $0.displayName.contains(domain) })
    }

    /// GETs `url`, sending the signed-in cookies for `domain` when one is given.
    static func data(from url: URL, cookiesFor domain: String? = nil, headers: [String: String] = [:]) async throws -> (Data, URL?) {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let domain {
            for (field, value) in HTTPCookie.requestHeaderFields(with: await cookies(for: domain)) {
                request.setValue(value, forHTTPHeaderField: field)
            }
        }
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FeedError.failed(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return (data, response.url)
        case 401, 403: throw FeedError.signedOut
        default: throw FeedError.http(status)
        }
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
}
