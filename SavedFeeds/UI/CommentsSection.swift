import SwiftUI

/// A post's comments, opened below it in the feed.
struct CommentsSection: View {
    let model: CommentsModel
    let onHide: () -> Void
    /// Top-level comments shown; long threads reveal more at a time.
    @State private var shown = 20

    private var post: SavedPost { model.post }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.comments.isEmpty {
                if let problem = model.problem {
                    HStack {
                        Text(problem.localizedDescription)
                            .foregroundStyle(.secondary)
                        Button("Try Again") { Task { await model.load() } }
                            .buttonStyle(.link)
                    }
                } else if model.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading comments…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No comments yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(model.comments.prefix(shown))) { comment in
                    CommentRow(
                        comment: comment, service: post.service, permalink: post.permalink,
                        loadReplies: post.service == .instagram ? { await model.loadReplies(to: comment.id) } : nil
                    )
                }
                more
                if let problem = model.problem {
                    Text(problem.localizedDescription)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Hide Comments", action: onHide)
                    .buttonStyle(.link)
                Spacer()
                Link("Open on \(post.service.name)", destination: post.permalink)
            }
        }
        .zoomedFont(.callout)
        .task { await model.load() }
    }

    @ViewBuilder
    private var more: some View {
        if shown < model.comments.count {
            Button("Show More Comments") { shown += 20 }
                .buttonStyle(.link)
        } else if model.canLoadMore {
            HStack(spacing: 8) {
                Button("Load More Comments") {
                    Task {
                        await model.loadMore()
                        shown = model.comments.count
                    }
                }
                .buttonStyle(.link)
                .disabled(model.isLoading)
                if model.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
        } else if model.more > 0 {
            Link("\(model.more) more comments on \(post.service.name)", destination: post.permalink)
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
                        .zoomedFont(.caption2)
                            .bold()
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Text(comment.author)
                        .fontWeight(.semibold)
                    if comment.isSubmitter {
                        Text("OP")
                            .zoomedFont(.caption2)
                            .bold()
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
                .zoomedFont(.subheadline)
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
            .zoomedFont(.caption)
        } else {
            Link("\(comment.moreReplies) more \(replies) on \(service.name)", destination: permalink)
                .zoomedFont(.caption)
        }
    }

    private var replyCount: Int {
        comment.replies.count + comment.moreReplies
    }
}
