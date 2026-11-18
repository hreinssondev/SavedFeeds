import AVKit
import SwiftUI

/// A post's pictures and videos, one at a time, in a frame sized by the first.
struct MediaCarousel: View {
    let media: [Media]
    @State private var index = 0

    var body: some View {
        Rectangle()
            .fill(.black)
            // Like Instagram: no taller than 4:5, no wider than 1.91:1.
            .aspectRatio(min(max(media.first?.aspectRatio ?? 1, 0.8), 1.91), contentMode: .fit)
            .overlay {
                MediaView(media: media[index])
                    .id(index)
            }
            .overlay {
                if media.count > 1 {
                    HStack {
                        pageButton("chevron.left", hidden: index == 0) { index -= 1 }
                        Spacer()
                        pageButton("chevron.right", hidden: index == media.count - 1) { index += 1 }
                    }
                    .padding(8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if media.count > 1 {
                    Text("\(index + 1)/\(media.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: .capsule)
                        .padding(8)
                }
            }
            .clipShape(.rect(cornerRadius: 8))
    }

    private func pageButton(_ symbol: String, hidden: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.bold())
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.55), in: .circle)
        }
        .buttonStyle(.plain)
        .opacity(hidden ? 0 : 1)
        .disabled(hidden)
    }
}

struct MediaView: View {
    let media: Media

    var body: some View {
        switch media.kind {
        case .image: RemoteImage(url: media.image)
        case .video: VideoTile(media: media, loops: false)
        case .loop: VideoTile(media: media, loops: true)
        }
    }
}

struct RemoteImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure:
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            default:
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Poster with a play button; loops start on their own, muted.
struct VideoTile: View {
    let media: Media
    let loops: Bool
    @State private var player: AVPlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else {
                RemoteImage(url: media.image)
                Button(action: play) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 56))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { if loops { play() } }
        .onDisappear(perform: stop)
    }

    private func play() {
        guard let url = media.video else { return }
        let item = AVPlayerItem(url: url)
        if loops {
            let queue = AVQueuePlayer()
            looper = AVPlayerLooper(player: queue, templateItem: item)
            queue.isMuted = true
            player = queue
        } else {
            player = AVPlayer(playerItem: item)
        }
        player?.play()
    }

    private func stop() {
        player?.pause()
        player = nil
        looper = nil
    }
}
