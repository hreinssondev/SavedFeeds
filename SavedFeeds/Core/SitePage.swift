import Foundation
import WebKit

/// A hidden tab on a site. Fetching from inside it sends what the website itself sends (every cookie the site sets,
/// browser headers, same origin). Reddit blocks bare requests and Instagram bounces them, even with the session.
final class SitePage: NSObject, WKNavigationDelegate {
    static let reddit = SitePage(home: URL(string: "https://www.reddit.com/")!)
    static let instagram = SitePage(home: URL(string: "https://www.instagram.com/")!)

    static func `for`(_ service: Service) -> SitePage {
        switch service {
        case .reddit: reddit
        case .instagram: instagram
        }
    }

    struct Response {
        let status: Int
        /// Where it ended up after redirects.
        let path: String
        let body: Data
    }

    private let home: URL
    private let webView: WKWebView
    private var loading: CheckedContinuation<Void, Error>?
    private var isReady = false

    private init(home: URL) {
        self.home = home
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WebSession.store
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    /// The web view, for iOS to keep in a window (it only runs pages that are in one).
    var hostedView: WKWebView { webView }

    /// Loads the site afresh before the next fetch (after its cookies changed).
    func reload() {
        isReady = false
    }

    /// GETs `pathAndQuery` on the site. `instagram` adds the headers instagram.com's own requests carry.
    func fetch(_ pathAndQuery: String, instagram: Bool = false) async throws -> Response {
        if !isReady || webView.url?.host() != home.host() || webView.customUserAgent != WebSession.userAgent {
            try await load()
        }
        let result: Any?
        do {
            result = try await webView.callAsyncJavaScript(
                Self.fetchScript, arguments: ["path": pathAndQuery, "instagram": instagram], contentWorld: .defaultClient
            )
        } catch {
            isReady = false
            throw FeedError.failed("Couldn't ask \(home.host() ?? "the site"): \(error.localizedDescription)")
        }
        guard let result = result as? [String: Any],
              let status = (result["status"] as? NSNumber)?.intValue,
              let body = result["body"] as? String
        else { throw FeedError.unreadable }
        let path = (result["url"] as? String).flatMap(URL.init(string:))?.path() ?? ""
        // Paths only: queries can hold the Reddit feed token.
        let requested = pathAndQuery.prefix { $0 != "?" }
        log.info("GET \(self.home.host() ?? "", privacy: .public)\(requested, privacy: .public) → \(status) at \(path, privacy: .public)")
        if !(200..<300).contains(status) {
            log.error("\(status) body: \(String(body.prefix(400)), privacy: .public)")
        }
        return Response(status: status, path: path, body: Data(body.utf8))
    }

    private static let fetchScript = """
        const headers = { "Accept": "application/json" };
        if (instagram) {
            headers["X-IG-App-ID"] = "936619743392459";
            headers["X-ASBD-ID"] = "359341";
            headers["X-IG-WWW-Claim"] = sessionStorage.getItem("www-claim-v2") ?? "0";
            headers["X-Requested-With"] = "XMLHttpRequest";
            const csrf = document.cookie.match(/(?:^|; )csrftoken=([^;]*)/)?.[1];
            if (csrf) headers["X-CSRFToken"] = csrf;
        }
        const response = await fetch(path, { credentials: "include", headers });
        return { status: response.status, url: response.url, body: await response.text() };
        """

    private func load() async throws {
        isReady = false
        webView.customUserAgent = WebSession.userAgent
        let timeout = Task {
            try await Task.sleep(for: .seconds(30))
            finishLoading(.failure(FeedError.failed("\(home.host() ?? "The site") took too long to load.")))
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { continuation in
            loading = continuation
            webView.load(URLRequest(url: home))
        }
        await waitForBotCheck()
        isReady = true
    }

    /// Reddit answers new visitors with a check page that solves a puzzle and submits itself;
    /// requests before that's done get blocked.
    private func waitForBotCheck() async {
        for _ in 0..<40 {
            let pending = try? await webView.evaluateJavaScript(
                #"document.readyState !== "complete" || document.querySelector('input[name="solution"]') !== null"#
            ) as? Bool
            if pending == false { return }
            try? await Task.sleep(for: .milliseconds(500))
        }
        log.error("\(self.home.host() ?? "", privacy: .public) still checking after 20 s")
    }

    private func finishLoading(_ result: Result<Void, Error>) {
        loading?.resume(with: result)
        loading = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoading(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failLoading(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failLoading(error)
    }

    private func failLoading(_ error: Error) {
        // Superseded by a redirect; the next navigation finishes the load.
        if (error as? URLError)?.code == .cancelled { return }
        finishLoading(.failure(FeedError.failed(error.localizedDescription)))
    }
}
