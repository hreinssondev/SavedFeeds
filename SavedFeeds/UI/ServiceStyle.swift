import SwiftUI

struct ServiceBadge: View {
    let service: Service

    var body: some View {
        Image(systemName: service.symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(service.tint, in: .circle)
    }
}

extension Service {
    var symbol: String {
        switch self {
        case .reddit: "bubble.left.and.bubble.right.fill"
        case .instagram: "camera.fill"
        }
    }

    var tint: AnyShapeStyle {
        switch self {
        case .reddit:
            AnyShapeStyle(Color(red: 1, green: 0.27, blue: 0))
        case .instagram:
            AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.98, green: 0.65, blue: 0.2), Color(red: 0.91, green: 0.2, blue: 0.45), Color(red: 0.55, green: 0.24, blue: 0.85)],
                startPoint: .bottomLeading, endPoint: .topTrailing
            ))
        }
    }
}

extension View {
    /// A button that reads as a link: AppKit's link style on the Mac, tinted text on iOS.
    @ViewBuilder
    func linkButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.link)
        #else
        buttonStyle(.borderless)
        #endif
    }
}
