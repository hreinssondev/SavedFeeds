import SwiftUI

@main
struct SavedFeedsiOSApp: App {
    @State private var app = AppModel()

    init() {
        // AsyncImage goes through the shared cache; give it room for a feed's worth of media.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
        Playback.quiet()
    }

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environment(app)
        }
    }
}
