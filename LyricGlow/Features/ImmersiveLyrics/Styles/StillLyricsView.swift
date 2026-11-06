import SwiftUI

struct StillLyricsView: View {
    let scheduler: LyricScheduler
    let theme: ThemeColors

    var body: some View {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let t = PlayerCenter.shared.lyricClock
            let lines = scheduler.lyrics.lines
                                    let effectiveIndex = scheduler.activeLineIndex(at: t) ?? 0

            ZStack {
                                RadialGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    center: .center,
                    startRadius: 0,
                    endRadius: UIScreen.main.bounds.width * 0.9
                )
                .allowsHitTesting(false)

                                VStack(spacing: 32) {
                    ForEach([-1, 0, 1], id: \.self) { offset in
                        let lineIndex = effectiveIndex + offset
                        if lines.indices.contains(lineIndex), !lines[lineIndex].plainText.isEmpty {
                            lineText(lines[lineIndex], isCurrent: offset == 0)
                        } else {
                                                        Color.clear.frame(height: 80)
                        }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 64)
                .frame(maxWidth: 896)
            }
        }
    }

        private func lineText(_ line: LyricLine, isCurrent: Bool) -> some View {
        Text(line.plainText)
            .font(.system(size: isCurrent ? 40 : 30, weight: isCurrent ? .bold : .semibold))
            .tracking(isCurrent ? 40 * 0.02 : 30 * 0.02)
            .foregroundStyle(theme.primary.opacity(isCurrent ? 1 : 0.3))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}
