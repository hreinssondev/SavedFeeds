import SwiftUI

struct FeedColumn: View {
    let feed: FeedModel
    /// Tall enough to center on the window controls, since the header bars stand in for the title bar.
    let headerHeight: CGFloat
    @State private var hoveringHeader = false
    @Environment(AppModel.self) private var app
    @State private var topEdge = TopEdge()
    @State private var columnWidth = 0.0
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

    /// The service centered in the column's bar; refreshing shows on hover (⌘R refreshes both).
    private var header: some View {
        HStack(spacing: 6) {
            ServiceBadge(service: feed.service)
            Text(feed.service.name)
                .font(.headline)
            if !feed.posts.isEmpty {
                Text("\(feed.posts.count)\(feed.canLoadMore ? "+" : "")")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            Group {
                if feed.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if hoveringHeader {
                    Button { Task { await feed.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh \(feed.service.name) (⌘R refreshes both)")
                }
            }
            .padding(.trailing, 12)
        }
        .frame(height: headerHeight)
        .contentShape(.rect)
        .onHover { hoveringHeader = $0 }
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
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
                    Group {
                        if isTwoUp {
                            // Two independent stacks, so a short post doesn't leave a gap beside a tall one.
                            HStack(alignment: .top, spacing: Self.spacing) {
                                posts(feed.posts.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element))
                                posts(feed.posts.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element))
                            }
                            .frame(maxWidth: FeedZoom.width * zoom * 2 + Self.spacing)
                        } else {
                            posts(feed.posts)
                                .frame(maxWidth: FeedZoom.width * zoom)
                        }
                    }
                    .zoomedFont(.body)
                    .padding(Self.margin)
                    .frame(maxWidth: .infinity)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columnWidth = $0 }
                .environment(\.feedZoom, zoom)
                // Closing the comments you were scrolled into would leave you further down the feed; go back to their post.
                .onChange(of: app.openComments) { old, new in
                    if let id = old.subtracting(new).first(where: topEdge.posts.contains) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
        }
    }

    private static let spacing = 16.0
    private static let margin = 20.0

    /// Zoomed out to 80 % or less, posts go two abreast when each still gets 300 pt.
    private var isTwoUp: Bool {
        zoom <= 0.8 && (columnWidth - Self.margin * 2 - Self.spacing) / 2 >= 300
    }

    private func posts(_ posts: [SavedPost]) -> some View {
        LazyVStack(spacing: Self.spacing) {
            ForEach(posts) { post in
                PostCard(post: post)
                    .modifier(OpensOnClick(enabled: isTwoUp) {
                        withAnimation(.snappy(duration: 0.2)) { app.open(post) }
                    })
                    .id(post.id)
                    .onGeometryChange(for: Bool.self) { proxy in
                        let frame = proxy.frame(in: .scrollView)
                        return frame.minY < 0 && frame.maxY > 0
                    } action: { straddles in
                        if straddles { topEdge.posts.insert(post.id) } else { topEdge.posts.remove(post.id) }
                    }
            }
            if feed.canLoadMore {
                ProgressView()
                    .padding()
                    // Runs when the end scrolls into view, and again after each page while it stays visible.
                    // Two abreast, each stack has one; whichever shows first loads the page.
                    .task(id: feed.posts.count) { await feed.loadMore() }
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

/// The posts straddling a column's top edge. Kept out of view state on purpose: it changes at every post
/// while scrolling, and is only read when comments close.
private final class TopEdge {
    var posts: Set<String> = []
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
