import AVKit
import AppKit
import SwiftUI

struct VideoPreviewSheet: View {
    let asset: LibraryAssetRecord
    @ObservedObject var applicationModel: ApplicationModel
    @Environment(\.dismiss) private var dismiss
    @State private var session: VideoPlaybackSession?
    @State private var filmstrip: [NSImage] = []
    @State private var loadingFailed = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(asset.filename, systemImage: "film")
                    .lineLimit(1)
                Spacer()
                if asset.videoIsHDR == true {
                    Label("HDR", systemImage: "sun.max.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Button("完成") { dismiss() }
            }
            .padding(.horizontal)

            if let session {
                VideoPlaybackView(session: session, filmstrip: filmstrip)
            } else if loadingFailed {
                ContentUnavailableView(
                    "视频不可播放",
                    systemImage: asset.availability == .offline ? "externaldrive.badge.xmark" : "film",
                    description: Text("原视频不可访问，或 macOS 无法创建播放会话。")
                )
                .frame(minWidth: 700, minHeight: 460)
            } else {
                ProgressView("正在准备视频…")
                    .frame(minWidth: 700, minHeight: 460)
            }
        }
        .padding(.vertical)
        .task(id: asset.id) {
            guard asset.mediaType == .video else { return }
            session = await applicationModel.makeVideoPlaybackSession(for: asset)
            loadingFailed = session == nil
        }
        .task(id: "filmstrip-\(asset.id.uuidString)") {
            guard asset.mediaType == .video,
                  let data = await applicationModel.videoFilmstripData(for: asset),
                  !Task.isCancelled else { return }
            filmstrip = data.compactMap(NSImage.init(data:))
        }
        .onDisappear {
            session?.close()
        }
    }
}

private struct VideoPlaybackView: View {
    @ObservedObject var session: VideoPlaybackSession
    let filmstrip: [NSImage]

    var body: some View {
        VStack(spacing: 12) {
            VideoPlayer(player: session.player)
                .frame(minWidth: 700, minHeight: 420)
                .background(.black, in: RoundedRectangle(cornerRadius: 8))

            if !filmstrip.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(filmstrip.enumerated()), id: \.offset) { _, image in
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .frame(maxWidth: 700)
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(timeText(session.currentTime))
                        .font(.caption.monospacedDigit())
                        .frame(width: 62, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { session.currentTime },
                            set: { session.seek(to: $0) }
                        ),
                        in: 0...max(session.duration, 0.01)
                    )
                    Text(timeText(session.duration))
                        .font(.caption.monospacedDigit())
                        .frame(width: 62, alignment: .trailing)
                }
                HStack(spacing: 12) {
                    Button {
                        session.step(frames: -1)
                    } label: {
                        Image(systemName: "backward.frame.fill")
                    }
                    .help("后退一帧")
                    Button {
                        session.togglePlayback()
                    } label: {
                        Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    .help(session.isPlaying ? "暂停" : "播放")
                    Button {
                        session.step(frames: 1)
                    } label: {
                        Image(systemName: "forward.frame.fill")
                    }
                    .help("前进一帧")
                    Menu {
                        ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { rate in
                            Button("\(rate.formatted(.number.precision(.fractionLength(1))))×") {
                                session.setPlaybackRate(rate)
                            }
                        }
                    } label: {
                        Text("\(session.playbackRate.formatted(.number.precision(.fractionLength(1))))×")
                            .frame(minWidth: 38)
                    }
                    Spacer()
                    Button {
                        session.toggleMute()
                    } label: {
                        Image(systemName: session.isMuted || session.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .help(session.isMuted ? "取消静音" : "静音")
                    Slider(
                        value: Binding(
                            get: { session.volume },
                            set: { session.setVolume($0) }
                        ),
                        in: 0...1
                    )
                    .frame(width: 90)
                    Button {
                        NSApp.keyWindow?.toggleFullScreen(nil)
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("全屏")
                }
            }
            .padding(.horizontal)
        }
    }

    private func timeText(_ seconds: Double) -> String {
        let rounded = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}
