import MediaPlayer
import UIKit

final class NowPlayingCoordinator {
    static let shared = NowPlayingCoordinator()
    private var commandsAttached = false

    private init() {}

        func update(track: PlayableTrack?, duration: Double, elapsed: Double, playing: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track?.title ?? "",
            MPMediaItemPropertyArtist: track?.artist ?? "",
            MPMediaItemPropertyPlaybackDuration: max(duration, 0),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(elapsed, 0),
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1 : 0,
        ]
        if let data = track?.artworkData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        attachCommandsIfNeeded()
    }

        func updateElapsed(_ elapsed: Double, duration: Double, playing: Bool) {
        guard MPNowPlayingInfoCenter.default().nowPlayingInfo != nil else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(elapsed, 0)
        info[MPMediaItemPropertyPlaybackDuration] = max(duration, 0)
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1 : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func attachCommandsIfNeeded() {
        guard !commandsAttached else { return }
        commandsAttached = true

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in
            Task { @MainActor in PlayerCenter.shared.playPause() }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in PlayerCenter.shared.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in PlayerCenter.shared.playPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in PlayerCenter.shared.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in PlayerCenter.shared.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { event in
            Task { @MainActor in
                if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                    PlayerCenter.shared.seek(to: positionEvent.positionTime)
                }
            }
            return .success
        }
    }
}
