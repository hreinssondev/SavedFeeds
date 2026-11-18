import Foundation
import Observation

struct Comment: Identifiable, Hashable {
    let id: String
    let author: String
    let text: String
    let score: Int?
    let date: Date?
    var isSubmitter = false
    var replies: [Comment] = []
    /// Replies there are but weren't loaded (Reddit's "more", Instagram's beyond the preview).
    var moreReplies = 0
}

struct CommentPage {
    let comments: [Comment]
    /// Cursor for more top-level comments; nil at the end.
    let next: String?
    /// Top-level comments not loaded and not reachable by `next` (Reddit's "more").
    var more = 0
    /// All comments on the post, when the service says.
    var total: Int?
}

/// Reddit's comment orders.
enum CommentSort: String, CaseIterable, Identifiable {
    case best = "confidence", top, new, controversial, old, qa

    var id: Self { self }

    var title: String {
        switch self {
        case .best: "Best"
        case .top: "Top"
        case .new: "New"
        case .controversial: "Controversial"
        case .old: "Old"
        case .qa: "Q&A"
        }
    }
}

/// One post's comments.
@Observable
final class CommentsModel {
    let post: SavedPost
    /// Reddit only; Instagram has its own order.
    private(set) var sort = CommentSort.best
    private(set) var comments: [Comment] = []
    private(set) var more = 0
    private(set) var total: Int?
    private(set) var isLoading = false
    private(set) var problem: FeedError?
    private var next: String?

    init(post: SavedPost) {
        self.post = post
    }

    var canLoadMore: Bool { next != nil }

    func load() async {
        guard comments.isEmpty else { return }
        await fetch(after: nil)
    }

    func loadMore() async {
        guard let next else { return }
        await fetch(after: next)
    }

    /// Fetches the comments again, replacing them when they arrive.
    func reload() async {
        await fetch(after: nil, replacing: true)
    }

    func sort(by sort: CommentSort) async {
        guard sort != self.sort else { return }
        self.sort = sort
        await reload()
    }

    /// Instagram's replies to a top-level comment (it previews none).
    func loadReplies(to commentID: String) async {
        guard post.service == .instagram, let mediaID = post.mediaID,
              let index = comments.firstIndex(where: { $0.id == commentID })
        else { return }
        do {
            var replies: [Comment] = []
            var cursor: String?
            repeat {
                var path = "/api/v1/media/\(mediaID)/comments/\(commentID)/child_comments/"
                if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
                    path += "?max_id=" + encoded
                }
                let response = try await SitePage.instagram.fetch(path, instagram: true)
                guard (200..<300).contains(response.status) else { throw FeedError.http(response.status) }
                let page = try InstagramComments.replies(from: response.body)
                replies += page.comments
                cursor = page.next
            } while cursor != nil && replies.count < 200
            let known = Set(replies.map(\.id))
            comments[index].replies = comments[index].replies.filter { !known.contains($0.id) } + replies
            comments[index].moreReplies = 0
        } catch {
            problem = error as? FeedError ?? .failed(error.localizedDescription)
            log.error("replies: \(String(describing: self.problem), privacy: .public)")
        }
    }

    private func fetch(after cursor: String?, replacing: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await Self.page(for: post, after: cursor, sort: sort)
            if replacing {
                comments = page.comments
            } else {
                let known = Set(comments.map(\.id))
                comments += page.comments.filter { !known.contains($0.id) }
            }
            next = page.next
            more = page.more
            total = page.total ?? total
            problem = nil
        } catch {
            problem = error as? FeedError ?? .failed(error.localizedDescription)
            log.error("comments: \(String(describing: self.problem), privacy: .public)")
        }
    }

    private static func page(for post: SavedPost, after cursor: String?, sort: CommentSort) async throws -> CommentPage {
        #if DEBUG
        if let data = DemoData.comments(for: post.service) {
            return post.service == .reddit ? try RedditComments.page(from: data) : try InstagramComments.page(from: data)
        }
        #endif
        switch post.service {
        case .reddit:
            // The permalink's JSON: the post, then its comment tree (rooted at the comment for a saved comment).
            var components = URLComponents(url: post.permalink, resolvingAgainstBaseURL: false)!
            var path = components.path
            if path.hasSuffix("/") { path.removeLast() }
            components.path = path + ".json"
            components.queryItems = [
                URLQueryItem(name: "raw_json", value: "1"),
                URLQueryItem(name: "limit", value: "200"),
                URLQueryItem(name: "sort", value: sort.rawValue),
            ]
            return try RedditComments.page(from: try await RedditSource.get(components.url!))
        case .instagram:
            guard let mediaID = post.mediaID else {
                throw FeedError.failed("Refresh the feed to load this post's comments.")
            }
            var path = "/api/v1/media/\(mediaID)/comments/?can_support_threading=true&permalink_enabled=false"
            if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
                path += "&min_id=" + encoded
            }
            let response = try await SitePage.instagram.fetch(path, instagram: true)
            if response.path.hasPrefix("/accounts/login") || response.status == 401 || response.status == 403 {
                throw FeedError.signedOut
            }
            guard (200..<300).contains(response.status) else { throw FeedError.http(response.status) }
            return try InstagramComments.page(from: response.body)
        }
    }
}

