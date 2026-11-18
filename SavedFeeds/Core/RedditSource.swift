import Foundation

/// Saved posts and comments, from the private feed link if one is set, otherwise the reddit.com session.
final class RedditSource: FeedSource {
    let service = Service.reddit
    private var username: (session: String, name: String)?

    func page(after cursor: String?) async throws -> FeedPage {
        if let feed = Credentials.redditFeedURL.flatMap(URL.init(string:)) {
            do {
                let (data, _) = try await WebSession.data(from: Self.pageURL(feed, after: cursor))
                return try RedditParser.page(from: data)
            } catch FeedError.signedOut {
                throw FeedError.badFeedLink
            }
        }
        guard let session = await WebSession.cookie(Service.reddit.sessionCookie, for: "reddit.com") else {
            throw FeedError.notConnected
        }
        let name = try await currentUsername(session: session)
        let saved = URL(string: "https://www.reddit.com/user/\(name)/saved.json")!
        let (data, _) = try await WebSession.data(from: Self.pageURL(saved, after: cursor), cookiesFor: "reddit.com")
        return try RedditParser.page(from: data)
    }

    private func currentUsername(session: String) async throws -> String {
        if let username, username.session == session { return username.name }
        struct Me: Decodable {
            struct Account: Decodable { let name: String }
            let data: Account?
        }
        let (data, _) = try await WebSession.data(from: URL(string: "https://www.reddit.com/api/me.json")!, cookiesFor: "reddit.com")
        guard let name = (try? JSONDecoder().decode(Me.self, from: data))?.data?.name else { throw FeedError.signedOut }
        username = (session, name)
        return name
    }

    /// `base` with paging added. Takes the feed page's RSS link too.
    static func pageURL(_ base: URL, after cursor: String?) -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix(".rss") { path.removeLast(4) }
        if !path.hasSuffix(".json") { path += ".json" }
        components.path = path
        var items = (components.queryItems ?? []).filter { !["after", "limit", "raw_json"].contains($0.name) }
        items.append(URLQueryItem(name: "limit", value: "100"))
        // Unescaped URLs and text instead of &amp;.
        items.append(URLQueryItem(name: "raw_json", value: "1"))
        if let cursor { items.append(URLQueryItem(name: "after", value: cursor)) }
        components.queryItems = items
        return components.url ?? base
    }
}

/// Reads a Reddit listing (`/saved.json`).
enum RedditParser {
    static func page(from data: Data) throws -> FeedPage {
        guard let listing = try? JSONDecoder().decode(Listing.self, from: data) else { throw FeedError.unreadable }
        return FeedPage(posts: listing.data.children.compactMap(post), next: listing.data.after)
    }

    static func post(from thing: Thing) -> SavedPost? {
        guard let item = thing.data, let permalink = URL(string: "https://www.reddit.com" + item.permalink) else { return nil }
        let date = Date(timeIntervalSince1970: item.created_utc)
        if thing.kind == "t1" {
            return SavedPost(
                id: item.name, service: .reddit, author: item.author ?? "[deleted]",
                community: item.subreddit_name_prefixed, title: item.link_title, text: item.body,
                permalink: permalink, link: nil, media: [], date: date,
                score: item.score, comments: nil, isComment: true
            )
        }
        // A crosspost's media lives on the original.
        let origin = item.crosspost_parent_list?.first ?? item
        return SavedPost(
            id: item.name, service: .reddit, author: item.author ?? "[deleted]",
            community: item.subreddit_name_prefixed, title: item.title,
            text: item.selftext?.isEmpty == false ? item.selftext : nil,
            permalink: permalink, link: origin.externalLink, media: media(of: origin), date: date,
            score: item.score, comments: item.num_comments
        )
    }

