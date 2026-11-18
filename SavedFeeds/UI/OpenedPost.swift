import SwiftUI

extension EnvironmentValues {
    /// Set on posts that open full size when clicked (two abreast); their video posters then open the post instead of playing.
    @Entry var opensOnClick = false
}

/// Clicking the post opens it full size, when `enabled`.
struct OpensOnClick: ViewModifier {
    let enabled: Bool
    let open: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .contentShape(.rect)
                .onTapGesture(perform: open)
                .environment(\.opensOnClick, true)
        } else {
            content
        }
    }
}

/// A post opened from the two-abreast feed, at 100 % over its own column. Esc or a click outside it closes it.
struct OpenedPostOverlay: View {
    let post: SavedPost
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .contentShape(.rect)
                .onTapGesture(perform: close)
            HStack(spacing: 0) {
                if post.service == .instagram { outside }
                opened
                if post.service == .reddit { outside }
            }
        }
        .ignoresSafeArea()
    }

    /// The other column: clicks go through to the dimming, which closes.
    private var outside: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
    }

    private var opened: some View {
        GeometryReader { geometry in
            ScrollView {
                PostCard(post: post)
                    .zoomedFont(.body)
                    .frame(maxWidth: FeedZoom.width)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    // The space around the post closes it too.
                    .background {
                        Color.clear
                            .contentShape(.rect)
                            .onTapGesture(perform: close)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .environment(\.feedZoom, 1)
    }
}
