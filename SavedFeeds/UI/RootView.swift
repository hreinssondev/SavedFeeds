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
        // Esc closes an opened post, or else every open comment section.
        .background(EscapeKey(isActive: app.openedPost != nil || !app.openComments.isEmpty) {
            withAnimation(.snappy(duration: 0.25)) {
                if app.openedPost != nil { app.closeOpenedPost() } else { app.closeAllComments() }
            }
        })
        .overlay {
            if let post = app.openedPost {
                OpenedPostOverlay(post: post) {
                    withAnimation(.snappy(duration: 0.2)) { app.closeOpenedPost() }
                }
                .transition(.opacity)
            }
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

/// Calls `action` on Esc in this window while `isActive`, whatever has focus: a keyboard shortcut never sees Esc
/// once something in a post (selected text, the video player) has taken focus. Left alone when inactive, or for a
/// sheet or another window, so Esc keeps its usual jobs there.
struct EscapeKey: NSViewRepresentable {
    let isActive: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> Monitor { Monitor() }

    func updateNSView(_ view: Monitor, context: Context) {
        view.isActive = isActive
        view.action = action
    }

    final class Monitor: NSView {
        var isActive = false
        var action: () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let keyCode = event.keyCode
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let windowNumber = event.windowNumber
                let handled = MainActor.assumeIsolated {
                    self?.handle(keyCode: keyCode, modifiers: modifiers, windowNumber: windowNumber) ?? false
                }
                return handled ? nil : event
            }
        }

        private func handle(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, windowNumber: Int) -> Bool {
            guard isActive, keyCode == 53, modifiers.isEmpty, // 53: Esc
                  let window, window.windowNumber == windowNumber, window.attachedSheet == nil
            else { return false }
            action()
            return true
        }
    }
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
