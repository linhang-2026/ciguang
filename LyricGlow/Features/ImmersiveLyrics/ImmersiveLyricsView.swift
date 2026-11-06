import OSLog
import SwiftUI
struct ImmersiveLyricsView: View {
    private static let logCam = Logger(subsystem: "com.lhy.lyricglow", category: "camera")
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
                        @State private var lyricsMode: LyricsMode
    @State private var latentPreset: LatentBackgroundPreset

    init() {
        _lyricsMode = State(initialValue:
            LyricsMode(rawValue: UserDefaults.standard.string(forKey: "lyricsMode") ?? "") ?? .fume)
        _latentPreset = State(initialValue:
            LatentBackgroundPreset(rawValue: UserDefaults.standard.string(forKey: "latentBackgroundPreset") ?? "") ?? .cover)
    }
    @State private var article: FumeArticle?
    @State private var layoutSize: CGSize = .zero
    @State private var scheduler: LyricScheduler?
    @State private var theme: ThemeColors = .fallback
    @State private var camera = FumeCamera()
    @State private var lastFrameTime: Double?
        @State private var lastLyricTime: Double?
    @State private var noLyrics = false
        @State private var showLyricImporter = false
    @State private var lyricNotice: String?
    @State private var scrubRatio: Double?
        @State private var coverColors: [CoverPalette.RGB] = []
        @State private var chromeHidden = false

    private var player: PlayerCenter { PlayerCenter.shared }
    private var track: PlayableTrack? { player.currentTrack }

