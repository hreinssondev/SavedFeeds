import Foundation

/// Last loaded posts per service, so the window fills instantly on launch.
enum FeedCache {
    private static func file(_ service: Service) -> URL {
        URL.applicationSupportDirectory.appending(path: "Feeds/\(service.rawValue).json")
    }

    static func load(_ service: Service) -> [SavedPost] {
        guard let data = try? Data(contentsOf: file(service)) else { return [] }
        return (try? JSONDecoder().decode([SavedPost].self, from: data)) ?? []
    }

    static func save(_ posts: [SavedPost], for service: Service) {
        let url = file(service)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(posts).write(to: url, options: .atomic)
    }
}
