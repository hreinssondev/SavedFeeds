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
        #if DEBUG
        if let demo = DemoData.posts(for: source.service) { posts = demo }
        #endif
    }

    var canLoadMore: Bool { loadedFirstPage && next != nil }

    func refresh() async {
        #if DEBUG
        if DemoData.folder != nil { return }
        #endif
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
            #if os(macOS)
            // The session works: share it with the iPhone app.
            await SessionSync.publish(service)
            #endif
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
    /// Posts whose comments are open below them.
    private(set) var openComments: Set<String> = []
    /// Loaded comments, kept so reopening is instant.
    @ObservationIgnored private var commentModels: [String: CommentsModel] = [:]

    func comments(for post: SavedPost) -> CommentsModel {
        if let model = commentModels[post.id] { return model }
        let model = CommentsModel(post: post)
        commentModels[post.id] = model
        return model
    }

    func toggleComments(for post: SavedPost) {
        if openComments.remove(post.id) == nil { openComments.insert(post.id) }
    }

    func closeAllComments() {
        openComments.removeAll()
    }

    /// A post opened full size from the two-abreast feed.
    private(set) var openedPost: SavedPost?
    @ObservationIgnored private var openedPostHadComments = false

    func open(_ post: SavedPost) {
        openedPostHadComments = openComments.contains(post.id)
        openedPost = post
    }

    /// Comments opened while the post was open close with it.
    func closeOpenedPost() {
        if let post = openedPost, !openedPostHadComments { openComments.remove(post.id) }
        openedPost = nil
    }

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

    /// iPhone: adopts sign-ins the Mac app shared through iCloud Keychain; returns the services to reload.
    @discardableResult
    func importMacSessions() async -> [Service] {
        var changed: [Service] = []
        for service in Service.allCases {
            guard let session = SessionSync.take(service, phoneSignedIn: await service.isSignedIn()) else { continue }
            if let userAgent = session.userAgent { WebSession.userAgent = userAgent }
            await WebSession.clear(service.cookieDomain)
            await WebSession.setCookies(session.cookies.compactMap(\.httpCookie))
            SitePage.for(service).reload()
            log.info("Took the Mac's \(service.rawValue, privacy: .public) session from iCloud Keychain")
            changed.append(service)
        }
        return changed
    }

    func syncMacSessions() async {
        for service in await importMacSessions() {
            await feed(for: service).refresh()
        }
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