    var body: some View {
        ZStack {
                        LatentBackgroundView(theme: theme, coverColors: coverColors, preset: latentPreset)
                .ignoresSafeArea()
            GeometryReader { geo in
                ZStack {
                    switch lyricsMode {
                    case .fume:
                        if let article {
                            worldContent(article: article, size: geo.size)
                        } else if noLyrics || track == nil {
                            emptyHint
                        }
                    case .classic:
                        if let scheduler {
                            ClassicLyricsView(scheduler: scheduler, theme: theme)
                        } else if noLyrics || track == nil {
                            emptyHint
                        }
                    case .still:
                        if let scheduler {
                            StillLyricsView(scheduler: scheduler, theme: theme)
                        } else if noLyrics || track == nil {
                            emptyHint
                        }
                    case .tilt:
                        if let scheduler {
                            TiltLyricsView(scheduler: scheduler, theme: theme)
                        } else if noLyrics || track == nil {
                            emptyHint
                        }
                    case .partita:
                        if let scheduler {
                            PartitaLyricsView(scheduler: scheduler, theme: theme)
                        } else if noLyrics || track == nil {
                            emptyHint
                        }
                    case .claddagh:
                        if let scheduler {
                            CladdaghLyricsView(scheduler: scheduler, theme: theme)
                        } else if noLyrics || track == nil {
                            emptyHint
                        }
                    case .cadenza:
                        if let scheduler {
                            CadenzaLyricsView(scheduler: scheduler, theme: theme, viewport: geo.size)
                        } else if noLyrics || track == nil {
                            emptyHint
                        }
                    case .monet:
                                                centeredHint(icon: "paintbrush", text: "Monet 风格移植中", detail: "正在从 folia-major 逐行对齐，完成后此风格即可用")
                    case .cappella:
                        if let scheduler {
                            CappellaLyricsView(scheduler: scheduler, theme: theme, title: track?.title, artist: track?.artist)
                        } else if noLyrics || track == nil {
                            emptyHint
                        }
                    case .diorama:
                        if let scheduler {
                            DioramaLyricsView(
                                scheduler: scheduler,
                                theme: theme,
                                sceneKey: "\(track?.id.uuidString ?? "")|\(track?.title ?? "")"
                            )
                        } else if noLyrics || track == nil {
                            emptyHint
                        }
                    }
                }
                .onAppear { relayoutIfNeeded(size: geo.size) }
                .onChange(of: geo.size) { _, newSize in relayoutIfNeeded(size: newSize) }
            }
            .ignoresSafeArea()
            chrome
                .opacity(chromeHidden ? 0 : 1)
                .allowsHitTesting(!chromeHidden)
        }
                .onTapGesture {
            if chromeHidden {
                withAnimation(.easeInOut(duration: 0.35)) {
                    chromeHidden = false
                }
            }
        }
        .preferredColorScheme(.dark)
                                .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            DispatchQueue.main.async {
                if let m = LyricsMode(rawValue: UserDefaults.standard.string(forKey: "lyricsMode") ?? ""), m != lyricsMode {
                    lyricsMode = m
                }
                if let p = LatentBackgroundPreset(rawValue: UserDefaults.standard.string(forKey: "latentBackgroundPreset") ?? ""), p != latentPreset {
                    latentPreset = p
                }
            }
        }
        .task(id: track?.id) {
            await loadTheme()
            await rebuildLayout()
        }
    }

        private func relayoutIfNeeded(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        guard abs(size.width - layoutSize.width) > 4 || abs(size.height - layoutSize.height) > 4 else { return }
        layoutSize = size
        Task { await rebuildLayout(viewport: size, resetCamera: false) }
    }

    private func worldContent(article: FumeArticle, size: CGSize) -> some View {
        let worldSize = CGSize(
            width: max(article.width, size.width * 1.2),
            height: max(article.height, size.height * 1.2)
        )
        return ZStack(alignment: .topLeading) {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                FumeBackgroundShapes(
                    worldSize: worldSize,
                    paperBounds: article.paperBounds,
                    seed: track?.title ?? "seed",
                    theme: theme,
                    time: context.date.timeIntervalSinceReferenceDate,
                    view: camera.backgroundView(worldSize: worldSize, viewport: size),
                    viewport: size
                )
            }

                        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                let now = context.date.timeIntervalSinceReferenceDate
                let camOffset = CGSize(
                    width: size.width / 2 - camera.x * camera.scale,
                    height: size.height / 2 - camera.y * camera.scale
                )
                blocksLayer(article: article)
                    .frame(width: article.width, height: article.height, alignment: .topLeading)
                    .scaleEffect(camera.scale, anchor: .topLeading)
                    .offset(camOffset)
                    .onChange(of: context.date) { _, _ in
                        stepCamera(article: article, now: now, viewport: size)
                    }
            }
        }
    }

        private func stepCamera(article: FumeArticle, now: Double, viewport: CGSize) {
        let dt = min(max(now - (lastFrameTime ?? now), 0.001), 0.1)
        lastFrameTime = now
        let time = player.lyricClock
                        if let lastLyricTime, abs(time - lastLyricTime) > 1.5 {
            Self.logCam.info("SNAP time=\(time, format: .fixed(precision: 2)) jump=\(time - lastLyricTime, format: .fixed(precision: 2))")
            camera.snap(article: article, time: time, viewport: viewport)
            self.lastLyricTime = time
            return
        }
        lastLyricTime = time
        camera.step(
            article: article,
            time: time,
            now: now,
            dt: dt,
            lineIndex: scheduler?.activeLineIndex(at: time),
            viewport: viewport
        )
    }

    private func blocksLayer(article: FumeArticle) -> some View {
                let time = player.lyricClock
        let activeIndex = scheduler?.activeLineIndex(at: time)
        return ZStack(alignment: .topLeading) {
            ForEach(article.chronologicalBlocks) { block in
                blockView(block, activeIndex: activeIndex, time: time)
                    .font(FumeArticleLayout.swiftUIFont(block.fontPx, hero: block.isHero))
                    .position(x: block.x + block.width / 2, y: block.y + block.height / 2)
                    .onTapGesture {
                        player.seek(to: block.line.start + 0.01)
                    }
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: FumeBlock, activeIndex: Int?, time: Double) -> some View {
        let nextLineStart: Double? = {
            guard let scheduler else { return nil }
            let idx = block.id + 1
            return idx < scheduler.lyrics.lines.count ? scheduler.lyrics.lines[idx].start : nil
        }()
        let trailEnd = (block.line.words.last?.end ?? block.line.end) + 1.5

        if block.id == activeIndex {
                        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
                FumeBlockView(
                    block: block,
                    mode: .live(PlayerCenter.shared.lyricClock),
                    nextLineStart: nextLineStart,
                    theme: theme
                )
            }
        } else if time >= block.line.start && time <= trailEnd {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                FumeBlockView(
                    block: block,
                    mode: .live(PlayerCenter.shared.lyricClock),
                    nextLineStart: nextLineStart,
                    theme: theme
                )
            }
        } else if time >= block.line.start {
            FumeBlockView(block: block, mode: .passedStatic, nextLineStart: nextLineStart, theme: theme)
        } else {
            FumeBlockView(block: block, mode: .waiting, nextLineStart: nextLineStart, theme: theme)
        }
    }

    private func loadTheme() async {
        guard let track else { return }
        if let dominant = ThemeExtractor.dominantColor(from: track.artworkData) {
            theme = ThemeColors.from(dominant: dominant)
        } else {
            theme = .fallback
        }
        coverColors = CoverPalette.representativeColors(from: track.artworkData, count: 6)
    }

    private func rebuildLayout(viewport: CGSize? = nil, resetCamera: Bool = true) async {
        guard let track else {
            article = nil
            noLyrics = false
            return
        }
                let loaded = LyricMatcher.findLocalLyrics(for: track.audioURL)
        scheduler = loaded.map { LyricScheduler($0) }
        noLyrics = (loaded == nil)
        guard let loaded, !loaded.lines.isEmpty else {
            article = nil
            return
        }
        let size = viewport ?? layoutSize
        guard size.width > 0, size.height > 0 else { return }
        layoutSize = size

        let computed = await Task.detached(priority: .userInitiated) {
            FumeArticleLayout.layout(lines: loaded.lines, viewport: size)
        }.value
        article = computed
        if let computed {
            if resetCamera { camera = FumeCamera() }
            camera.sync(to: computed)
        }
    }

        private var isLandscape: Bool { verticalSizeClass == .compact }

        private var modeMenu: some View {
        Menu {
            ForEach(LyricsMode.visibleModes) { mode in
                Button {
                    lyricsMode = mode
                    UserDefaults.standard.set(mode.rawValue, forKey: "lyricsMode")
                } label: {
                    if lyricsMode == mode {
                        Label(mode.label, systemImage: "checkmark")
                    } else {
                        Text(mode.label)
                    }
                }
            }
            Divider()
            Section("背景") {
                ForEach(LatentBackgroundPreset.allCases) { preset in
                    Button {
                        latentPreset = preset
                        UserDefaults.standard.set(preset.rawValue, forKey: "latentBackgroundPreset")
                    } label: {
                        if latentPreset == preset {
                            Label(preset.label, systemImage: "checkmark")
                        } else {
                            Text(preset.label)
                        }
                    }
                }
            }
            Divider()
            Section("歌词校准 \(formatOffset(player.lyricOffset))") {
                Button {
                    player.lyricOffset += 0.1
                } label: {
                    Label("歌词提前 0.1s", systemImage: "gobackward.15")
                }
                Button {
                    player.lyricOffset -= 0.1
                } label: {
                    Label("歌词延后 0.1s", systemImage: "goforward.15")
                }
                Button {
                    player.lyricOffset += 1
                } label: {
                    Label("歌词提前 1s", systemImage: "gobackward")
                }
                Button {
                    player.lyricOffset -= 1
                } label: {
                    Label("歌词延后 1s", systemImage: "goforward")
                }
                if player.lyricOffset != 0 {
                    Button(role: .destructive) {
                        player.lyricOffset = 0
                    } label: {
                        Label("偏移归零（仅对当前歌曲生效）", systemImage: "arrow.uturn.backward")
                    }
                }
            }
            Divider()
            Button {
                withAnimation(.easeInOut(duration: 0.35)) {
                    chromeHidden.toggle()
                }
            } label: {
                Label(
                    chromeHidden ? "退出全屏沉浸" : "全屏沉浸",
                    systemImage: chromeHidden ? "rectangle" : "rectangle.expand.vertical"
                )
            }
        } label: {
            HStack(spacing: 4) {
                Text(lyricsMode.label)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.08), in: Capsule())
                                    .contentShape(Capsule())
            .padding(.horizontal, 6)
            .padding(.vertical, 9)
        }
    }

        private func formatOffset(_ value: Double) -> String {
        value == 0 ? "0s" : String(format: "%+.1fs", value)
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track?.title ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                    if !isLandscape {
                        Text(track?.artist ?? "")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.28))
                            .lineLimit(1)
                    }
                }
                if isLandscape {
                    Text(track?.artist ?? "")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.28))
                        .lineLimit(1)
                    Spacer()
                } else {
                    Spacer()
                }
                modeMenu
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(8)
                        .contentShape(Rectangle())
                                                .padding(6)
                }
            }
            .padding(.horizontal, isLandscape ? 24 : 20)
            .padding(.top, isLandscape ? 10 : 8)

            Spacer()

            Group {
                if isLandscape {
                                        HStack(spacing: 20) {
                        HStack(spacing: 20) {
                            Button {
                                player.previous()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            Button {
                                player.playPause()
                            } label: {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            Button {
                                player.next()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                        progressTimeline
                    }
                    .padding(.horizontal, 36)
                    .padding(.bottom, 10)
                } else {
                    VStack(spacing: 14) {
                        progressTimeline
                        HStack(spacing: 44) {
                            Button {
                                player.previous()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            Button {
                                player.playPause()
                            } label: {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 30, weight: .light))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            Button {
                                player.next()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private var progressTimeline: some View {
        GeometryReader { geo in
                                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                let ratio = scrubRatio
                    ?? (player.duration > 0 ? min(player.liveTime / player.duration, 1) : 0)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(height: 2)
                    Capsule()
                        .fill(.white.opacity(0.75))
                        .frame(width: max(geo.size.width * ratio, 0), height: 2)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                                                                                    scrubRatio = min(max(value.location.x / geo.size.width, 0), 1)
                        }
                        .onEnded { _ in
                            if let scrubRatio, player.duration > 0 {
                                player.seek(to: scrubRatio * player.duration)
                            }
                            scrubRatio = nil
                        }
                )
            }
        }
        .frame(height: 22)
    }

    private var emptyHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.quote")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
            Text(track == nil ? "未在播放" : "这首歌还没有歌词")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
            if track != nil {
                Text("把歌词文件和歌用同一个名字一起导入会自动匹配，也可以现在手动加上")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                HStack(spacing: 12) {
                    Button {
                        showLyricImporter = true
                    } label: {
                        Label("导入歌词文件", systemImage: "folder")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.18))
                    .foregroundStyle(.white.opacity(0.9))
                    Button {
                        pasteLyricsFromClipboard()
                    } label: {
                        Label("粘贴歌词", systemImage: "doc.on.clipboard")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.18))
                    .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(
            isPresented: $showLyricImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importLyrics(from: url) }
            case .failure:
                break
            }
        }
        .alert("歌词", isPresented: Binding(
            get: { lyricNotice != nil },
            set: { if !$0 { lyricNotice = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(lyricNotice ?? "")
        }
    }

        private func importLyrics(from url: URL) {
        guard let track else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              LyricMatcher.parse(content) != nil else {
            lyricNotice = "这个文件不像带时间轴的歌词（支持 LRC、QRC、TTML 等格式）"
            return
        }
        LyricMatcher.saveLyrics(content, for: track.audioURL, overwrite: true)
        Task { await rebuildLayout() }
    }

        private func pasteLyricsFromClipboard() {
        guard let track else { return }
        guard let content = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            lyricNotice = "剪贴板里没有歌词文本，先复制一份再回来粘贴"
            return
        }
        guard LyricMatcher.parse(content) != nil else {
            lyricNotice = "剪贴板里的内容不像带时间轴的歌词（支持 LRC、QRC、TTML 等格式）"
            return
        }
        LyricMatcher.saveLyrics(content, for: track.audioURL, overwrite: true)
        Task { await rebuildLayout() }
    }

    private func centeredHint(icon: String, text: String, detail: String? = nil) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
            Text(text)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FumeBackgroundShapes: View {
    let worldSize: CGSize
    let paperBounds: CGRect
    let seed: String
    let theme: ThemeColors
    let time: Double
    let view: FumeCamera.BackgroundView
    let viewport: CGSize

        @State private var shapes: [Shape] = []

    private struct Shape {
        let kind: Kind
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let rotation: Double
        let rotationSpeed: Double
        let strokeWidth: CGFloat
        let opacity: Double
        let useAccent: Bool
        let depth: Double
        let ringGapStart: Double
        let ringGapSize: Double

        enum Kind { case ring, square, cross, spark }
    }

    private var sceneKey: String {
        "\(seed)|\(Int(worldSize.width))x\(Int(worldSize.height))"
    }

    var body: some View {
        Canvas { context, _ in
            for shape in shapes {
                drawShape(shape, in: &context)
            }
        }
        .allowsHitTesting(false)
        .task(id: sceneKey) {
            shapes = buildScene()
        }
    }

    private func buildScene() -> [Shape] {
        let worldWidth = max(worldSize.width, viewport.width * 1.2)
        let worldHeight = max(worldSize.height, viewport.height * 1.2)
        let baseUnit = min(max(min(viewport.width, viewport.height) * 0.72, 320), 760)
        let bounds = paperBounds

        let kinds: [Shape.Kind] = [.ring, .square, .cross, .ring, .square, .cross]
        let shapeCount = worldWidth > worldHeight ? 8 : 7
        let sparkCount = worldWidth > worldHeight ? 12 : 9

        var result: [Shape] = []

        for index in 0..<shapeCount {
            let localSeed = "\(seed):\(Int(worldWidth)):\(Int(worldHeight)):\(index)"
            let kind = kinds[index % kinds.count]
            let size = baseUnit * mix(0.82, 1.36, seedF("\(localSeed):size"))
            let anchor = paperHaloAnchor(bounds: bounds, worldWidth: worldWidth, worldHeight: worldHeight, size: size, seedKey: localSeed)
            result.append(Shape(
                kind: kind,
                x: anchor.x,
                y: anchor.y,
                size: size,
                rotation: mix(-.pi * 0.2, .pi * 0.2, seedF("\(localSeed):rotation")),
                rotationSpeed: mix(-0.045, 0.045, seedF("\(localSeed):rotation-speed")),
                strokeWidth: mix(0.25, 2.1, seedF("\(localSeed):stroke-width")),
                opacity: mix(0.01, 0.16, seedF("\(localSeed):opacity")),
                useAccent: seedF("\(localSeed):color") > 0.5,
                depth: seedF("\(localSeed):depth"),
                ringGapStart: kind == .ring ? mix(-.pi, .pi, seedF("\(localSeed):gap-start")) : 0,
                ringGapSize: kind == .ring ? mix(.pi * 0.12, .pi * 0.24, seedF("\(localSeed):gap-size")) : 0
            ))
        }

                let areaLeft = worldWidth * 0.2
        let areaRight = worldWidth * 0.8
        let areaTop = worldHeight * 0.18
        let areaBottom = worldHeight * 0.82
        let columns = Int(ceil(sqrt(Double(sparkCount) * Double(worldWidth / max(worldHeight, 1)))))
        let rows = Int(ceil(Double(sparkCount) / Double(max(columns, 1))))
        let cellWidth = (areaRight - areaLeft) / CGFloat(max(columns, 1))
        let cellHeight = (areaBottom - areaTop) / CGFloat(max(rows, 1))

        for index in 0..<sparkCount {
            let localSeed = "\(seed):\(Int(worldWidth)):\(Int(worldHeight)):spark:\(index)"
            let size = baseUnit * mix(0.1, 0.24, seedF("\(localSeed):size"))
            let column = index % max(columns, 1)
            let row = index / max(columns, 1)
            let jitterX = mix(-0.32, 0.32, seedF("\(localSeed):jitter-x")) * cellWidth
            let jitterY = mix(-0.32, 0.32, seedF("\(localSeed):jitter-y")) * cellHeight
            let x = min(max(areaLeft + (CGFloat(column) + 0.5) * cellWidth + jitterX, areaLeft), areaRight)
            let y = min(max(areaTop + (CGFloat(row) + 0.5) * cellHeight + jitterY, areaTop), areaBottom)
            result.append(Shape(
                kind: .spark,
                x: x,
                y: y,
                size: size,
                rotation: mix(-.pi, .pi, seedF("\(localSeed):rotation")),
                rotationSpeed: mix(-0.18, 0.18, seedF("\(localSeed):rotation-speed")),
                strokeWidth: mix(0.75, 1.7, seedF("\(localSeed):stroke-width")),
                opacity: mix(0.08, 0.22, seedF("\(localSeed):opacity")),
                useAccent: seedF("\(localSeed):color") > 0.5,
                depth: seedF("\(localSeed):depth"),
                ringGapStart: 0,
                ringGapSize: 0
            ))
        }

        return result.sorted { $0.depth < $1.depth }
    }

        private func paperHaloAnchor(bounds: CGRect, worldWidth: CGFloat, worldHeight: CGFloat, size: CGFloat, seedKey: String) -> CGPoint {
        if seedF("\(seedKey):inside-chance") < 0.22 {
            return CGPoint(
                x: min(max(mix(bounds.minX + size * 0.12, bounds.maxX - size * 0.12, seedF("\(seedKey):inside-x")), 0), worldWidth),
                y: min(max(mix(bounds.minY + size * 0.12, bounds.maxY - size * 0.12, seedF("\(seedKey):inside-y")), 0), worldHeight)
            )
        }
        let side = Int(seedF("\(seedKey):side") * 4) % 4
        let overflowX = size * mix(0.16, 0.24, seedF("\(seedKey):overflow-x"))
        let overflowY = size * mix(0.16, 0.24, seedF("\(seedKey):overflow-y"))
        let jitterX = size * mix(-0.18, 0.18, seedF("\(seedKey):span-jitter-x"))
        let jitterY = size * mix(-0.18, 0.18, seedF("\(seedKey):span-jitter-y"))

        switch side {
        case 0:
            return CGPoint(
                x: min(max(bounds.minX - overflowX, 0), worldWidth),
                y: min(max(mix(bounds.minY - size * 0.12, bounds.maxY + size * 0.12, seedF("\(seedKey):y")) + jitterY, 0), worldHeight)
            )
        case 1:
            return CGPoint(
                x: min(max(bounds.maxX + overflowX, 0), worldWidth),
                y: min(max(mix(bounds.minY - size * 0.12, bounds.maxY + size * 0.12, seedF("\(seedKey):y")) + jitterY, 0), worldHeight)
            )
        case 2:
            return CGPoint(
                x: min(max(mix(bounds.minX - size * 0.12, bounds.maxX + size * 0.12, seedF("\(seedKey):x")) + jitterX, 0), worldWidth),
                y: min(max(bounds.minY - overflowY, 0), worldHeight)
            )
        default:
            return CGPoint(
                x: min(max(mix(bounds.minX - size * 0.12, bounds.maxX + size * 0.12, seedF("\(seedKey):x")) + jitterX, 0), worldWidth),
                y: min(max(bounds.maxY + overflowY, 0), worldHeight)
            )
        }
    }

    private func drawShape(_ shape: Shape, in context: inout GraphicsContext) {
                let layerResponse = mix(0.58, 1.16, shape.depth)
        let parallaxX = (view.cameraX - view.centerX) * (1 - layerResponse)
        let parallaxY = (view.cameraY - view.centerY) * (1 - layerResponse)
        let screenX = viewport.width / 2 + (shape.x + parallaxX - view.cameraX) * view.scale
        let screenY = viewport.height / 2 + (shape.y + parallaxY - view.cameraY) * view.scale
        let size = shape.size * view.scale
        let angle = shape.rotation + time * shape.rotationSpeed
        let opacity = min(max(shape.opacity * 1.0, 0), 0.42)

        let path = shapePath(shape, size: size)
        let transform = CGAffineTransform(translationX: screenX, y: screenY).rotated(by: angle)
        let transformed = path.applying(transform)

        if shape.kind == .spark {
            let color = shape.useAccent ? theme.accent : theme.secondary
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: color.opacity(opacity * 0.75), radius: max(10 * view.scale, 4)))
                layer.stroke(transformed, with: .color(color.opacity(opacity)), lineWidth: shape.strokeWidth * view.scale)
            }
        } else {
                        func strokeGradient(_ multiplier: Double) -> Gradient {
                Gradient(stops: [
                    .init(color: theme.secondary.opacity(opacity * 0.18 * multiplier), location: 0),
                    .init(color: mixColor(theme.secondary, theme.accent, 0.24).opacity(opacity * 0.58 * multiplier), location: 0.28),
                    .init(color: mixColor(theme.secondary, theme.accent, 0.62).opacity(opacity * 0.92 * multiplier), location: 0.54),
                    .init(color: theme.accent.opacity(opacity * 0.7 * multiplier), location: 1),
                ])
            }
            let start = CGPoint(x: screenX - size * 0.55, y: screenY - size * 0.28)
            let end = CGPoint(x: screenX + size * 0.55, y: screenY + size * 0.28)
            context.stroke(
                transformed,
                with: .linearGradient(strokeGradient(0.56), startPoint: start, endPoint: end),
                lineWidth: max(shape.strokeWidth * 0.28, 0.14) * view.scale
            )
            context.stroke(
                transformed,
                with: .linearGradient(strokeGradient(1), startPoint: start, endPoint: end),
                lineWidth: max(shape.strokeWidth * 0.92, 0.78) * view.scale
            )
        }
    }

    private func shapePath(_ shape: Shape, size: CGFloat) -> Path {
        var path = Path()
        let s = size
        switch shape.kind {
        case .ring:
                        let gapSize = min(max(shape.ringGapSize, 0.18), .pi * 0.6)
            path.addArc(
                center: .zero,
                radius: s / 2,
                startAngle: .radians(shape.ringGapStart + gapSize),
                endAngle: .radians(shape.ringGapStart + .pi * 2),
                clockwise: false
            )
        case .square:
            path.addRect(CGRect(x: -s / 2, y: -s / 2, width: s, height: s))
        case .cross:
            let arm = s * 0.3
            path.move(to: CGPoint(x: -arm, y: -s / 2))
            path.addLine(to: CGPoint(x: arm, y: -s / 2))
            path.addLine(to: CGPoint(x: arm, y: -arm))
            path.addLine(to: CGPoint(x: s / 2, y: -arm))
            path.addLine(to: CGPoint(x: s / 2, y: arm))
            path.addLine(to: CGPoint(x: arm, y: arm))
            path.addLine(to: CGPoint(x: arm, y: s / 2))
            path.addLine(to: CGPoint(x: -arm, y: s / 2))
            path.addLine(to: CGPoint(x: -arm, y: arm))
            path.addLine(to: CGPoint(x: -s / 2, y: arm))
            path.addLine(to: CGPoint(x: -s / 2, y: -arm))
            path.addLine(to: CGPoint(x: -arm, y: -arm))
            path.closeSubpath()
        case .spark:
            let outer = s / 2
            let inner = s * 0.13
            path.move(to: CGPoint(x: 0, y: -outer))
            path.addLine(to: CGPoint(x: inner, y: -inner))
            path.addLine(to: CGPoint(x: outer, y: 0))
            path.addLine(to: CGPoint(x: inner, y: inner))
            path.addLine(to: CGPoint(x: 0, y: outer))
            path.addLine(to: CGPoint(x: -inner, y: inner))
            path.addLine(to: CGPoint(x: -outer, y: 0))
            path.addLine(to: CGPoint(x: -inner, y: -inner))
            path.closeSubpath()
        }
        return path
    }

    private func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private func seedF(_ key: String) -> CGFloat {
        CGFloat(FumeArticleLayout.seeded(key))
    }

    private func mixColor(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let clamped = min(max(t, 0), 1)
        let ca = UIColor(a), cb = UIColor(b)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0
        ca.getRed(&ar, green: &ag, blue: &ab, alpha: nil)
        cb.getRed(&br, green: &bg, blue: &bb, alpha: nil)
        return Color(
            red: Double(ar + (br - ar) * clamped),
            green: Double(ag + (bg - ag) * clamped),
            blue: Double(ab + (bb - ab) * clamped)
        )
    }
}
