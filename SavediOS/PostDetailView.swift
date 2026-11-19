import SwiftUI

/// A post on its own: all of it, then its comments.
struct PostDetailView: View {
    let route: PostRoute
    @Environment(AppModel.self) private var app
    @State private var picture: PictureIndex?

    private var post: SavedPost { route.post }

    var body: some View {
        let comments = app.comments(for: post)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    PhonePostView(
                        post: post, isDetail: true,
                        onComments: { withAnimation(.snappy) { proxy.scrollTo(Self.comments, anchor: .top) } },
                        onOpenPicture: { index in picture = PictureIndex(index: index) }
                    )
                    Divider()
                    CommentsHeader(model: comments)
                        .id(Self.comments)
                    PhoneComments(model: comments)
                }
            }
            .task {
                guard route.toComments else { return }
                // After the zoom into the post has settled.
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation(.snappy) { proxy.scrollTo(Self.comments, anchor: .top) }
            }
        }
        .background(Color(.systemBackground))
        .refreshable { await comments.reload() }
        .navigationTitle(post.service == .reddit ? (post.community ?? "Post") : post.author)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                OpenInAppButton(post: post) {
                    ServiceLogo(service: post.service, size: 24)
                        .frame(width: 32, height: 32)
                }
                PostMenu(post: post) {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .fullScreenCover(item: $picture) { start in
            MediaViewer(media: post.media, start: start.index, link: post.permalink)
        }
        .task {
            #if DEBUG
            if let index = UserDefaults.standard.string(forKey: "demoPicture").flatMap(Int.init) { picture = PictureIndex(index: index) }
            #endif
            await comments.load()
        }
    }
}

extension PostDetailView {
    fileprivate static let comments = "comments"
}

private struct PictureIndex: Identifiable {
    let index: Int
    var id: Int { index }
}

private struct CommentsHeader: View {
    let model: CommentsModel

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Comments")
                .font(.headline)
            if let count = model.total ?? model.post.comments {
                Text(count.formatted())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.post.service == .reddit {
                Menu {
                    Picker("Sort Comments", selection: Binding(
                        get: { model.sort },
                        set: { sort in Task { await model.sort(by: sort) } }
                    )) {
                        ForEach(CommentSort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                } label: {
                    Label(model.sort.title, systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
}

/// The comment rows, laid straight into the post screen's lazy stack so long threads stay quick.
private struct PhoneComments: View {
    let model: CommentsModel
    /// Top-level comments shown; long threads show more at a time.
    @State private var shown = 30

    private var post: SavedPost { model.post }

    var body: some View {
        if model.comments.isEmpty {
            Group {
                if let problem = model.problem {
                    VStack(spacing: 10) {
                        Text(problem.localizedDescription)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { Task { await model.reload() } }
                            .buttonStyle(.bordered)
                    }
                } else if model.isLoading {
                    ProgressView()
                } else {
                    Text("No comments yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            ForEach(Array(model.comments.prefix(shown))) { comment in
                CommentRow(
                    comment: comment, service: post.service, permalink: post.permalink,
                    loadReplies: post.service == .instagram ? { await model.loadReplies(to: comment.id) } : nil
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Divider()
                    .padding(.leading, 16)
            }
            more
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private var more: some View {
        if shown < model.comments.count {
            Button("Show More Comments") { shown += 30 }
                .buttonStyle(.bordered)
        } else if model.canLoadMore {
            Button {
                Task {
                    await model.loadMore()
                    shown = model.comments.count
                }
            } label: {
                if model.isLoading {
                    ProgressView()
                } else {
                    Text("Load More Comments")
                }
            }
            .buttonStyle(.bordered)
            .disabled(model.isLoading)
        } else if model.more > 0 {
            Link("\(model.more) more comments on \(post.service.name)", destination: post.permalink)
                .font(.subheadline)
        }
    }
}
