import SwiftUI

struct CommentsSheet: View {
    @State private var model: CommentsModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(post: SavedPost) {
        _model = State(initialValue: CommentsModel(post: post))
    }

    private var post: SavedPost { model.post }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.title ?? post.author)
                        .font(.headline)
                        .lineLimit(1)
                    Text((model.total ?? post.comments).map { "\($0.formatted()) comments" } ?? "Comments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Open on \(post.service.name)") { openURL(post.permalink) }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 760)
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if model.comments.isEmpty {
            if let problem = model.problem {
                ContentUnavailableView {
                    Label("Couldn't Load Comments", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(problem.localizedDescription)
                } actions: {
                    Button("Try Again") { Task { await model.load() } }
                }
            } else if model.isLoading {
                ProgressView()
            } else {
                ContentUnavailableView("No Comments", systemImage: "bubble.left.and.bubble.right")
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(model.comments) { comment in
                        CommentRow(
                            comment: comment, service: post.service, permalink: post.permalink,
                            loadReplies: post.service == .instagram ? { await model.loadReplies(to: comment.id) } : nil
                        )
                        Divider()
                    }
                    if model.canLoadMore {
                        Button("Load More Comments") { Task { await model.loadMore() } }
                            .disabled(model.isLoading)
                    } else if model.more > 0 {
                        Link("\(model.more) more comments on \(post.service.name)", destination: post.permalink)
                            .font(.callout)
                    }
                    if let problem = model.problem {
                        Text(problem.localizedDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
        }
    }
}

private struct CommentRow: View {
    let comment: Comment
    let service: Service
    let permalink: URL
    /// Loads the rest of the replies in the app (Instagram); without it, they're a link.
    var loadReplies: (() async -> Void)? = nil
    @State private var collapsed = false
    @State private var loadingReplies = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy(duration: 0.2)) { collapsed.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Text(comment.author)
                        .fontWeight(.semibold)
                    if comment.isSubmitter {
                        Text("OP")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(.blue, in: .rect(cornerRadius: 3))
                    }
                    if let date = comment.date {
                        Text(date, format: .relative(presentation: .named))
                            .foregroundStyle(.secondary)
                    }
                    if collapsed, !comment.replies.isEmpty || comment.moreReplies > 0 {
                        Text("+\(replyCount)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let score = comment.score {
                        Label(score.formatted(.number.notation(.compactName)), systemImage: service == .reddit ? "arrow.up" : "heart")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if !collapsed {
                Text(PostCard.rich(comment.text))
                    .textSelection(.enabled)
                    .padding(.leading, 16)
                if !comment.replies.isEmpty || comment.moreReplies > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(comment.replies) { reply in
                            CommentRow(comment: reply, service: service, permalink: permalink)
                        }
                        if comment.moreReplies > 0 {
                            moreReplies
                        }
                    }
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(.quaternary)
                            .frame(width: 2)
                    }
                    .padding(.leading, 4)
                    .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var moreReplies: some View {
        let replies = comment.moreReplies == 1 ? "reply" : "replies"
        if let loadReplies {
            HStack(spacing: 6) {
                Button("View \(comment.moreReplies) \(replies)") {
                    loadingReplies = true
                    Task {
                        await loadReplies()
                        loadingReplies = false
                    }
                }
                .buttonStyle(.link)
                .disabled(loadingReplies)
                if loadingReplies {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .font(.caption)
        } else {
            Link("\(comment.moreReplies) more \(replies) on \(service.name)", destination: permalink)
                .font(.caption)
        }
    }

    private var replyCount: Int {
        comment.replies.count + comment.moreReplies
    }
}
