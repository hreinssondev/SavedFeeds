import Foundation

enum Service: String, Codable, CaseIterable, Identifiable {
    case reddit, instagram

    var id: Self { self }

    var name: String {
        switch self {
        case .reddit: "Reddit"
        case .instagram: "Instagram"
        }
    }
}

/// One saved item, normalized from either service.
struct SavedPost: Identifiable, Hashable, Codable {
    let id: String
    let service: Service
    let author: String
    /// The subreddit ("r/swift") for Reddit posts.
    let community: String?
    let title: String?
    let text: String?
    let permalink: URL
    /// Where a Reddit link post points, when that's off Reddit.
    let link: URL?
    let media: [Media]
    let date: Date
    let score: Int?
    let comments: Int?
    var isComment = false
}

struct Media: Hashable, Codable {
    enum Kind: String, Codable {
        case image
        case video
        /// A silent, looping clip (GIFs).
        case loop
    }

    let kind: Kind
    /// The picture, or a video's poster frame.
    let image: URL?
    let video: URL?
    let width: Int?
    let height: Int?

    var aspectRatio: Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return Double(width) / Double(height)
    }
}