/// Reads a Reddit permalink's `.json`: `[post listing, comment listing]`.
enum RedditComments {
    static func page(from data: Data) throws -> CommentPage {
        guard let listings = try? JSONDecoder().decode([Listing].self, from: data), listings.count > 1 else {
            throw FeedError.unreadable
        }
        let (comments, more) = convert(listings[1].data.children)
        return CommentPage(comments: comments, next: nil, more: more)
    }

    /// Comments, plus how many more there are behind "more" stubs.
    private static func convert(_ things: [Thing]) -> ([Comment], Int) {
        var comments: [Comment] = []
        var more = 0
        for thing in things {
            switch thing.kind {
            case "t1":
                let data = thing.data
                guard let id = data.name else { continue }
                var comment = Comment(
                    id: id, author: data.author ?? "[deleted]", text: data.body ?? "",
                    score: data.score, date: data.created_utc.map { Date(timeIntervalSince1970: $0) },
                    isSubmitter: data.is_submitter == true
                )
                (comment.replies, comment.moreReplies) = convert(data.replies?.data.children ?? [])
                comments.append(comment)
            case "more":
                more += thing.data.count ?? 0
            default:
                continue
            }
        }
        return (comments, more)
    }

    // Field names mirror Reddit's JSON.

    struct Listing: Decodable {
        struct Body: Decodable { let children: [Thing] }
        let data: Body
    }

    struct Thing: Decodable {
        let kind: String
        let data: Fields
    }

    struct Fields: Decodable {
        let name: String?
        let author: String?
        let body: String?
        let score: Int?
        let created_utc: Double?
        let is_submitter: Bool?
        let count: Int?
        /// A listing, or "" when there are none.
        let replies: Listing?

        enum CodingKeys: CodingKey { case name, author, body, score, created_utc, is_submitter, count, replies }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try? container.decode(String.self, forKey: .name)
            author = try? container.decode(String.self, forKey: .author)
            body = try? container.decode(String.self, forKey: .body)
            score = try? container.decode(Int.self, forKey: .score)
            created_utc = try? container.decode(Double.self, forKey: .created_utc)
            is_submitter = try? container.decode(Bool.self, forKey: .is_submitter)
            count = try? container.decode(Int.self, forKey: .count)
            replies = try? container.decode(Listing.self, forKey: .replies)
        }
    }
}

/// Reads `/api/v1/media/<id>/comments/`.
enum InstagramComments {
    static func page(from data: Data) throws -> CommentPage {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw FeedError.unreadable }
        if response.message == "login_required" { throw FeedError.signedOut }
        guard let comments = response.comments else {
            throw response.message.map { FeedError.failed("Instagram said: \($0)") } ?? .unreadable
        }
        // Ranked comments page from the top ("headload"); the plain flag stays false.
        let more = response.has_more_headload_comments == true || response.has_more_comments == true
        return CommentPage(
            comments: comments.compactMap(\.comment), next: more ? response.next_min_id?.value : nil,
            total: response.comment_count
        )
    }

    /// Reads `/api/v1/media/<id>/comments/<comment id>/child_comments/`.
    static func replies(from data: Data) throws -> CommentPage {
        guard let response = try? JSONDecoder().decode(RepliesResponse.self, from: data), let replies = response.child_comments else {
            throw FeedError.unreadable
        }
        let more = response.has_more_tail_child_comments == true
        return CommentPage(comments: replies.compactMap(\.comment), next: more ? response.next_max_child_cursor?.value : nil)
    }

    // Field names mirror Instagram's JSON.

    struct RepliesResponse: Decodable {
        let child_comments: [Item]?
        let has_more_tail_child_comments: Bool?
        let next_max_child_cursor: InstagramParser.LooseString?
    }

    struct Response: Decodable {
        let comments: [Item]?
        let next_min_id: InstagramParser.LooseString?
        let has_more_comments: Bool?
        let has_more_headload_comments: Bool?
        let comment_count: Int?
        let message: String?
    }

    struct Item: Decodable {
        struct User: Decodable { let username: String? }
        let pk: InstagramParser.LooseString?
        let text: String?
        let created_at: Double?
        let user: User?
        let comment_like_count: Int?
        let child_comment_count: Int?
        let preview_child_comments: [Item]?

        var comment: Comment? {
            guard let pk, let text else { return nil }
            let replies = preview_child_comments?.compactMap(\.comment) ?? []
            return Comment(
                id: pk.value, author: user?.username ?? "", text: text,
                score: comment_like_count, date: created_at.map { Date(timeIntervalSince1970: $0) },
                replies: replies, moreReplies: max((child_comment_count ?? 0) - replies.count, 0)
            )
        }
    }
}
