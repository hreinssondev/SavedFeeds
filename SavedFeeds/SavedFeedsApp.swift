import SwiftUI

@main
struct SavedFeedsApp: App {
    @State private var app = AppModel()

    init() {
        // AsyncImage goes through the shared cache; give it room for a feed's worth of media.
        URLCache.shared = URLCache(memoryCapacity: 128 << 20, diskCapacity: 1 << 30)
    }

    var body: some Scene {
        WindowGroup("SavedFeeds") {
            RootView()
                .environment(app)
        }
        // Opens filling the screen.
        .defaultWindowPlacement { _, context in
            WindowPlacement(size: context.defaultDisplay.visibleRect.size)
        }
        .commands {
            CommandGroup(before: .toolbar) {
                Button("Refresh") { Task { await app.refreshAll() } }
                    .keyboardShortcut("r")
                Divider()
            }
        }

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}
