import SwiftUI

struct FeedColumn: View {
    let feed: FeedModel
    @Environment(AppModel.self) private var app
    /// The post at the top of the column.
    @State private var topPostID: String?
    @AppStorage(FeedZoom.key) private var zoom = 1.0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let problem = feed.problem, !feed.posts.isEmpty {
                banner(problem)
                Divider()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ServiceBadge(service: feed.service)
            Text(feed.service.name)
                .font(.headline)
            if !feed.posts.isEmpty {
                Text("\(feed.posts.count)\(feed.canLoadMore ? "+" : "")")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if feed.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Button { Task { await feed.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            .disabled(feed.isLoading)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    @ViewBuilder
    private var content: some View {
        if feed.posts.isEmpty {
            switch feed.problem {
            case .notConnected?:
                ConnectView(service: feed.service)
            case let problem?:
                ContentUnavailableView {
                    Label("Couldn't Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(problem.localizedDescription)
                } actions: {
                    actions(for: problem)
                }
            case nil:
                if feed.isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView("No Saved Posts", systemImage: "bookmark")
                }
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(feed.posts) { post in
                            PostCard(post: post)
                                .id(post.id)
                        }
                        if feed.canLoadMore {
                            ProgressView()
                                .padding()
                                // Runs when the end scrolls into view, and again after each page while it stays visible.
                                .task(id: feed.posts.count) { await feed.loadMore() }
                        }
                    }
                    .scrollTargetLayout()
                    .zoomedFont(.body)
                    .frame(maxWidth: FeedZoom.width * zoom)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
                .scrollPosition(id: $topPostID, anchor: .top)
                .environment(\.feedZoom, zoom)
                // Closing the comments you were scrolled into would leave you further down the feed; go back to their post.
                .onChange(of: app.openComments) { old, new in
                    if let id = topPostID, old.subtracting(new).contains(id) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
        }
    }

    private func banner(_ problem: FeedError) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(problem.localizedDescription)
                .lineLimit(2)
            Spacer()
            actions(for: problem)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.08))
    }

    @ViewBuilder
    private func actions(for problem: FeedError) -> some View {
        switch problem {
        case .signedOut:
            Button("Sign In…") { app.signingIn = feed.service }
        case .badFeedLink:
            SettingsLink { Text("Open Settings…") }
        default:
            Button("Try Again") { Task { await feed.refresh() } }
        }
    }
}

struct ConnectView: View {
    let service: Service
    @Environment(AppModel.self) private var app

    var body: some View {
        ContentUnavailableView {
            Label("Connect \(service.name)", systemImage: service.symbol)
        } description: {
            switch service {
            case .reddit:
                Text("Paste your private saved-links feed in Settings, or sign in on reddit.com.")
            case .instagram:
                Text("Sign in on instagram.com. Instagram has no official API for saved posts, so SavedFeeds reads them through your web session.")
            }
        } actions: {
            if service == .reddit {
                SettingsLink { Text("Add Feed Link…") }
            }
            Button("Sign In…") { app.signingIn = service }
            if service == .instagram {
                SettingsLink { Text("Sign In with Safari…") }
            }
        }
    }
}

struct ServiceBadge: View {
    let service: Service

    var body: some View {
        Image(systemName: service.symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(service.tint, in: .circle)
    }
}

extension Service {
    var symbol: String {
        switch self {
        case .reddit: "bubble.left.and.bubble.right.fill"
        case .instagram: "camera.fill"
        }
    }

    var tint: AnyShapeStyle {
        switch self {
        case .reddit:
            AnyShapeStyle(Color(red: 1, green: 0.27, blue: 0))
        case .instagram:
            AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.98, green: 0.65, blue: 0.2), Color(red: 0.91, green: 0.2, blue: 0.45), Color(red: 0.55, green: 0.24, blue: 0.85)],
                startPoint: .bottomLeading, endPoint: .topTrailing
            ))
        }
    }
}
