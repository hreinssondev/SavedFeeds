import SwiftUI

/// A post as the iPhone shows it: Instagram's like the Instagram app (author, edge-to-edge media, counts, caption),
/// Reddit's like a Reddit card (subreddit, title, media or link, text, score and comments).
struct PhonePostView: View {
    let post: SavedPost
    /// The post screen: all of the text, videos play, pictures open full screen.
    var isDetail = false
    /// The feed: tapping the post opens it.
    var onOpen: (() -> Void)? = nil
    /// Tapping the comment count: the feed opens the post at its comments, the post screen scrolls to them.
    var onComments: (() -> Void)? = nil
    /// The post screen: tapping a picture opens it full screen.
    var onOpenPicture: ((Int) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PostHeader(post: post, showsMenu: !isDetail)
                .padding(.horizontal, 14)
            switch post.service {
            case .reddit: redditBody
            case .instagram: instagramBody
            }
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
        .modifier(OpensOnTap(open: onOpen))
    }

    // MARK: Reddit

    @ViewBuilder
    private var redditBody: some View {
        if let title = post.title {
            VStack(alignment: .leading, spacing: 6) {
                if post.isComment {
                    Label("Comment on “\(title)”", systemImage: "text.bubble")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(isDetail ? nil : 2)
                } else {
                    Text(title)
                        .font(.headline)
                }
                if let flair = post.flair {
                    FlairChip(text: flair)
                }
            }
            .padding(.horizontal, 14)
        }
        if !post.media.isEmpty {
            MediaPager(media: post.media, fill: false, playsVideo: isDetail, onTapPicture: onOpenPicture)
        }
        if let link = post.link {
            LinkCard(url: link)
                .padding(.horizontal, 14)
        }
        if let text = post.text, !text.isEmpty {
            Text(PostCard.rich(text))
                .font(.body)
                .lineLimit(isDetail ? nil : 6)
                .modifier(SelectableText(enabled: isDetail))
                .padding(.horizontal, 14)
        }
        HStack(spacing: 8) {
            if let score = post.score {
                Chip(systemImage: "arrow.up", text: score.compact)
            }
            if !post.isComment {
                CommentsButton(action: onComments) {
                    Chip(systemImage: "bubble.right", text: post.comments?.compact ?? "Comments")
                }
            }
            Spacer()
            ShareLink(item: post.permalink) {
                Chip(systemImage: "square.and.arrow.up", text: nil)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
    }

    // MARK: Instagram

    @ViewBuilder
    private var instagramBody: some View {
        if !post.media.isEmpty {
            MediaPager(media: post.media, fill: true, playsVideo: isDetail, onTapPicture: onOpenPicture)
        }
        HStack(spacing: 16) {
            if let likes = post.score {
                Label(likes.compact, systemImage: "heart")
            }
            if let comments = post.comments {
                CommentsButton(action: onComments) {
                    Label(comments.compact, systemImage: "bubble.right")
                }
            }
            Spacer()
            ShareLink(item: post.permalink) {
                Image(systemName: "paperplane")
            }
            .buttonStyle(.plain)
        }
        .font(.subheadline.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 14)
        VStack(alignment: .leading, spacing: 4) {
            if let caption = post.text, !caption.isEmpty {
                Text("\(Text(post.author).fontWeight(.semibold)) \(PostCard.rich(caption))")
                    .font(.subheadline)
                    .lineLimit(isDetail ? nil : 2)
                    .modifier(SelectableText(enabled: isDetail))
            }
            if !isDetail, let comments = post.comments, comments > 0 {
                CommentsButton(action: onComments) {
                    Text("View all \(comments.formatted()) comments")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(post.date, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
    }
}

/// Text you can select on the post screen; in the feed a long press is the post's preview instead.
private struct SelectableText: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.textSelection(.enabled)
        } else {
            content
        }
    }
}

/// Opens the post when tapped, if there's a way to; otherwise taps go to what's inside.
private struct OpensOnTap: ViewModifier {
    let open: (() -> Void)?

    func body(content: Content) -> some View {
        if let open {
            content.onTapGesture(perform: open)
        } else {
            content
        }
    }
}

/// A comment count that goes to the comments when there's somewhere to go.
private struct CommentsButton<Label: View>: View {
    let action: (() -> Void)?
    @ViewBuilder let label: () -> Label

    var body: some View {
        if let action {
            Button(action: action, label: label)
                .buttonStyle(.plain)
        } else {
            label()
        }
    }
}

/// Who and where: Instagram's author with their picture; Reddit's subreddit, author and age.
struct PostHeader: View {
    let post: SavedPost
    var showsMenu = true

    var body: some View {
        HStack(spacing: 10) {
            switch post.service {
            case .instagram:
                Avatar(url: post.avatar, name: post.author, size: 34)
                Text(post.author)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            case .reddit:
                Avatar(url: nil, name: post.community ?? post.author, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.community ?? "u/\(post.author)")
                        .font(.subheadline.weight(.semibold))
                    Text("u/\(post.author) · \(post.date.shortAge)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if showsMenu {
                PostMenu(post: post) {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .tint(.primary)
            }
        }
    }
}

/// Open in the service's app, share, copy the link.
struct PostMenu<Label: View>: View {
    let post: SavedPost
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            PostActions(post: post)
        } label: {
            label()
        }
    }
}

struct PostActions: View {
    let post: SavedPost
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(post.permalink)
        } label: {
            Label("Open in \(post.service.name)", systemImage: "arrow.up.forward.app")
        }
        if let link = post.link {
            Button {
                openURL(link)
            } label: {
                Label("Open Link", systemImage: "safari")
            }
        }
        ShareLink(item: post.permalink)
        Button {
            UIPasteboard.general.url = post.permalink
        } label: {
            Label("Copy Link", systemImage: "link")
        }
    }
}

/// A profile picture, or the name's first letter on a color of its own.
struct Avatar: View {
    let url: URL?
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                CachedImage(url: url, size: size)
            } else {
                Circle()
                    .fill(color.gradient)
                    .overlay {
                        Text(initial)
                            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }

    private var initial: String {
        let letters = name.hasPrefix("r/") || name.hasPrefix("u/") ? name.dropFirst(2) : Substring(name)
        return letters.first.map { String($0).uppercased() } ?? "?"
    }

    /// The same color for the same name, from a set that reads well under white.
    private var color: Color {
        let palette: [Color] = [.red, .orange, .pink, .purple, .indigo, .blue, .teal, .green, .brown, .mint]
        let hash = name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}

struct FlairChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemFill), in: .capsule)
    }
}

