import SwiftUI

struct FumeBlockView: View {
    enum Mode {
        case waiting
        case passedStatic
        case live(Double)
    }

    let block: FumeBlock
    let mode: Mode
    let nextLineStart: Double?
    let theme: ThemeColors

    private var isHero: Bool { block.isHero }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(block.renderLines.enumerated()), id: \.offset) { index, renderLine in
                lineView(index: index, renderLine: renderLine)
                    .frame(width: block.width, height: block.lineHeight, alignment: .leading)
            }
        }
        .frame(width: block.width, height: block.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func lineView(index: Int, renderLine: FumeRenderLine) -> some View {
        switch mode {
        case .waiting:
            Text(renderLine.text)
                .foregroundStyle(theme.primary.opacity(isHero ? 0.06 : 0.035))
                .offset(x: renderLine.left)
        case .passedStatic:
            Text(renderLine.text)
                .foregroundStyle(theme.primary.opacity(isHero ? 0.74 : 0.58))
                .offset(x: renderLine.left)
        case .live(let time):
            HStack(spacing: 0) {
                ForEach(Array(block.wordSlices[index].enumerated()), id: \.offset) { _, slice in
                    WordView(
                        slice: slice,
                        state: wordState(slice.word, time: time),
                        fontPx: block.fontPx,
                        lineHeight: block.lineHeight,
                        theme: theme,
                        isHero: isHero
                    )
                }
            }
            .offset(x: renderLine.left)
                        .shadow(color: theme.accent.opacity(lineGlowAlpha(time: time)), radius: lineGlowRadius / 2)
        }
    }

        private var passCutoff: Double { nextLineStart ?? .infinity }

    private var lineDuration: Double {
        max((block.line.words.last?.end ?? block.line.start) - block.line.start, 0.18)
    }
    private var colorTrailDuration: Double {
        min(max(lineDuration * (isHero ? 0.42 : 0.52), 0.45), 1.45)
    }

    private func lineGlowAlpha(time: Double) -> Double {
        guard time >= block.line.start, time < passCutoff else { return 0 }
        let progress = min(max((time - block.line.start) / max(lineDuration, 0.01), 0), 1)
        let envelope = min(max((progress - 0.2) / 0.8, 0), 1)
        return (isHero ? 0.16 : 0.12) + envelope * (isHero ? 0.26 : 0.2)
    }

    private var lineGlowRadius: Double {
        (isHero ? 12 : 8) + Double(block.fontPx) * (isHero ? 0.7 : 0.52)
    }

    private func wordState(_ word: LyricWord, time: Double) -> WordState {
        if time >= passCutoff {
            return .passedTrail(1)
        }
        if time < word.start {
            return .waiting
        }
        let duration = max(word.end - word.start, 0.08)
        let trailStart = word.start + duration * 0.18
        if time <= trailStart {
            let progress = min(max((time - word.start) / duration + 0.16, 0), 1)
            return .lighting(easeOutCubic(progress))
        }
        let trail = pow(min(max((time - trailStart) / colorTrailDuration, 0), 1), 1.35)
        return .passedTrail(trail)
    }
}

private enum WordState {
    case waiting
    case lighting(Double)
    case passedTrail(Double)
}

private struct WordView: View {
    let slice: FumeWordSlice
    let state: WordState
    let fontPx: CGFloat
    let lineHeight: CGFloat
    let theme: ThemeColors
    let isHero: Bool

    private var activeOpacity: Double { isHero ? 0.985 : 0.92 }
    private var waitingOpacity: Double { isHero ? 0.06 : 0.035 }
    private var passedOpacity: Double { isHero ? 0.74 : 0.58 }

    var body: some View {
        Group {
            switch state {
            case .waiting:
                Text(slice.text)
                    .foregroundStyle(theme.primary.opacity(waitingOpacity))
            case .lighting(let eased):
                Text(slice.text)
                    .foregroundStyle(
                        Self.mix(theme.primary, theme.accent, 0.22 + eased * 0.78)
                            .opacity(waitingOpacity + (activeOpacity - waitingOpacity) * eased)
                    )
                    .shadow(color: theme.accent.opacity(0.4 + eased * 0.44),
                           radius: (4 + fontPx * 0.22) * eased * 0.92 * 0.5)
            case .passedTrail(let trail):
                let color = Self.mix(theme.accent, theme.primary, 0.18 + trail * 0.82)
                Text(slice.text)
                    .foregroundStyle(
                        color.opacity(activeOpacity + (passedOpacity - activeOpacity) * trail)
                    )
                    .shadow(
                        color: Self.mix(theme.accent, theme.primary, 0.55 + trail * 0.45)
                            .opacity(0.1 + (1 - trail) * 0.16),
                        radius: (2 + fontPx * 0.1) * (1 - trail * 0.35) * 0.62 * 0.5
                    )
            }
        }
        .overlay(alignment: .top) { printStamp }
    }

                        @ViewBuilder
    private var printStamp: some View {
        if case .lighting(let eased) = state {
            let isCJK = slice.text.first?.isCJK ?? false
                        let pulse = 0.18 + (1 - 0.18) * pow(eased, 0.78)
            let glyphVisualWidth = max(fontPx * (isCJK ? 0.95 : 0.6) * 0.88, fontPx * (isCJK ? 0.56 : 0.38))
            let stampWidth = glyphVisualWidth + fontPx * (isHero ? 0.18 : 0.12)
            let stampHeight = fontPx * (isHero ? 0.72 : 0.62)
            let dropDistance = lineHeight * (isHero ? 0.24 : 0.2)

            Rectangle()
                .fill(theme.accent.opacity((isHero ? 0.82 : 0.72) * pulse))
                .frame(width: stampWidth, height: stampHeight)
                .shadow(color: theme.accent.opacity(0.56 * pulse), radius: (8 + fontPx * 0.24) * pulse * 0.5)
                .offset(y: -stampHeight * 0.5 - fontPx * 0.38 - dropDistance * (1 - eased))
                .allowsHitTesting(false)
        }
    }

        static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let clamped = min(max(t, 0), 1)
        return Color(
            red: a.redValue + (b.redValue - a.redValue) * clamped,
            green: a.greenValue + (b.greenValue - a.greenValue) * clamped,
            blue: a.blueValue + (b.blueValue - a.blueValue) * clamped
        )
    }
}

private func easeOutCubic(_ t: Double) -> Double {
    1 - pow(1 - t, 3)
}

private extension Character {
    var isCJK: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x2E80...0x9FFF, 0xF900...0xFAFF, 0x3000...0x303F, 0xFF00...0xFFEF:
            return true
        default:
            return false
        }
    }
}

private extension Color {
    var redValue: Double { UIColor(self).components.r }
    var greenValue: Double { UIColor(self).components.g }
    var blueValue: Double { UIColor(self).components.b }
}

private extension UIColor {
    var components: (r: Double, g: Double, b: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }
}
