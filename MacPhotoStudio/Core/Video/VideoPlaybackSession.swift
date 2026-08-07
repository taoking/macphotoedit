import AVFoundation
import Combine
import Foundation

@MainActor
final class VideoPlaybackSession: ObservableObject {
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackRate: Double = 1
    @Published private(set) var isMuted = false
    @Published private(set) var volume: Double = 1

    let player: AVPlayer
    let duration: Double

    private let frameRate: Double
    private let securityScopedRootURL: URL
    private var hasSecurityScopedAccess: Bool
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init(sourceURL: URL, securityScopedRootURL: URL, duration: Double?, frameRate: Double?) {
        self.duration = max(0, duration ?? 0)
        self.frameRate = max(1, frameRate ?? 30)
        self.securityScopedRootURL = securityScopedRootURL
        self.hasSecurityScopedAccess = securityScopedRootURL.startAccessingSecurityScopedResource()
        self.player = AVPlayer(url: sourceURL)
        configureObservers()
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        if duration > 0, currentTime >= duration - 0.001 {
            seek(to: 0)
        }
        player.playImmediately(atRate: Float(playbackRate))
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) {
        let target = min(max(0, seconds), duration > 0 ? duration : .greatestFiniteMagnitude)
        currentTime = target
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func step(frames: Int) {
        seek(to: currentTime + Double(frames) / frameRate)
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        if isPlaying {
            player.rate = Float(rate)
        }
    }

    func setVolume(_ newVolume: Double) {
        volume = min(max(0, newVolume), 1)
        player.volume = Float(volume)
        if volume > 0 {
            player.isMuted = false
            isMuted = false
        }
    }

    func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
    }

    func close() {
        pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if hasSecurityScopedAccess {
            securityScopedRootURL.stopAccessingSecurityScopedResource()
            hasSecurityScopedAccess = false
        }
    }

    private func configureObservers() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = max(0, time.seconds.isFinite ? time.seconds : 0)
            Task { @MainActor [weak self] in
                self?.currentTime = seconds
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = false
            }
        }
    }
}
