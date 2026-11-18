import SwiftUI
import WebKit

/// The hidden reddit.com and instagram.com tabs that feeds are fetched through. iOS only keeps a web page running
/// while its view is in a window, so they're kept in this one, out of sight.
struct HiddenSitePages: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        for page in [SitePage.reddit, .instagram] {
            view.addSubview(page.hostedView)
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
