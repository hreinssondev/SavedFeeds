import SwiftUI

struct ServiceBadge: View {
    let service: Service

    var body: some View {
        ServiceLogo(service: service, size: 18)
    }
}

/// The services' own marks, drawn so they're sharp at any size: Reddit's Snoo on its orange disc, Instagram's camera
/// on its sunset gradient. As a `glyph`, Instagram's camera alone, in the current foreground style.
struct ServiceLogo: View {
    let service: Service
    var size: CGFloat = 22
    var glyph = false

    var body: some View {
        Canvas { context, canvas in
            let side = min(canvas.width, canvas.height)
            switch (service, glyph) {
            case (.reddit, _): Self.reddit(&context, side)
            case (.instagram, false): Self.instagram(&context, side)
            case (.instagram, true): Self.camera(&context, side, inset: 0.06, shading: .foreground)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static let redditOrange = Color(red: 1, green: 0.271, blue: 0)

    private static func reddit(_ context: inout GraphicsContext, _ side: CGFloat) {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * side, y: y * side) }
        func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: (x - radius) * side, y: (y - radius) * side, width: 2 * radius * side, height: 2 * radius * side))
        }
        let white = GraphicsContext.Shading.color(.white)
        let orange = GraphicsContext.Shading.color(redditOrange)
        context.fill(circle(0.5, 0.5, 0.5), with: orange)
        // The antenna, bent toward its ball.
        var antenna = Path()
        antenna.move(to: point(0.52, 0.40))
        antenna.addLine(to: point(0.565, 0.21))
        antenna.addLine(to: point(0.70, 0.24))
        context.stroke(antenna, with: white, style: StrokeStyle(lineWidth: 0.04 * side, lineCap: .round, lineJoin: .round))
        context.fill(circle(0.745, 0.25, 0.068), with: white)
        // Ears, then the head over them.
        context.fill(circle(0.215, 0.46, 0.08), with: white)
        context.fill(circle(0.785, 0.46, 0.08), with: white)
        context.fill(Path(ellipseIn: CGRect(x: 0.185 * side, y: 0.39 * side, width: 0.63 * side, height: 0.40 * side)), with: white)
        // Eyes and smile.
        context.fill(circle(0.385, 0.56, 0.058), with: orange)
        context.fill(circle(0.615, 0.56, 0.058), with: orange)
        var smile = Path()
        smile.move(to: point(0.39, 0.67))
        smile.addQuadCurve(to: point(0.61, 0.67), control: point(0.5, 0.74))
        context.stroke(smile, with: orange, style: StrokeStyle(lineWidth: 0.032 * side, lineCap: .round))
    }

    private static func instagram(_ context: inout GraphicsContext, _ side: CGFloat) {
        let gradient = Gradient(stops: [
            .init(color: Color(red: 1.00, green: 0.86, blue: 0.50), location: 0.00),
            .init(color: Color(red: 0.99, green: 0.69, blue: 0.27), location: 0.10),
            .init(color: Color(red: 0.97, green: 0.47, blue: 0.22), location: 0.25),
            .init(color: Color(red: 0.96, green: 0.38, blue: 0.25), location: 0.35),
            .init(color: Color(red: 0.99, green: 0.11, blue: 0.11), location: 0.45),
            .init(color: Color(red: 0.88, green: 0.19, blue: 0.42), location: 0.60),
            .init(color: Color(red: 0.76, green: 0.21, blue: 0.52), location: 0.75),
            .init(color: Color(red: 0.51, green: 0.23, blue: 0.71), location: 0.90),
            .init(color: Color(red: 0.35, green: 0.32, blue: 0.86), location: 1.00),
        ])
        context.fill(
            Path(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerRadius: 0.27 * side, style: .continuous),
            with: .radialGradient(gradient, center: CGPoint(x: 0.28 * side, y: 1.08 * side), startRadius: 0, endRadius: 1.25 * side)
        )
        camera(&context, side, inset: 0.2, shading: .color(.white))
    }

    /// The camera outline: a rounded square, the lens and the flash dot, `inset` (as a share of the side) from the edges.
    private static func camera(_ context: inout GraphicsContext, _ side: CGFloat, inset: CGFloat, shading: GraphicsContext.Shading) {
        let box = (1 - 2 * inset) * side
        let origin = inset * side
        let line = box * 0.11
        let body = CGRect(x: origin, y: origin, width: box, height: box).insetBy(dx: line / 2, dy: line / 2)
        context.stroke(Path(roundedRect: body, cornerRadius: box * 0.3, style: .continuous), with: shading, lineWidth: line)
        let lens = box * 0.46
        context.stroke(
            Path(ellipseIn: CGRect(x: origin + (box - lens) / 2, y: origin + (box - lens) / 2, width: lens, height: lens)),
            with: shading, lineWidth: line
        )
        let dot = box * 0.13
        context.fill(Path(ellipseIn: CGRect(x: origin + box * 0.71, y: origin + box * 0.16, width: dot, height: dot)), with: shading)
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
