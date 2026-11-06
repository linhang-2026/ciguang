import MediaPlayer
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum HomeSection: String, CaseIterable {
    case songs = "歌曲"
    case albums = "专辑"
}

struct HomeCard: Identifiable {
    let id: String
    let title: String
    let secondary: String
    let trackCount: Int?
    let artworkData: Data?
    let records: [TrackRecord]
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query(sort: \TrackRecord.importedAt, order: .reverse) private var records: [TrackRecord]

        private var isLandscape: Bool { verticalSizeClass == .compact }

    @State private var showImporter = false
    @State private var showMediaPicker = false
    @State private var showNowPlaying = false
    @State private var importNotice: String?
        @State private var importDone = 0
    @State private var importTotal = 0
    @State private var importTask: Task<Void, Never>?
    @State private var searchText = ""
    @State private var section: HomeSection = .songs
        @AppStorage("homeCardStyle") private var cardStyle: HomeCardStyle = .image
        @State private var carouselResetToken = 0
        @State private var editTarget: TrackRecord?
        @State private var backdropTheme: ThemeColors = .fallback
        @State private var showOnboarding = !UserDefaults.standard.bool(forKey: OnboardingView.hasSeenKey)
        @State private var showSettings = false

    private var player: PlayerCenter { PlayerCenter.shared }

