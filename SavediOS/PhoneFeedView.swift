import SwiftUI

struct PhoneFeedView: View {
    let feed: FeedModel
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            if feed.posts.isEmpty {
                empty
                    .containerRelativeFrame(.vertical)
            } else {
                LazyVStack(spacing: 12) {
                    if let problem = feed.problem {
                        banner(problem)
                    }
                    ForEach(feed.posts) { post in
                        PostCard(post: post)
                    }
                    if feed.canLoadMore {
                        ProgressView()
                            .padding()
                            // Runs when the end scrolls into view, and again after each page while it stays visible.
                            .task(id: feed.posts.count) { await feed.loadMore() }
                    }
                }
                .zoomedFont(.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .refreshable { await feed.refresh() }
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
                    .font(.footnote)
            }
        }
        .padding(10)
        .background(.yellow.opacity(0.1), in: .rect(cornerRadius: 10))
    }
}
