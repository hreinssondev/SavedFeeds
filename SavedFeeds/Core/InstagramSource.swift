import Foundation

/// Saved posts through the instagram.com web session. Unofficial: Instagram has no API for these,
/// so this calls the endpoint instagram.com's own "Saved" page uses.
struct InstagramSource: FeedSource {
    let service = Service.instagram

    func page(after cursor: String?) async throws -> FeedPage {
        guard await service.isSignedIn() else { throw FeedError.notConnected }
        var components = URLComponents(string: "https://www.instagram.com/api/v1/feed/saved/posts/")!
        if let cursor { components.queryItems = [URLQueryItem(name: "max_id", value: cursor)] }
        var headers = [
            "X-IG-App-ID": "936619743392459", // instagram.com's web app
            "X-Requested-With": "XMLHttpRequest",
            "Referer": "https://www.instagram.com/",
            "Accept": "application/json",
        ]
        headers["X-CSRFToken"] = await WebSession.cookie("csrftoken", for: "instagram.com")
        let (data, finalURL) = try await WebSession.data(from: components.url!, cookiesFor: "instagram.com", headers: headers)
        if finalURL?.path().contains("/accounts/login") == true { throw FeedError.signedOut }
        return try InstagramParser.page(from: data)
    }
}

/// Reads `/api/v1/feed/saved/posts/`.
enum InstagramParser {
    static func page(from data: Data) throws -> FeedPage {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw FeedError.unreadable }
        if response.message == "login_required" { throw FeedError.signedOut }
        guard let items = response.items else { throw FeedError.unreadable }
        return FeedPage(
            posts: items.compactMap { $0.media.flatMap(post) },
            next: response.more_available == true ? response.next_max_id?.value : nil
        )
    }

    static func post(from item: Item) -> SavedPost? {
        guard let code = item.code, let permalink = URL(string: "https://www.instagram.com/p/\(code)/") else { return nil }
        let parts = item.carousel_media.flatMap { $0.isEmpty ? nil : $0 } ?? [item]
        return SavedPost(
            id: "ig_" + code, service: .instagram, author: item.user?.username ?? "",
            community: nil, title: nil, text: item.caption?.text,
            permalink: permalink, link: nil, media: parts.compactMap(\.media),
            date: Date(timeIntervalSince1970: item.taken_at ?? 0),
            score: item.like_count, comments: item.comment_count
        )
    }

    // Field names mirror Instagram's JSON.

    struct Response: Decodable {
        let items: [Saved]?
        let more_available: Bool?
        let next_max_id: LooseString?
        let message: String?
    }

    struct Saved: Decodable {
        let media: Item?

        enum CodingKeys: CodingKey { case media }

        init(from decoder: Decoder) throws {
            // One odd item shouldn't sink the page.
            media = try? decoder.container(keyedBy: CodingKeys.self).decode(Item.self, forKey: .media)
        }
    }

    struct Item: Decodable {
        let code: String?
        let taken_at: Double?
        let image_versions2: Versions?
        let video_versions: [Candidate]?
        let carousel_media: [Item]?
        let caption: Caption?
        let user: User?
        let like_count: Int?
        let comment_count: Int?
        let original_width: Int?
        let original_height: Int?

        var media: Media? {
            let image = image_versions2?.candidates.max { ($0.width ?? 0) < ($1.width ?? 0) }
            let imageURL = image.flatMap { URL(string: $0.url) }
            let width = original_width ?? image?.width
            let height = original_height ?? image?.height
            if let video = video_versions?.first.flatMap({ URL(string: $0.url) }) {
                return Media(kind: .video, image: imageURL, video: video, width: width, height: height)
            }
            guard let imageURL else { return nil }
            return Media(kind: .image, image: imageURL, video: nil, width: width, height: height)
        }
    }

    struct Versions: Decodable { let candidates: [Candidate] }

    struct Candidate: Decodable {
        let url: String
        let width: Int?
        let height: Int?
    }

    struct Caption: Decodable { let text: String? }

    struct User: Decodable { let username: String? }

    /// Instagram sends some IDs as strings and some as numbers.
    struct LooseString: Decodable {
        let value: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                value = string
            } else {
                value = String(try container.decode(Int64.self))
            }
        }
    }
}
