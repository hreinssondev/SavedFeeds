import SwiftUI

struct PostCard: View {
    let post: SavedPost
    @State private var expanded = false
    @State private var showingComments = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let title = post.title {
                Text(post.isComment ? "Comment on “\(title)”" : title)
                    .font(post.isComment ? .subheadline : .title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(post.isComment ? .secondary : .primary)
            }
            if !post.media.isEmpty {
                MediaCarousel(media: post.media)
            }
            if let link = post.link {
                LinkRow(url: link)
            }
            if let text = post.text, !text.isEmpty {
                Text(Self.rich(text))
                    .lineLimit(expanded ? nil : 6)
                    .textSelection(.enabled)
                if text.count > 320 {
                    Button(expanded ? "Show Less" : "Show More") { expanded.toggle() }
                        .buttonStyle(.link)
                }
            }
            footer
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .sheet(isPresented: $showingComments) {
            CommentsSheet(post: post)
        }
        .contextMenu {
            Button("Show Comments") { showingComments = true }
            Button("Open in Browser") { openURL(post.permalink) }
            if let link = post.link {
                Button("Open Link") { openURL(link) }
            }
            Button("Copy Link") { copy(post.permalink) }
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            if let community = post.community {
                Text(community).fontWeight(.semibold)
                Text("·").foregroundStyle(.tertiary)
                Text("u/\(post.author)").foregroundStyle(.secondary)
            } else {
                Text(post.author).fontWeight(.semibold)
            }
            Text("·").foregroundStyle(.tertiary)
            Text(post.date, format: .relative(presentation: .named))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .lineLimit(1)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if let score = post.score {
                Label(score.formatted(.number.notation(.compactName)), systemImage: post.service == .reddit ? "arrow.up" : "heart")
            }
            Button { showingComments = true } label: {
                Label(post.comments?.formatted(.number.notation(.compactName)) ?? "Comments", systemImage: "bubble.right")
            }
            .buttonStyle(.borderless)
            .help("Show comments")
            Spacer()
            ShareLink(item: post.permalink) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .help("Share")
            Button("Open") { openURL(post.permalink) }
                .buttonStyle(.borderless)
                .help("Open on \(post.service.name)")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func copy(_ url: URL) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #else
        UIPasteboard.general.url = url
        #endif
    }

    /// Bold, italics, links and code; keeps line breaks.
    static func rich(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

private struct LinkRow: View {
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                Text(host)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .font(.subheadline)
            .padding(10)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var host: String {
        let host = url.host() ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
