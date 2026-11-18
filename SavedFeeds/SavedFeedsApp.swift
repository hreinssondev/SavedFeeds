import SwiftUI

@main
struct SavedFeedsApp: App {
    @State private var app = AppModel()
    @AppStorage(FeedZoom.key) private var zoom = 1.0

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
        // No title bar or toolbar: the feeds' header bars are the top of the window.
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultWindowPlacement { _, context in
            WindowPlacement(size: context.defaultDisplay.visibleRect.size)
        }
        .commands {
            CommandGroup(before: .toolbar) {
                Button("Refresh") { Task { await app.refreshAll() } }
                    .keyboardShortcut("r")
                Divider()
                Button("Actual Size") { zoom = 1 }
                    .keyboardShortcut("0")
                    .disabled(zoom == 1)
                Button("Zoom In") { zoom = FeedZoom.zoomedIn(from: zoom) }
                    .keyboardShortcut("+")
                    .disabled(zoom >= FeedZoom.steps.last!)
                Button("Zoom Out") { zoom = FeedZoom.zoomedOut(from: zoom) }
                    .keyboardShortcut("-")
                    .disabled(zoom <= FeedZoom.steps.first!)
                Divider()
            }
        }

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}
