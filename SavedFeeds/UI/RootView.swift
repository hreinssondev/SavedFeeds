import Combine
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    /// Distance from the window's top edge to the center of the close/minimize/zoom buttons.
    @State private var controlsCenterY: CGFloat = 14

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 0) {
            FeedColumn(feed: app.reddit, headerHeight: headerHeight)
            Divider()
            FeedColumn(feed: app.instagram, headerHeight: headerHeight)
        }
        // The title bar is hidden; the columns' header bars take its place, level with the window controls.
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowControlsProbe { controlsCenterY = $0 })
        .background {
            // Esc closes every open comment section (disabled otherwise, so Esc keeps its other uses).
            Button("Close Comments") { withAnimation(.snappy(duration: 0.25)) { app.closeAllComments() } }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(app.openComments.isEmpty)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            await app.importSafariSessions()
            await app.refreshAll()
        }
        // The Safari extension says it handed over a session; becoming active covers a missed signal.
        .onReceive(DistributedNotificationCenter.default().publisher(for: SharedSessions.changed).receive(on: RunLoop.main)) { _ in
            Task { await app.syncSafariSessions() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await app.syncSafariSessions() }
        }
        .sheet(item: $app.signingIn) { service in
            SignInSheet(service: service) {
                Task { await app.feed(for: service).refresh() }
            }
        }
    }

    private var headerHeight: CGFloat { max(28, controlsCenterY * 2) }
}

/// Reports how far below the window's top edge the window controls are centered.
private struct WindowControlsProbe: NSViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> Probe { Probe(onChange: onChange) }
    func updateNSView(_ view: Probe, context: Context) { view.onChange = onChange }

    final class Probe: NSView {
        var onChange: (CGFloat) -> Void

        init(onChange: @escaping (CGFloat) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // The title bar buttons are laid out after the content view joins the window.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window,
                      let button = window.standardWindowButton(.closeButton) else { return }
                let frame = button.convert(button.bounds, to: nil)
                onChange((window.frame.height - frame.midY).rounded())
            }
        }
    }
}
