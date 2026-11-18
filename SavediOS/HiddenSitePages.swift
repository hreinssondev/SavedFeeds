import SwiftUI
import WebKit

/// The hidden reddit.com and instagram.com tabs that feeds are fetched through. iOS only keeps a web page running
/// while its view is in a window, so they're kept in this one: a 1-point view behind everything, clipping them.
struct HiddenSitePages: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        for page in [SitePage.reddit, .instagram] {
            view.addSubview(page.hostedView)
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
