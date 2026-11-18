import Foundation

struct FeedPage {
    let posts: [SavedPost]
    /// Cursor for the next page; nil at the end.
    let next: String?
}

protocol FeedSource {
    var service: Service { get }
    func page(after cursor: String?) async throws -> FeedPage
}

enum FeedError: LocalizedError, Equatable {
    case notConnected
    case signedOut
    case badFeedLink
    case http(Int)
    case unreadable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected."
        case .signedOut: "Your session expired. Sign in again."
        case .badFeedLink: "Reddit rejected the feed link. Copy it again from old.reddit.com/prefs/feeds."
        case .http(let status): "The server answered \(status) (\(HTTPURLResponse.localizedString(forStatusCode: status)))."
        case .unreadable: "The response couldn't be read. The service may have changed its format."
        case .failed(let message): message
        }
    }
}
