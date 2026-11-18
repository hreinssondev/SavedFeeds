import SwiftUI

/// The feed's zoom (View › Zoom In ⌘+, Zoom Out ⌘-, Actual Size ⌘0).
enum FeedZoom {
    static let key = "feedZoom"
    static let steps: [Double] = [0.7, 0.8, 0.9, 1, 1.1, 1.25, 1.4, 1.6, 1.8, 2]
    /// The feed's width at 100 %.
    static let width = 640.0

    static func zoomedIn(from zoom: Double) -> Double {
        steps.first { $0 > zoom + 0.001 } ?? steps.last!
    }

    static func zoomedOut(from zoom: Double) -> Double {
        steps.last { $0 < zoom - 0.001 } ?? steps.first!
    }
}

extension EnvironmentValues {
    @Entry var feedZoom = 1.0
}

extension View {
    /// `style` at the feed's zoom. macOS ignores Dynamic Type, so the feed sizes its text itself.
    func zoomedFont(_ style: Font.TextStyle) -> some View {
        modifier(ZoomedFont(style: style))
    }
}

private struct ZoomedFont: ViewModifier {
    let style: Font.TextStyle
    @Environment(\.feedZoom) private var zoom

    func body(content: Content) -> some View {
        content.font(.system(size: style.macPointSize * zoom))
    }
}

private extension Font.TextStyle {
    /// The point size macOS uses for the style.
    var macPointSize: Double {
        switch self {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption, .caption2: 10
        @unknown default: 13
        }
    }
}
