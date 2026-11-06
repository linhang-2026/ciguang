import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@main
struct LyricGlowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

        private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: TrackRecord.self)
        } catch {
                                    let support = URL.applicationSupportDirectory
            for name in ["default.store", "default.store-wal", "default.store-shm"] {
                try? FileManager.default.removeItem(at: support.appendingPathComponent(name))
            }
            container = try! ModelContainer(for: TrackRecord.self)
        }
    }

    var body: some Scene {
        WindowGroup {
                        if ProcessInfo.processInfo.environment["LYRICGLOW_SEEK_TEST"] == "1" {
                ImmersiveLyricsView()
                    .task { startSeekDiagnosticsIfRequested() }
            } else {
                LibraryView()
                    .onOpenURL { url in handleOpenURL(url) }
            }
        }
        .modelContainer(container)
    }

            private func startSeekDiagnosticsIfRequested() {
        Task { @MainActor in
            guard ProcessInfo.processInfo.environment["LYRICGLOW_SEEK_TEST"] == "1" else { return }
            let player = PlayerCenter.shared
            let context = ModelContext(container)
            let tracks = (try? context.fetch(FetchDescriptor<TrackRecord>())) ?? []
            guard let first = tracks.first else {
                print("[seektest] no track in library")
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            player.play([first.playable], at: 0)
            print("[seektest] playing:", first.title)
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            for target: Double in [150, 45, 210, 90] {
                player.seek(to: target)
                print("[seektest] seek →", target)
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
            player.pause()
        }
    }

            private func handleOpenURL(_ url: URL) {
        guard url.isFileURL,
              UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true
        else { return }
        let context = ModelContext(container)
        Task { @MainActor in
            await LibraryStore.importFiles([url], into: context)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