/// A count in a gray capsule, as in the Reddit app.
struct Chip: View {
    let systemImage: String
    let text: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            if let text {
                Text(text)
                    .monospacedDigit()
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Color(.tertiarySystemFill), in: .capsule)
    }
}

/// Where a link post points, opening in the in-app browser.
struct LinkCard: View {
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                Image(systemName: "safari")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(host)
                        .font(.subheadline.weight(.semibold))
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var host: String {
        let host = url.host() ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// What a long press lifts out of the feed.
struct PostPreview: View {
    let post: SavedPost

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let thumbnail = post.thumbnail {
                CachedImage(url: thumbnail, size: 400)
                    .aspectRatio(min(max(post.media.first?.aspectRatio ?? 1, 0.8), 1.91), contentMode: .fit)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(post.community ?? post.author)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let words = post.title ?? post.text, !words.isEmpty {
                    Text(PostCard.rich(words))
                        .font(.subheadline)
                        .lineLimit(4)
                }
            }
            .padding(12)
        }
        .frame(width: 320)
        .background(Color(.systemBackground))
    }
}

extension Int {
    /// 1.2K, 34M.
    var compact: String { formatted(.number.notation(.compactName)) }
}

extension Date {
    /// "now", "5m", "3h", "2d", "6w", "3y".
    var shortAge: String {
        let seconds = max(Date.now.timeIntervalSince(self), 0)
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<604_800: return "\(Int(seconds / 86_400))d"
        case ..<31_536_000: return "\(Int(seconds / 604_800))w"
        default: return "\(Int(seconds / 31_536_000))y"
        }
    }
}
