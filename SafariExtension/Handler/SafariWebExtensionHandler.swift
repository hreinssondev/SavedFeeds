import Foundation
import SafariServices

/// Receives `browser.runtime.sendNativeMessage` from background.js.
nonisolated final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        if let sessions = message?["sessions"] as? [String: String], !sessions.isEmpty {
            SharedSessions.hand(sessions)
        }
        context.completeRequest(returningItems: [], completionHandler: nil)
    }
}
