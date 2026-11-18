import SwiftUI
import UIKit

/// A post's pictures full screen: swipe between them, pinch or double-tap to zoom, swipe down to close, tap to hide
/// the buttons. Sharing a picture offers Save Image.
struct MediaViewer: View {
    let media: [Media]
    /// Shared for videos, which have no file to share.
    let link: URL
    @State private var page: Int
    @State private var closing: CGFloat = 0
    @State private var chromeHidden = false
    @State private var file: URL?
    @Environment(\.dismiss) private var dismiss

    init(media: [Media], start: Int, link: URL) {
        self.media = media
        self.link = link
        _page = State(initialValue: start)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - closing * 0.8)
                .ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(media.indices, id: \.self) { index in
                    pageView(index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            chrome
                .opacity(chromeHidden || closing > 0 ? 0 : 1)
                .animation(.easeOut(duration: 0.2), value: chromeHidden)
        }
        .statusBarHidden(chromeHidden)
        .presentationBackground(.clear)
        .task(id: page) {
            file = nil
            if media[page].kind == .image, let image = media[page].image {
                file = await ImageCache.shared.file(for: image)
            }
        }
    }

    @ViewBuilder
    private func pageView(_ index: Int) -> some View {
        let item = media[index]
        switch item.kind {
        case .image:
            ZoomableImage(
                url: item.image,
                onTap: { chromeHidden.toggle() },
                onSwipe: { closing = $0 },
                onClose: close
            )
            .ignoresSafeArea()
        case .video, .loop:
            VideoPlayerView(media: item, isCurrent: page == index)
        }
    }

    private var chrome: some View {
        VStack {
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                Spacer()
                if media.count > 1 {
                    Text("\(page + 1) of \(media.count)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                Spacer()
                ShareLink(item: file ?? link) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            .padding(.horizontal)
            Spacer()
        }
    }

    private func close() {
        var transaction = Transaction()
        transaction.disablesAnimations = closing > 0
        withTransaction(transaction) { dismiss() }
    }
}

/// A picture in a zooming scroll view. Swiping down when it isn't zoomed reports how far (0–1) and, past a point,
/// closes; the picture flies off first.
private struct ZoomableImage: UIViewRepresentable {
    let url: URL?
    let onTap: () -> Void
    let onSwipe: (CGFloat) -> Void
    let onClose: () -> Void

    func makeUIView(context: Context) -> ZoomView { ZoomView() }

    func updateUIView(_ view: ZoomView, context: Context) {
        view.onTap = onTap
        view.onSwipe = onSwipe
        view.onClose = onClose
        view.load(url)
    }
}

private final class ZoomView: UIScrollView, UIScrollViewDelegate {
    var onTap: () -> Void = {}
    var onSwipe: (CGFloat) -> Void = { _ in }
    var onClose: () -> Void = {}

    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private var url: URL?
    private var fittedForSize = CGSize.zero
    private lazy var swipe = UIPanGestureRecognizer(target: self, action: #selector(swiped(_:)))

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        spinner.color = .white
        addSubview(spinner)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.require(toFail: doubleTap)
        addGestureRecognizer(tap)
        addGestureRecognizer(swipe)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func load(_ url: URL?) {
        guard url != self.url else { return }
        self.url = url
        show(url.flatMap { ImageCache.shared.cached($0) })
        guard imageView.image == nil, let url else { return }
        spinner.startAnimating()
        Task { [weak self] in
            let image = await ImageCache.shared.image(url)
            guard let self, self.url == url else { return }
            spinner.stopAnimating()
            show(image)
        }
    }

    private func show(_ image: UIImage?) {
        imageView.image = image
        fittedForSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        if bounds.size != fittedForSize { fit() }
    }

    /// Sizes the picture to fit, unzoomed, centered.
    private func fit() {
        fittedForSize = bounds.size
        zoomScale = 1
        guard let size = imageView.image?.size, size.width > 0, size.height > 0, bounds.width > 0 else {
            imageView.frame = bounds
            contentSize = bounds.size
            return
        }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        imageView.frame = CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
        contentSize = imageView.frame.size
        center()
    }

    private func center() {
        let x = max((bounds.width - contentSize.width) / 2, 0)
        let y = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { center() }

    @objc private func tapped() { onTap() }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            zoom(to: CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size), animated: true)
        }
    }

    /// The swipe down only starts when the picture isn't zoomed and the drag is mostly vertical; the scroll view's own
    /// gestures go on as usual.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === swipe else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        let velocity = swipe.velocity(in: self)
        return zoomScale <= minimumZoomScale + 0.01 && abs(velocity.y) > abs(velocity.x)
    }

    @objc private func swiped(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: superview)
        switch gesture.state {
        case .changed:
            imageView.transform = CGAffineTransform(translationX: translation.x * 0.4, y: translation.y)
            onSwipe(min(abs(translation.y) / 320, 1))
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: superview).y
            if abs(translation.y) > 130 || abs(velocity) > 900 {
                let direction: CGFloat = (translation.y == 0 ? velocity : translation.y) < 0 ? -1 : 1
                onSwipe(1)
                UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn) {
                    self.imageView.transform = CGAffineTransform(translationX: translation.x * 0.4, y: direction * self.bounds.height)
                } completion: { _ in
                    self.onClose()
                }
            } else {
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
                    self.imageView.transform = .identity
                }
                onSwipe(0)
            }
        default:
            break
        }
    }
}
