import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var theme: ThemeColors = .fallback
    @State private var scrubRatio: Double?
    @State private var showLyrics = false

    private var player: PlayerCenter { PlayerCenter.shared }
    private var track: PlayableTrack? { player.currentTrack }

    var body: some View {
        ZStack {
            LatticeBackdrop(theme: theme)
            if let track {
                GeometryReader { geo in
                    posterWall(in: geo.size)
                    expandedPoster(track, in: geo.size)
                }
            } else {
                emptyState
            }
        }
        .preferredColorScheme(.dark)
        .task(id: track?.id) { loadTheme() }
        .fullScreenCover(isPresented: $showLyrics) {
            ImmersiveLyricsView()
        }
        .overlay(alignment: .topLeading) { backButton }
    }

    private func loadTheme() {
        if let data = track?.artworkData,
           let dominant = ThemeExtractor.dominantColor(from: data) {
            theme = .from(dominant: dominant)
        } else {
            theme = .fallback
        }
    }

        private func posterWall(in size: CGSize) -> some View {
        let others = player.tracks.enumerated()
            .filter { $0.element.id != track?.id }
            .map { (index: $0.offset, track: $0.element) }
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(others, id: \.track.id) { item in
                wallPoster(item.track, queueIndex: item.index + 1)
                    .onTapGesture {
                        player.play(player.tracks, at: item.index)
                    }
            }
        }
        .padding(10)
        .frame(width: size.width, height: size.height, alignment: .top)
        .overlay(Color.black.opacity(0.78))
        .ignoresSafeArea()
    }

        private func wallPoster(_ item: PlayableTrack, queueIndex: Int) -> some View {
        ZStack(alignment: .bottomLeading) {
            artworkImage(item.artworkData)
                        LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.05), location: 0.34),
                    .init(color: .black.opacity(0.24), location: 0.56),
                    .init(color: .black.opacity(0.92), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(0.92))
                Text(item.artist)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(8)
        }
        .overlay(alignment: .topLeading) {
            badgeText(String(format: "%02d", queueIndex), accent: false)
                .padding(8)
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
    }

    private func expandedPoster(_ track: PlayableTrack, in size: CGSize) -> some View {
        let isLandscape = size.width > size.height
        let side = isLandscape
            ? min(size.width * 0.42, size.height * 0.78)
            : min(size.width * 0.9, size.height * 0.6)

        return ZStack(alignment: .bottom) {
            artworkImage(track.artworkData)

                        LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0.54),
                    .init(color: .black.opacity(0.26), location: 0.70),
                    .init(color: .black.opacity(0.62), location: 0.86),
                    .init(color: .black.opacity(0.86), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.88), location: 0),
                    .init(color: .black.opacity(0.5), location: 0.52),
                    .init(color: .black.opacity(0.08), location: 1.0),
                ],
                startPoint: .leading, endPoint: .trailing
            )

                        VStack(alignment: .leading, spacing: 7) {
                Text(track.title)
                    .font(.system(size: 40, weight: .bold))
                    .kerning(-1.8)
                    .lineSpacing(-2)
                    .minimumScaleFactor(0.55)
                    .lineLimit(2)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                Text(track.artist)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.78))
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 128)

            chrome
        }
        .frame(width: side, height: side)
        .clipped()
        .shadow(color: .black.opacity(0.74), radius: 50, y: 26)
        .overlay(alignment: .topLeading) {
            badgeText("正在播放 · \(String(format: "%02d", player.index + 1))", accent: true)
                .padding(14)
        }
        .position(x: size.width / 2, y: isLandscape ? size.height * 0.5 : size.height * 0.42)
    }

        private func badgeText(_ text: String, accent: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy).monospacedDigit())
            .tracking(1.3)
            .foregroundStyle(accent ? theme.accent : .white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(accent ? 0.78 : 0.62))
    }

    private var chrome: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                chromeButton("backward.fill") {
                    player.previous()
                }
                .disabled(player.index == 0)

                chromeButton(player.isPlaying ? "pause.fill" : "play.fill", iconSize: 22) {
                    player.playPause()
                }

                chromeButton("forward.fill") {
                    player.next()
                }
                .disabled(player.index >= player.tracks.count - 1)

                Spacer(minLength: 12)

                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                    let elapsed = scrubRatio.map { $0 * player.duration }
                        ?? min(player.liveTime, player.duration)
                    Text("\(fmt(elapsed)) / \(fmt(player.duration))")
                        .font(.system(size: 12, design: .monospaced).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                chromeButton("arrow.up.right") {
                    showLyrics = true
                }
            }

            progressLine
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
    }

    private func chromeButton(_ icon: String, iconSize: CGFloat = 20, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

        private var progressLine: some View {
        GeometryReader { geo in
                                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                let ratio = scrubRatio
                    ?? (player.duration > 0 ? min(player.liveTime / player.duration, 1) : 0)
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.2))
                        .frame(height: 2)
                    Rectangle()
                        .fill(.white.opacity(0.85))
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
        .frame(height: 36)
    }

    private func artworkImage(_ data: Data?) -> some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(white: 0.1)
                    Image(systemName: "music.note")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.3), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "music.note")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
            Text("队列为空")
                .font(.system(size: 17, weight: .semibold))
                .tracking(2.6)
                .foregroundStyle(.white.opacity(0.9))
            Text("回到曲库选择一首歌")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fmt(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
