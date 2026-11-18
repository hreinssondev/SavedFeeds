import AVKit
import SwiftUI

/// Decoded pictures, kept in memory so scrolling back doesn't flash or decode again; the bytes come through URLCache.
final class ImageCache {
    static let shared = ImageCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 250 << 20
        return cache
    }()

    /// `size`: the longest side wanted, in points, for thumbnails; nil for the whole picture.
    func cached(_ url: URL, size: CGFloat? = nil) -> UIImage? {
        cache.object(forKey: key(url, size))
    }

    func image(_ url: URL, size: CGFloat? = nil, scale: CGFloat = 3) async -> UIImage? {
        if let image = cached(url, size: size) { return image }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = await Self.decode(data, maxPixels: size.map { $0 * scale })
        else { return nil }
        let pixels: CGFloat = image.size.width * image.scale * image.size.height * image.scale
        cache.setObject(image, forKey: key(url, size), cost: Int(pixels) * 4)
        return image
    }

    /// The picture as a JPEG file, for sharing or saving to Photos.
    func file(for url: URL) async -> URL? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return await Self.jpegFile(data, name: "SavedFeeds-\(abs(url.absoluteString.hashValue)).jpg")
    }

    private func key(_ url: URL, _ size: CGFloat?) -> NSString {
        (size.map { "\(Int($0))@" } ?? "") + url.absoluteString as NSString
    }

    @concurrent
    private nonisolated static func decode(_ data: Data, maxPixels: CGFloat?) async -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        if let maxPixels, max(pixels.width, pixels.height) > maxPixels {
            let factor = maxPixels / max(pixels.width, pixels.height)
            return image.preparingThumbnail(of: CGSize(width: pixels.width * factor, height: pixels.height * factor)) ?? image
        }
        return image.preparingForDisplay() ?? image
    }

    @concurrent
    private nonisolated static func jpegFile(_ data: Data, name: String) async -> URL? {
        guard let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.95) else { return nil }
        let file = URL.temporaryDirectory.appending(path: name)
        return (try? jpeg.write(to: file, options: .atomic)) == nil ? nil : file
    }
}

/// A remote picture from ImageCache, filling or fitting its frame; shown at once when it's cached.
struct CachedImage: View {
    let url: URL?
    var fill = true
    /// The longest side to decode for, in points; nil decodes the whole picture.
    var size: CGFloat? = nil
    var placeholder = Color(.secondarySystemBackground)
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    init(url: URL?, fill: Bool = true, size: CGFloat? = nil, placeholder: Color = Color(.secondarySystemBackground)) {
        self.url = url
        self.fill = fill
        self.size = size
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap { ImageCache.shared.cached($0, size: size) })
    }

    var body: some View {
        Rectangle()
            .fill(placeholder)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: fill ? .fill : .fit)
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: url) {
                guard let url else { return }
                if let cached = ImageCache.shared.cached(url, size: size) {
                    image = cached
                    return
                }
                let loaded = await ImageCache.shared.image(url, size: size, scale: displayScale)
                withAnimation(.easeOut(duration: 0.15)) { image = loaded }
            }
    }
}

/// A post's pictures and videos: swipe between them. Instagram's fill the frame, cut to the first one's shape,
/// as in the app; Reddit's show whole.
struct MediaPager: View {
    let media: [Media]
    let fill: Bool
    /// The post screen plays videos; the feed shows their posters.
    var playsVideo = false
    /// Tapping a picture (the post screen opens it full screen); without it taps go to the post.
    var onTapPicture: ((Int) -> Void)? = nil
    @State private var page = 0

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(min(max(media.first?.aspectRatio ?? 1, 0.8), 1.91), contentMode: .fit)
            .overlay {
                if media.count == 1 {
                    item(0)
                } else {
                    TabView(selection: $page) {
                        ForEach(media.indices, id: \.self) { index in
                            item(index).tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .clipped()
            .overlay(alignment: .topTrailing) {
                if media.count > 1 {
                    Text("\(page + 1)/\(media.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: .capsule)
                        .padding(10)
                }
            }
            .overlay(alignment: .bottom) {
                if media.count > 1 {
                    PageDots(count: media.count, page: page)
                        .padding(.bottom, 10)
                }
            }
    }

    @ViewBuilder
    private func item(_ index: Int) -> some View {
        let item = media[index]
        switch item.kind {
        case .image:
            if let onTapPicture {
                CachedImage(url: item.image, fill: fill)
                    .contentShape(.rect)
                    .onTapGesture { onTapPicture(index) }
            } else {
                CachedImage(url: item.image, fill: fill)
            }
        case .loop:
            LoopingVideo(media: item, fill: fill)
        case .video:
            if playsVideo {
                VideoPlayerView(media: item, isCurrent: page == index)
            } else {
                VideoPoster(media: item, fill: fill)
            }
        }
    }
}

struct PageDots: View {
    let count: Int
    let page: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<min(count, 10), id: \.self) { index in
                Circle()
                    .fill(.white.opacity(index == min(page, 9) ? 1 : 0.5))
                    .frame(width: 6, height: 6)
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 2)
    }
}

/// A video's poster with a play mark, as videos show in the feed.
struct VideoPoster: View {
    let media: Media
    let fill: Bool

    var body: some View {
        CachedImage(url: media.image, fill: fill)
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(.black.opacity(0.45), in: .circle)
            }
    }
}

/// A silent, looping clip (GIFs) that plays while it's on screen.
struct LoopingVideo: View {
    let media: Media
    let fill: Bool
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        CachedImage(url: media.image, fill: fill)
            .overlay {
                if let player {
                    PlayerLayer(player: player, fill: fill)
                }
            }
            .onAppear(perform: start)
            .onDisappear(perform: stop)
    }

    private func start() {
        guard player == nil, let url = media.video else { return }
        let queue = AVQueuePlayer()
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        player = queue
        queue.play()
    }

    private func stop() {
        player?.pause()
        player = nil
        looper = nil
    }
}

/// A video with sound and controls, playing while it's the page shown.
struct VideoPlayerView: View {
    let media: Media
    var isCurrent = true
    @State private var player: AVPlayer?

    var body: some View {
        CachedImage(url: media.image, fill: false, placeholder: .black)
            .overlay {
                if let player {
                    PlayerController(player: player)
                }
            }
            .onAppear { if isCurrent { play() } }
            .onChange(of: isCurrent) { _, current in
                if current { play() } else { player?.pause() }
            }
            .onDisappear(perform: stop)
    }

    private func play() {
        guard let url = media.video else { return }
        if player == nil { player = AVPlayer(url: url) }
        Playback.withSound()
        player?.play()
    }

    private func stop() {
        player?.pause()
        player = nil
        Playback.quiet()
    }
}

/// Sound: silent clips mix in under whatever else is playing; a video you play gets the sound, even with the
/// ring switch off, as in other video apps. The audio session is set off the main thread (it can block).
enum Playback {
    private static let queue = DispatchQueue(label: "com.hreinsson.SavedFeeds.audio")

    /// At launch: clips don't interrupt music.
    static func start() {
        queue.async {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        }
    }

    /// After a video: back to quiet, letting other audio resume.
    static func quiet() {
        queue.async {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    static func withSound() {
        queue.async {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }
}

/// An AVPlayerLayer: video without controls.
private struct PlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    let fill: Bool

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }

    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// UIKit's player, with its controls and full screen.
private struct PlayerController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}