        private var visibleRecords: [TrackRecord] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return records }
        return records.filter {
            $0.title.localizedStandardContains(query)
                || $0.artist.localizedStandardContains(query)
                || $0.album.localizedStandardContains(query)
        }
    }

    private var cards: [HomeCard] {
        let list = visibleRecords
        switch section {
        case .songs:
            return list.map { record in
                HomeCard(
                    id: "song:\(record.id.uuidString)",
                    title: record.title,
                    secondary: secondaryLine(artist: record.artist, album: record.album),
                    trackCount: nil,
                    artworkData: record.artworkData,
                    records: [record]
                )
            }
        case .albums:
            let groups = Dictionary(grouping: list, by: { $0.album })
            return groups.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .map { album in
                    let albumTracks = groups[album] ?? []
                    return HomeCard(
                        id: "album:\(album)",
                        title: album,
                        secondary: albumTracks.first?.artist ?? "",
                        trackCount: albumTracks.count,
                        artworkData: albumTracks.first?.artworkData,
                        records: albumTracks
                    )
                }
        }
    }

    private func secondaryLine(artist: String, album: String) -> String {
        album.isEmpty ? artist : "\(artist) · \(album)"
    }

    private func loadBackdropTheme() {
        if let data = player.currentTrack?.artworkData,
           let dominant = ThemeExtractor.dominantColor(from: data) {
            backdropTheme = .from(dominant: dominant)
        } else {
            backdropTheme = .fallback
        }
    }

    var body: some View {
        GeometryReader { geo in
            let vw = geo.size.width
            ZStack(alignment: .top) {
                LatticeBackdrop(theme: backdropTheme)
                Group {
                    if records.isEmpty {
                        VStack(spacing: 0) {
                            header
                            emptyState
                        }
                    } else if cards.isEmpty {
                        VStack(spacing: 0) {
                            header
                            noMatchHint
                        }
                    } else {
                        homeSurface(width: vw)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if player.currentTrack != nil {
                    miniPlayerBar
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            .overlay(alignment: .bottom) {
                if importTask != nil, importTotal > 0 {
                    importProgressBar
                        .padding(.horizontal)
                        .padding(.bottom, player.currentTrack != nil ? 68 : 8)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.audio, .data],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    importFiles(urls)
                case .failure(let error):
                    importNotice = error.localizedDescription
                }
            }
            .sheet(isPresented: $showMediaPicker) {
                MediaPickerView { items in
                    showMediaPicker = false
                    guard !items.isEmpty else { return }
                    importMediaItems(items)
                }
            }
            .sheet(item: $editTarget) { record in
                TrackEditView(record: record) {
                                        player.refreshTrack(
                        id: record.id, title: record.title, artist: record.artist,
                        album: record.album, artworkData: record.artworkData
                    )
                    loadBackdropTheme()
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    UserDefaults.standard.set(true, forKey: OnboardingView.hasSeenKey)
                    showOnboarding = false
                }
            }
            .alert("导入", isPresented: Binding(
                get: { importNotice != nil },
                set: { if !$0 { importNotice = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importNotice ?? "")
            }
            .fullScreenCover(isPresented: $showNowPlaying) {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-smoke-lyrics") {
                    ImmersiveLyricsView()
                } else {
                    NowPlayingView()
                }
#else
                NowPlayingView()
#endif
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await LibraryStore.reconcileLibrary(in: modelContext)
#if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("-demoSeed") {
                await DemoSeeder.seedIfNeeded(in: modelContext)
            }
#endif
            loadBackdropTheme()
#if DEBUG
            await smokeTestIfRequested()
#endif
        }
        .task(id: player.currentTrack?.id) {
            loadBackdropTheme()
        }
        .onChange(of: section) { _, _ in
            carouselResetToken += 1
        }
        .onChange(of: searchText) { _, _ in
            carouselResetToken += 1
        }
    }

#if DEBUG
            private func smokeTestIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-smoke-lyrics") || args.contains("-smoke-player") else { return }
        if let i = args.firstIndex(of: "-lyricsMode"), i + 1 < args.count,
           let mode = LyricsMode(rawValue: args[i + 1]) {
            UserDefaults.standard.set(mode.rawValue, forKey: "lyricsMode")
        }
        for _ in 0..<20 where records.isEmpty {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard player.currentTrack == nil else { return }
                var first = records.first
        if let i = args.firstIndex(of: "-smokeTrack"), i + 1 < args.count {
            let key = args[i + 1]
            first = records.first { ($0.title as NSString).contains(key) } ?? first
        }
        guard let first else { return }
        let queue = records.map(\.playable)
        guard let idx = queue.firstIndex(where: { $0.id == first.id }) else { return }
        player.play(queue, at: idx)
        showNowPlaying = true
                if let i = args.firstIndex(of: "-smokeSeek"), i + 1 < args.count, let t = Double(args[i + 1]) {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            player.seek(to: t)
        }
                if let i = args.firstIndex(of: "-smokePause"), i + 1 < args.count, let t = Double(args[i + 1]) {
            try? await Task.sleep(nanoseconds: UInt64(t * 1_000_000_000))
            player.pause()
        }
                                if let i = args.firstIndex(of: "-smokeSwitch"), i + 2 < args.count,
           let t = Double(args[i + 1]), let mode = LyricsMode(rawValue: args[i + 2]) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(t * 1_000_000_000))
                UserDefaults.standard.set(mode.rawValue, forKey: "lyricsMode")
            }
        }
    }
#endif

    private func homeSurface(width vw: CGFloat) -> some View {
        VStack(spacing: 0) {
            header
            PosterWallView(
                cards: cards,
                currentTrackID: player.currentTrack?.id.uuidString,
                resetToken: carouselResetToken,
                onSelect: { play(card: $0) },
                onDelete: { card in
                    for record in card.records {
                        LibraryStore.delete(record, in: modelContext)
                    }
                },
                onEdit: { card in
                    if let record = card.records.first {
                        editTarget = record
                    }
                },
                onOpenPlayer: { showNowPlaying = true }
            )
        }
    }

        private var header: some View {
        Group {
            if isLandscape {
                                HStack(spacing: 16) {
                    titleGroup
                    sectionPills
                    cardStyleToggle
                    searchCapsule
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            } else {
                                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        titleGroup
                        Spacer()
                        cardStyleToggle
                        searchCapsule
                            .frame(maxWidth: 224)
                    }
                    sectionPills
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
    }

        private var titleGroup: some View {
        HStack(spacing: 12) {
            Text("词光")
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(.white.opacity(0.9))
            Menu {
                Button {
                    showImporter = true
                } label: {
                    Label("导入音频文件", systemImage: "folder")
                }
                Button {
                    showMediaPicker = true
                } label: {
                    Label("从 Apple 音乐曲库导入", systemImage: "music.note.list")
                }
                Divider()
                Button {
                    showSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.08), in: Circle())
            }
        }
    }

            private var cardStyleToggle: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardStyle = cardStyle == .image ? .card : .image
            }
        } label: {
            Image(systemName: cardStyle == .image ? "photo" : "photo.artframe")
                .font(.body.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.08), in: Circle())
        }
        .accessibilityLabel(cardStyle == .image ? "切换为拍立得卡片" : "切换为纯封面卡片")
    }

        private var searchCapsule: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.4))
            TextField("搜索曲库", text: $searchText)
                .font(.subheadline)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(.white.opacity(0.05), in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var sectionPills: some View {
        HStack(spacing: 2) {
            ForEach(HomeSection.allCases, id: \.self) { tab in
                let active = tab == section
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        section = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.footnote.weight(active ? .semibold : .regular))
                        .foregroundStyle(active ? .black : .white.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background {
                            if active {
                                Capsule().fill(.white)
                                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                            }
                        }
                }
            }
        }
        .padding(4)
        .background(.white.opacity(0.10), in: Capsule())
        .scaleEffect(isLandscape ? 1 : 0.9)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            ContentUnavailableView {
                Label("曲库还是空的", systemImage: "music.note.house")
            } description: {
                Text("点右上角 + 导入本地音频文件")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text("没有匹配的结果")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

        private var importProgressBar: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.white.opacity(0.8))
            VStack(alignment: .leading, spacing: 2) {
                Text("正在导入 \(importDone)/\(importTotal)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                ProgressView(value: importTotal > 0 ? Double(importDone) / Double(importTotal) : 0)
                    .tint(.white.opacity(0.7))
            }
            Button {
                importTask?.cancel()
            } label: {
                Text("取消")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var miniPlayerBar: some View {
        HStack(spacing: 12) {
            if let track = player.currentTrack {
                ArtworkThumbnail(data: track.artworkData, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    Text(track.artist)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    player.playPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Button {
                    showNowPlaying = true
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

        private func play(card: HomeCard) {
        let queue = visibleRecords.map(\.playable)
        guard let first = card.records.first,
              let index = queue.firstIndex(where: { $0.id == first.id }) else { return }
        player.play(queue, at: index)
    }

    private func importFiles(_ urls: [URL]) {
        importTotal = urls.count
        importDone = 0
        importTask = Task {
            let inserted = await LibraryStore.importFiles(urls, into: modelContext) { done, _ in
                Task { @MainActor in importDone = done }
            }
            if inserted.isEmpty, !urls.isEmpty {
                importNotice = "导入失败，请重试"
            }
            finishImport(inserted: inserted)
        }
    }

        private func importMediaItems(_ items: [MPMediaItem]) {
        importTotal = items.count
        importDone = 0
        importTask = Task {
            let (inserted, skipped) = await LibraryStore.importMediaItems(items, into: modelContext) { done, _ in
                Task { @MainActor in importDone = done }
            }
            if inserted.isEmpty {
                importNotice = skipped > 0
                    ? "这 \(skipped) 首歌是 Apple Music 在线歌曲（有版权保护），导不出来。先把它们下载到本地，或换自己导入过的歌"
                    : "导入失败，请重试"
            } else if skipped > 0 {
                importNotice = "已导入 \(inserted.count) 首，跳过 \(skipped) 首受版权保护的在线歌曲"
            }
            finishImport(inserted: inserted)
        }
    }

        private func finishImport(inserted: [TrackRecord]) {
        importTask = nil
        importTotal = 0
        if player.currentTrack == nil, !inserted.isEmpty {
            let queue = inserted.map(\.playable)
            player.play(queue, at: 0)
        }
    }
}

struct ArtworkThumbnail: View {
    let data: Data?
    var size: CGFloat
    var radius: CGFloat? = nil

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [.pink.opacity(0.7), .indigo.opacity(0.7)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius ?? size * 0.22))
    }
}
