import SwiftUI

/// Where tapping a post goes: the post, maybe straight to its comments.
struct PostRoute: Hashable {
    let post: SavedPost
    var toComments = false
}

/// How a feed lays its posts out: whole posts, a compact list (Reddit), or a grid.
enum PhoneLayout: String, Identifiable {
    case full, compact, grid

    var id: Self { self }

    static func options(for service: Service) -> [PhoneLayout] {
        service == .reddit ? [.full, .compact, .grid] : [.full, .grid]
    }

    /// Instagram has no compact list; before Reddit had a grid, Instagram's grid was stored as "compact".
    func resolved(for service: Service) -> PhoneLayout {
        service == .instagram && self == .compact ? .grid : self
    }

    func name(for service: Service) -> String {
        switch self {
        case .full: service == .instagram ? "Feed" : "Cards"
        case .compact: "Compact"
        case .grid: "Grid"
        }
    }

    var symbol: String {
        switch self {
        case .full: "rectangle.portrait"
        case .compact: "list.bullet"
        case .grid: "square.grid.3x3"
        }
    }
}

/// One service's saved posts. Tapping a post opens it.
struct FeedScreen: View {
    let feed: FeedModel
    let query: String
    let layout: PhoneLayout
    let namespace: Namespace.ID
    /// Changes when the feed should scroll back to its top.
    let toTop: Int
    let open: (PostRoute) -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 0)
                    .id(Self.top)
                content
            }
            .background(Color(.systemBackground))
            .scrollEdgeEffectStyle(.soft, for: .top)
            .refreshable { await feed.refresh() }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: toTop) {
                withAnimation(.snappy) { proxy.scrollTo(Self.top, anchor: .top) }
            }
        }
    }

    private static let top = "top"

    @ViewBuilder
    private var content: some View {
        if feed.posts.isEmpty {
            empty
                .containerRelativeFrame(.vertical)
        } else {
            let posts = query.isEmpty ? feed.posts : feed.posts.filter { $0.matches(query) }
            if let problem = feed.problem {
                banner(problem)
            }
            if posts.isEmpty {
                ContentUnavailableView.search(text: query)
                    .padding(.top, 40)
            } else {
                switch layout {
                case .full: fullPosts(posts)
                case .compact: compactList(posts)
                case .grid: grid(posts)
                }
            }
            footer
        }
    }

    // MARK: Layouts

    private func fullPosts(_ posts: [SavedPost]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(posts) { post in
                PhonePostView(
                    post: post,
                    onOpen: { open(PostRoute(post: post)) },
                    onComments: { open(PostRoute(post: post, toComments: true)) }
                )
                    .matchedTransitionSource(id: post.id, in: namespace)
                    .contextMenu { PostActions(post: post) } preview: { PostPreview(post: post) }
                separator
            }
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    /// Three across, tall tiles, marks for carousels and videos, like Instagram's saved grid.
    private func grid(_ posts: [SavedPost]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 220), spacing: 2)], spacing: 2) {
            ForEach(posts) { post in
                GridCell(post: post)
                    .matchedTransitionSource(id: post.id, in: namespace)
                    .onTapGesture { open(PostRoute(post: post)) }
                    .contextMenu { PostActions(post: post) } preview: { PostPreview(post: post) }
            }
        }
    }

    private func compactList(_ posts: [SavedPost]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(posts) { post in
                CompactRow(post: post)
                    .matchedTransitionSource(id: post.id, in: namespace)
                    .onTapGesture { open(PostRoute(post: post)) }
                    .contextMenu { PostActions(post: post) } preview: { PostPreview(post: post) }
                Divider()
                    .padding(.leading, 16)
            }
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
    }

    /// Reddit's cards sit on gray bands; Instagram's posts just follow one another.
    @ViewBuilder
    private var separator: some View {
        if feed.service == .reddit {
            Rectangle()
                .fill(Color(.systemGray6))
                .frame(height: 8)
        } else {
            Spacer()
                .frame(height: 8)
        }
    }

    // MARK: Edges

    @ViewBuilder
    private var footer: some View {
        if feed.canLoadMore {
            if query.isEmpty {
                ProgressView()
                    .padding(24)
                    // Runs when the end scrolls into view, and again after each page while it stays visible.
                    .task(id: feed.posts.count) { await feed.loadMore() }
            } else {
                Button {
                    Task {
                        for _ in 0..<5 {
                            guard feed.canLoadMore else { break }
                            await feed.loadMore()
                        }
                    }
                } label: {
                    Label("Search Older Saved Posts", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(feed.isLoading)
                .padding(24)
            }
        }
    }

    @ViewBuilder
    private var empty: some View {
        switch feed.problem {
        case .notConnected?:
            ContentUnavailableView {
                Label("Sign In on Your Mac", systemImage: "laptopcomputer.and.iphone")
            } description: {
                Text("SavedFeeds on your Mac shares its \(feed.service.name) sign-in with this iPhone through iCloud Keychain. Open it there once while signed in.")
            } actions: {
                Button("Sign In Here Instead…") { app.signingIn = feed.service }
            }
        case let problem?:
            ContentUnavailableView {
                Label("Couldn't Load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(problem.localizedDescription)
            } actions: {
                Button("Try Again") { Task { await feed.refresh() } }
                if problem == .signedOut {
                    Button("Sign In Here…") { app.signingIn = feed.service }
                }
            }
        case nil:
            if feed.isLoading {
                ProgressView()
            } else {
                ContentUnavailableView("No Saved Posts", systemImage: "bookmark")
            }
        }
    }

    private func banner(_ problem: FeedError) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(problem.localizedDescription)
                .font(.footnote)
            Spacer()
            if problem == .signedOut {
                Button("Sign In") { app.signingIn = feed.service }
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(12)
        .background(.yellow.opacity(0.12), in: .rect(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// A grid tile: the post's first picture, marked when it's a carousel or a video. Reddit's add their title over the
/// picture, or, without one, are the title (or the saved comment) on the subreddit's color.
private struct GridCell: View {
    let post: SavedPost

    var body: some View {
        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let thumbnail = post.thumbnail {
                    CachedImage(url: thumbnail, size: 220)
                } else {
                    TextTile(post: post)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if post.service == .reddit, post.thumbnail != nil, let title = post.title {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.4), radius: 1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .bottom, endPoint: .top))
                }
            }
            .clipped()
            // Top left: the floating ⋯ button covers the top right of the first row.
            .overlay(alignment: .topLeading) {
                if let mark {
                    Image(systemName: mark)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .padding(7)
                }
            }
            .contentShape(.rect)
    }

    private var mark: String? {
        if post.media.count > 1 { return "square.fill.on.square.fill" }
        if let first = post.media.first, first.kind != .image { return "play.fill" }
        return nil
    }
}

/// A Reddit post without a picture, as a tile: its title (or the saved comment) on its subreddit's color.
private struct TextTile: View {
    let post: SavedPost

    var body: some View {
        Rectangle()
            .fill(Avatar.color(for: post.community ?? post.author).gradient)
            .overlay(alignment: .topLeading) {
                Image(systemName: post.isComment ? "quote.opening" : post.link != nil ? "link" : "text.alignleft")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(post.isComment ? (post.text ?? "") : (post.title ?? post.text ?? ""))
                        .font(.caption.weight(.semibold))
                        .lineLimit(post.isComment ? 5 : 6)
                    Text(post.community ?? "u/\(post.author)")
                        .font(.caption2)
                        .opacity(0.85)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(8)
            }
    }
}

/// A Reddit row: subreddit and age, title, counts; the picture on the right.
private struct CompactRow: View {
    let post: SavedPost

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(post.community ?? "u/\(post.author)")
                        .fontWeight(.semibold)
                    Text("· \(post.date.shortAge)")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .lineLimit(1)
                Text(post.isComment ? (post.text ?? "") : (post.title ?? ""))
                    .font(.subheadline.weight(post.isComment ? .regular : .semibold))
                    .lineLimit(3)
                if post.isComment, let title = post.title {
                    Text("on “\(title)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 12) {
                    if let score = post.score {
                        Label(score.compact, systemImage: "arrow.up")
                    }
                    if let comments = post.comments {
                        Label(comments.compact, systemImage: "bubble.right")
                    }
                    if let flair = post.flair {
                        Text(flair)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let thumbnail = post.thumbnail {
                CachedImage(url: thumbnail, size: 72)
                    .frame(width: 72, height: 72)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay {
                        if post.media.first?.kind == .video {
                            Image(systemName: "play.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                    }
            } else if post.link != nil {
                Image(systemName: "safari")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, height: 72)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }
}
