import AVFoundation
import Foundation

final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private var observers: [NSObjectProtocol] = []

    private init() {}

    func activate() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
                    }
        observeInterruptions()
        observeRouteChanges()
    }

        private func observeInterruptions() {
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                if raw == AVAudioSession.InterruptionType.began.rawValue {
                    PlayerCenter.shared.pause()
                }
            }
        })
    }

        private func observeRouteChanges() {
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                if raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                    PlayerCenter.shared.pause()
                }
            }
        })
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
