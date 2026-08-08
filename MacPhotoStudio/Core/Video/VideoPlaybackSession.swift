import AVFoundation
import Combine
import Foundation

/// Values that must survive rebuilding an `AVPlayerItem` for the editor preview.
/// The edited composition can have a shorter duration after trim/speed, so the
/// playhead is clamped only when the equivalent output time no longer exists.
struct VideoPreviewPlaybackState: Sendable, Equatable {
    let currentTime: Double
    let isPlaying: Bool
    let playbackRate: Double
    let isMuted: Bool
    let volume: Double

    func restored(forDuration duration: Double) -> VideoPreviewPlaybackState {
        let safeDuration = max(0, duration.isFinite ? duration : 0)
        return VideoPreviewPlaybackState(
            currentTime: min(max(0, currentTime.isFinite ? currentTime : 0), safeDuration),
            isPlaying: isPlaying,
            playbackRate: max(0, playbackRate.isFinite ? playbackRate : 1),
            isMuted: isMuted,
            volume: min(max(0, volume.isFinite ? volume : 1), 1)
        )
    }
}

@MainActor
final class VideoPlaybackSession: ObservableObject {
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackRate: Double = 1
    @Published private(set) var isMuted = false
    @Published private(set) var volume: Double = 1
    @Published private(set) var playbackError: String?

    let player: AVPlayer
    let sourceURL: URL
    let playbackURL: URL
    let usesProxy: Bool
    @Published private(set) var duration: Double

    private let frameRate: Double
    private let securityScopedRootURL: URL
    private var hasSecurityScopedAccess: Bool
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var itemStatusObserver: NSKeyValueObservation?
    private var itemDurationObserver: NSKeyValueObservation?
    private var itemErrorObserver: NSKeyValueObservation?
    private var replacementGeneration = 0

    init(
        sourceURL: URL,
        playbackURL: URL? = nil,
        securityScopedRootURL: URL,
        duration: Double?,
        frameRate: Double?
    ) {
        self.sourceURL = sourceURL
        let resolvedPlaybackURL = (playbackURL ?? sourceURL).standardizedFileURL
        self.playbackURL = resolvedPlaybackURL
        self.usesProxy = resolvedPlaybackURL != sourceURL.standardizedFileURL
        self.duration = max(0, duration ?? 0)
        self.frameRate = max(1, frameRate ?? 30)
        self.securityScopedRootURL = securityScopedRootURL
        self.hasSecurityScopedAccess = securityScopedRootURL.startAccessingSecurityScopedResource()
        self.player = AVPlayer(url: resolvedPlaybackURL)
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

    func replaceCurrentItem(with item: AVPlayerItem, duration: Double) {
        let preservedState = previewPlaybackState.restored(forDuration: duration)
        replacementGeneration += 1
        let generation = replacementGeneration
        pause()
        player.replaceCurrentItem(with: item)
        observeCurrentItem(item)
        applyPreviewPlaybackState(preservedState, duration: duration)
        seekForReplacement(to: preservedState.currentTime) { [weak self] finished in
            guard let self, finished, self.replacementGeneration == generation else { return }
            self.restorePlayingState(from: preservedState)
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
        replacementGeneration += 1
        pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        removeCurrentItemObservers()
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
        observeCurrentItem(player.currentItem)
    }

    private var previewPlaybackState: VideoPreviewPlaybackState {
        VideoPreviewPlaybackState(
            currentTime: currentTime,
            isPlaying: isPlaying,
            playbackRate: playbackRate,
            isMuted: isMuted,
            volume: volume
        )
    }

    private func applyPreviewPlaybackState(_ state: VideoPreviewPlaybackState, duration: Double) {
        self.duration = max(0, duration.isFinite ? duration : 0)
        currentTime = state.currentTime
        playbackRate = state.playbackRate
        isMuted = state.isMuted
        volume = state.volume
        player.isMuted = state.isMuted
        player.volume = Float(state.volume)
    }

    private func seekForReplacement(to seconds: Double, completion: @escaping @MainActor (Bool) -> Void) {
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { finished in
            Task { @MainActor in
                completion(finished)
            }
        }
    }

    private func restorePlayingState(from state: VideoPreviewPlaybackState) {
        guard state.isPlaying else {
            player.pause()
            isPlaying = false
            return
        }
        player.playImmediately(atRate: Float(state.playbackRate))
        isPlaying = true
    }

    /// All item-scoped observation is replaced together. This keeps callbacks
    /// from a previous editor composition from changing the current preview.
    private func observeCurrentItem(_ item: AVPlayerItem?) {
        removeCurrentItemObservers()
        guard let item else {
            isPlaying = false
            playbackError = nil
            return
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                self.isPlaying = false
            }
        }
        itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            guard let item else { return }
            let status = item.status
            let duration = item.duration.seconds
            let errorDescription = item.error?.localizedDescription
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                self.handleItemStatus(status, duration: duration, errorDescription: errorDescription)
            }
        }
        itemDurationObserver = item.observe(\.duration, options: [.initial, .new]) { [weak self, weak item] _, _ in
            guard let item else { return }
            let duration = item.duration.seconds
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                self.updateDurationIfAvailable(duration)
            }
        }
        itemErrorObserver = item.observe(\.error, options: [.new]) { [weak self, weak item] _, _ in
            guard let item else { return }
            let errorDescription = item.error?.localizedDescription
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                guard let errorDescription else { return }
                self.playbackError = errorDescription
                self.isPlaying = false
            }
        }
    }

    private func removeCurrentItemObservers() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        itemDurationObserver?.invalidate()
        itemDurationObserver = nil
        itemErrorObserver?.invalidate()
        itemErrorObserver = nil
    }

    private func handleItemStatus(
        _ status: AVPlayerItem.Status,
        duration: Double,
        errorDescription: String?
    ) {
        updateDurationIfAvailable(duration)
        switch status {
        case .readyToPlay:
            playbackError = nil
        case .failed:
            playbackError = errorDescription ?? "视频预览项目无法播放。"
            isPlaying = false
        case .unknown:
            break
        @unknown default:
            playbackError = "视频预览项目处于未知状态。"
            isPlaying = false
        }
    }

    private func updateDurationIfAvailable(_ candidate: Double) {
        guard candidate.isFinite, candidate >= 0 else { return }
        duration = candidate
        currentTime = min(currentTime, candidate)
    }
}
