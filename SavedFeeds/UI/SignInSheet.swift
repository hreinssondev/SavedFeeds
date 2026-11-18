import SwiftUI
import WebKit

/// The service's own login page; closes once its session cookie appears.
struct SignInSheet: View {
    let service: Service
    let onSignedIn: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var page: WebPage = {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = WebSession.store
        let page = WebPage(configuration: configuration)
        page.customUserAgent = WebSession.userAgent
        return page
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to \(service.name)")
                    .font(.headline)
                Spacer()
                if page.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            WebView(page)
        }
        .frame(width: 480, height: 700)
        .task {
            page.load(URLRequest(url: service.loginURL))
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