    static func media(of item: Item) -> [Media] {
        if let gallery = item.gallery_data?.items, let metadata = item.media_metadata {
            return gallery.compactMap { metadata[$0.media_id]?.media }
        }
        let poster = item.preview?.images?.first?.source
        if let video = item.secure_media?.reddit_video ?? item.media?.reddit_video ?? item.preview?.reddit_video_preview {
            return [video.media(poster: poster)].compactMap(\.self)
        }
        if let mp4 = item.preview?.images?.first?.variants?.mp4?.source, let video = URL(string: mp4.url) {
            return [Media(kind: .loop, image: poster.flatMap { URL(string: $0.url) }, video: video, width: mp4.width, height: mp4.height)]
        }
        if let poster, let image = URL(string: poster.url) {
            return [Media(kind: .image, image: image, video: nil, width: poster.width, height: poster.height)]
        }
        if let url = item.url.flatMap(URL.init(string:)), ["jpg", "jpeg", "png", "webp"].contains(url.pathExtension.lowercased()) {
            return [Media(kind: .image, image: url, video: nil, width: nil, height: nil)]
        }
        return []
    }

    // Field names mirror Reddit's JSON.

    struct Listing: Decodable {
        struct Body: Decodable {
            let children: [Thing]
            let after: String?
        }
        let data: Body
    }

    struct Thing: Decodable {
        let kind: String
        let data: Item?

        enum CodingKeys: CodingKey { case kind, data }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(String.self, forKey: .kind)
            // One odd item shouldn't sink the page.
            data = try? container.decode(Item.self, forKey: .data)
        }
    }

    struct Item: Decodable {
        let name: String
        let permalink: String
        let created_utc: Double
        let author: String?
        let subreddit_name_prefixed: String?
        let title: String?
        let selftext: String?
        let body: String?
        let link_title: String?
        let url: String?
        let is_self: Bool?
        let post_hint: String?
        let score: Int?
        let num_comments: Int?
        let preview: Preview?
        let media: MediaBox?
        let secure_media: MediaBox?
        let gallery_data: Gallery?
        let media_metadata: [String: MediaMetadata]?
        let crosspost_parent_list: [Item]?

        var externalLink: URL? {
            guard is_self != true, post_hint != "image",
                  let url = url.flatMap(URL.init(string:)), let host = url.host()
            else { return nil }
            let onReddit = ["reddit.com", "redd.it"].contains { host == $0 || host.hasSuffix("." + $0) }
            return onReddit ? nil : url
        }
    }

    struct Preview: Decodable {
        let images: [PreviewImage]?
        let reddit_video_preview: Video?
    }

    struct PreviewImage: Decodable {
        struct Variants: Decodable { let mp4: Variant? }
        struct Variant: Decodable { let source: Size }
        let source: Size
        let variants: Variants?
    }

    struct Size: Decodable {
        let url: String
        let width: Int?
        let height: Int?
    }

    struct Video: Decodable {
        let hls_url: String?
        let fallback_url: String?
        let width: Int?
        let height: Int?
        let is_gif: Bool?

        func media(poster: Size?) -> Media? {
            guard let video = (hls_url ?? fallback_url).flatMap(URL.init(string:)) else { return nil }
            return Media(
                kind: is_gif == true ? .loop : .video, image: poster.flatMap { URL(string: $0.url) }, video: video,
                width: width ?? poster?.width, height: height ?? poster?.height
            )
        }
    }

    struct MediaBox: Decodable {
        let reddit_video: Video?
    }

    struct Gallery: Decodable {
        struct Entry: Decodable { let media_id: String }
        let items: [Entry]
    }

    struct MediaMetadata: Decodable {
        struct Source: Decodable {
            let u: String?
            let gif: String?
            let mp4: String?
            let x: Int?
            let y: Int?
        }
        let s: Source?

        var media: Media? {
            guard let s else { return nil }
            if let mp4 = s.mp4.flatMap(URL.init(string:)) {
                return Media(kind: .loop, image: (s.gif ?? s.u).flatMap(URL.init(string:)), video: mp4, width: s.x, height: s.y)
            }
            guard let image = (s.u ?? s.gif).flatMap(URL.init(string:)) else { return nil }
            return Media(kind: .image, image: image, video: nil, width: s.x, height: s.y)
        }
    }
}
