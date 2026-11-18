#if DEBUG
import Foundation

/// For trying the UI without accounts, as in the iOS Simulator: launch with `-demoData <folder>`. The folder holds
/// reddit.json and instagram.json (arrays of SavedPost, the feed cache's format) and, optionally,
/// reddit-comments.json and instagram-comments.json (the services' own comment responses). Feeds then don't refresh.
enum DemoData {
    static var folder: URL? {
        UserDefaults.standard.string(forKey: "demoData").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func posts(for service: Service) -> [SavedPost]? {
        guard let folder, let data = try? Data(contentsOf: folder.appending(path: "\(service.rawValue).json")) else {
            return nil
        }
        return try? JSONDecoder().decode([SavedPost].self, from: data)
    }

    static func comments(for service: Service) -> Data? {
        guard let folder else { return nil }
        return try? Data(contentsOf: folder.appending(path: "\(service.rawValue)-comments.json"))
    }
}
#endif
