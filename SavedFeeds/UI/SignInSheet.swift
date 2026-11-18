import SwiftUI
import WebKit

/// The service's own login page; closes once its session cookie appears.
struct SignInSheet: View {
    let service: Service
    let onSignedIn: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var browser: LoginBrowser?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to \(service.name)")
                    .font(.headline)
                Spacer()
                if browser?.isLoading == true {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            ZStack {
                if let browser {
                    WebViewHost(webView: browser.webView)
                    if let popup = browser.popup {
                        VStack(spacing: 0) {
                            HStack {
                                Text(popup.url?.host() ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Close", action: browser.closePopup)
                            }
                            .padding(8)
                            Divider()
                            WebViewHost(webView: popup)
                                .id(ObjectIdentifier(popup))
                        }
                        .background(.background)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 700)
        #endif
        .task {
            browser = LoginBrowser(url: service.loginURL)
            while !Task.isCancelled {
                if await service.isSignedIn() {
                    onSignedIn()
                    dismiss()
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// A web view that also opens the popups sign-in buttons use ("Continue with Google", "Log in with Facebook").
@Observable
final class LoginBrowser: NSObject, WKUIDelegate, WKNavigationDelegate {
    let webView: WKWebView
    private(set) var popup: WKWebView?
    private(set) var isLoading = false

    init(url: URL) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WebSession.store
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        prepare(webView)
        webView.load(URLRequest(url: url))
    }

    func closePopup() {
        popup = nil
    }

    private func prepare(_ webView: WKWebView) {
        webView.customUserAgent = WebSession.userAgent
        webView.uiDelegate = self
        webView.navigationDelegate = self
    }

    // window.open and target="_blank". WebKit loads the returned view, which must use `configuration`.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: .zero, configuration: configuration)
        prepare(popup)
        self.popup = popup
        return popup
    }

    // The popup calls window.close() once it has handed the sign-in back.
    func webViewDidClose(_ webView: WKWebView) {
        if webView === popup { popup = nil }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }
}

#if os(macOS)
private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
#else
private struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
#endif
