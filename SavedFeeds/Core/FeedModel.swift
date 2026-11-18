import Foundation
import Observation

/// One column's posts, paging and errors.
@Observable
final class FeedModel {
    let service: Service
    private(set) var posts: [SavedPost]
    private(set) var isLoading = false
    private(set) var problem: FeedError?
    private var next: String?
    private var loadedFirstPage = false
    private let source: any FeedSource

    init(source: any FeedSource) {
        self.source = source
        service = source.service
        posts = FeedCache.load(source.service)
    }

    var canLoadMore: Bool { loadedFirstPage && next != nil }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await source.page(after: nil)
            posts = page.posts
            next = page.next
            loadedFirstPage = true
            problem = nil
            FeedCache.save(posts, for: service)
        } catch {
            problem = error as? FeedError ?? .failed(error.localizedDescription)
            log.error("\(self.service.rawValue, privacy: .public): \(String(describing: self.problem), privacy: .public)")
            if problem == .notConnected { clear() }
        }
    }

    func loadMore() async {
        guard !isLoading, loadedFirstPage, let cursor = next else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await source.page(after: cursor)
            let known = Set(posts.map(\.id))
            posts += page.posts.filter { !known.contains($0.id) }
            next = page.next
            problem = nil
            FeedCache.save(posts, for: service)
        } catch {
            problem = error as? FeedError ?? .failed(error.localizedDescription)
            log.error("\(self.service.rawValue, privacy: .public): \(String(describing: self.problem), privacy: .public)")
        }
    }

    func clear() {
        posts = []
        next = nil
        loadedFirstPage = false
        FeedCache.save([], for: service)
    }
}

@Observable
final class AppModel {
    let reddit = FeedModel(source: RedditSource())
    let instagram = FeedModel(source: InstagramSource())
    /// Shows the sign-in sheet in the main window.
    var signingIn: Service?

    func feed(for service: Service) -> FeedModel {
        switch service {
        case .reddit: reddit
        case .instagram: instagram
        }
    }

    func refreshAll() async {
        async let reddit: Void = reddit.refresh()
        async let instagram: Void = instagram.refresh()
        _ = await (reddit, instagram)
    }

    /// Adopts sign-ins the Safari extension handed over; returns the services to reload.
    @discardableResult
    func importSafariSessions() async -> [Service] {
        guard let handoff = SharedSessions.take() else { return [] }
        if let userAgent = handoff.userAgent { WebSession.userAgent = userAgent }
        var changed: [Service] = []
        for (key, cookies) in handoff.cookies {
            guard let service = Service(rawValue: key) else { continue }
            let session = cookies.first { $0.name == service.sessionCookie }?.value
            let isNew = await WebSession.cookie(service.sessionCookie, for: service.cookieDomain) != session
            guard isNew || feed(for: service).problem != nil else { continue }
            // Safari's whole set replaces ours: the session only counts alongside the visitor and device cookies it was made with.
            await WebSession.clear(service.cookieDomain)
            await WebSession.setCookies(cookies.compactMap(\.httpCookie))
            SitePage.for(service).reload()
            log.info("Safari handed over \(cookies.count) \(key, privacy: .public) cookies")
            changed.append(service)
        }
        return changed
    }

    func syncSafariSessions() async {
        for service in await importSafariSessions() {
            await feed(for: service).refresh()
        }
    }

    func signOut(_ service: Service) async {
        await service.signOut()
        feed(for: service).clear()
        await feed(for: service).refresh()
    }
}
