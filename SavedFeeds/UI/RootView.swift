import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 0) {
            FeedColumn(feed: app.reddit)
            Divider()
            FeedColumn(feed: app.instagram)
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            ToolbarItem {
                Button { Task { await app.refreshAll() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh both feeds (⌘R)")
            }
            ToolbarItem {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
            }
        }
        .task { await app.refreshAll() }
        .sheet(item: $app.signingIn) { service in
            SignInSheet(service: service) {
                Task { await app.feed(for: service).refresh() }
            }
        }
    }
}
