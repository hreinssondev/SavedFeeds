import Foundation
import SafariServices

/// Receives `browser.runtime.sendNativeMessage` from background.js.
nonisolated final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        if let handoff = message?["handoff"] as? String {
            SharedSessions.hand(Data(handoff.utf8))
        }
        context.completeRequest(returningItems: [], completionHandler: nil)
    }
}
