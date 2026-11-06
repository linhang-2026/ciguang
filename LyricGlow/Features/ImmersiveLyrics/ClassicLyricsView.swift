import SwiftUI
import UIKit

enum LyricsMode: String, CaseIterable, Identifiable {
    case fume
    case classic
    case still
    case tilt
    case partita
    case claddagh
    case cadenza
    case monet
    case cappella
    case diorama

    var id: String { rawValue }

        static var visibleModes: [LyricsMode] { [.fume, .classic, .diorama] }

        var label: String {
        switch self {
        case .fume: return "烬语"
        case .classic: return "萤川"
        case .still: return "Still"
        case .tilt: return "Tilt"
        case .partita: return "云阶"
        case .claddagh: return "Claddagh"
        case .cadenza: return "Mindscape"
        case .monet: return "Monet"
        case .cappella: return "Cappella"
        case .diorama: return "镜渊"
        }
    }
}

struct ClassicWordConfig {
    var x: CGFloat
    var y: CGFloat
    var rotate: CGFloat
    var scale: CGFloat
    var marginRight: CGFloat
    var passedRotate: CGFloat
}

struct ClassicLineLayout {
    enum Justify { case start, center, end, around, between }
    enum Align { case start, center, end }
    var justify: Justify
    var align: Align
}

enum ClassicLayout {

        static func random(seed: Double, offset: Double) -> Double {
        let x = sin(seed + offset) * 10000
        return x - x.rounded(.down)
    }

        static func lineLayout(seed: Double, isInterlude: Bool) -> ClassicLineLayout {
        if isInterlude {
            return ClassicLineLayout(justify: .center, align: .center)
        }
        let justify: [ClassicLineLayout.Justify] = [.start, .center, .end, .around, .between]
        let align: [ClassicLineLayout.Align] = [.start, .center, .end]
        let ji = Int(floor(seed.truncatingRemainder(dividingBy: 5)))
        let ai = Int(floor((seed * 2).truncatingRemainder(dividingBy: 3)))
        return ClassicLineLayout(
            justify: justify[max(0, min(ji, justify.count - 1))],
            align: align[max(0, min(ai, align.count - 1))]
        )
    }

            static func wordConfigs(words: [LyricWord], seed: Double, fontSize: CGFloat, isInterlude: Bool) -> [ClassicWordConfig] {
        let widths = words.map { measure($0.text, fontSize: fontSize) }
        var configs: [ClassicWordConfig] = []
        configs.reserveCapacity(words.count)

        for (i, _) in words.enumerated() {
            let wordSeed = seed + Double(i)
            func rnd(_ offset: Double) -> Double { random(seed: wordSeed, offset: offset) }

            if isInterlude {
                                configs.append(ClassicWordConfig(
                    x: 0,
                    y: (rnd(2) - 0.5) * 15,
                    rotate: 0,
                    scale: 1.5,
                    marginRight: 48,
                    passedRotate: 0
                ))
                continue
            }

            let scale = 1.1 + rnd(4) * 0.2
            let xVal = (rnd(1) - 0.5) * 40
            let yVal = (rnd(2) - 0.5) * 40

            var wNext: CGFloat = 0
            var sNext: CGFloat = 1
            var xNext: CGFloat = 0
            if i + 1 < words.count {
                func nrnd(_ offset: Double) -> Double { random(seed: seed + Double(i + 1), offset: offset) }
                sNext = (1.1 + nrnd(4) * 0.2) * 1.4
                xNext = (nrnd(1) - 0.5) * 40
                wNext = widths[i + 1]
            }

            let spacingMultiplier: CGFloat = 0.7
            let gap = fontSize * 0.05
            let halfOverflowSelf = widths[i] * (scale * 1.4 - 1) / 2
            let halfOverflowNext = wNext * (sNext - 1) / 2
            let calculated = (halfOverflowSelf + halfOverflowNext + (xVal - xNext) + gap) * spacingMultiplier
            let minMargin = fontSize * 0.12 * spacingMultiplier

                                    let margin = max(minMargin, calculated)

            configs.append(ClassicWordConfig(
                x: xVal,
                y: yVal,
                rotate: (rnd(3) - 0.5) * 10,
                scale: scale,
                marginRight: margin,
                passedRotate: (rnd(8) - 0.5) * 45
            ))
        }
        return configs
    }

    static func measure(_ text: String, fontSize: CGFloat) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: UIFont.boldSystemFont(ofSize: fontSize)]).width
    }
}

private struct ClassicWordView: View {
    let word: LyricWord
    let config: ClassicWordConfig
    let fontSize: CGFloat
    let theme: ThemeColors
    let t: Double
        let revealMode: String
        let lineRenderEnd: Double

        private var lookahead: Double {
        revealMode == "instant" ? 0.03 : revealMode == "fast" ? 0.08 : 0.15
    }

        private var activeEnd: Double {
        if revealMode == "instant" { return lineRenderEnd }
        if revealMode == "fast" { return min(lineRenderEnd, max(word.end, word.start + 0.12)) }
        return word.end
    }

    @State private var appeared = false

    private enum Status { case waiting, active, passed }

    private var status: Status {
        if t >= word.start - lookahead && t <= activeEnd { return .active }
        if t > activeEnd { return .passed }
        return .waiting
    }

        private var effectiveStatus: Status { appeared ? status : .waiting }

        private var duration: Double {
        let minDuration = revealMode == "instant" ? 0.08 : revealMode == "fast" ? 0.12 : 0.1
        return max(activeEnd - word.start, minDuration)
    }
    private var activation: Double { word.start - lookahead }
    private var chars: [Character] { Array(word.text) }

        private var bodyColor: Color {
        guard appeared else { return theme.primary }
        if t < activation { return theme.primary }
        if t <= activeEnd {
            let p = min(max((t - activation) / duration, 0), 1)
            return mixColor(theme.primary, theme.accent, p)
        }
        let p = min(max((t - activeEnd) / 0.8, 0), 1)
        return mixColor(theme.accent, theme.primary, easeInOut(p))
    }

        private var bodyBlur: CGFloat {
        guard appeared else { return 10 }
        if t < activation { return 10 }
        let fade = revealMode == "instant" ? 0.08 : revealMode == "fast" ? 0.12 : 0.2
        return 10 * (1 - min((t - activation) / fade, 1))
    }

                private func charGlow(_ index: Int) -> Double {
        guard appeared, t >= activation else { return 0 }
        let count = chars.count
        let wordDur = max(word.end - word.start, 0.001)
        var value: Double

        if count > 1 && revealMode != "instant" {
            let singleDur = wordDur / Double(count)
            let delay = singleDur * Double(index)
            let rampDur = singleDur * 6
            let p = (t - activation - delay) / rampDur
            if p <= 0 || p >= 1 {
                value = 0
            } else if p < 0.3 {
                value = easeInOut(p / 0.3)
            } else {
                value = 1 - easeInOut((p - 0.3) / 0.7)
            }
        } else {
            let p = (t - activation) / wordDur
            value = p <= 0 ? 0 : easeInOut(min(p / 0.9, 1))
        }

        if t > activeEnd {
            value *= 1 - easeOut(min((t - activeEnd) / 0.9, 1))
        }
        return min(max(value, 0), 1)
    }

    private var pose: (opacity: Double, scale: CGFloat, dx: CGFloat, dy: CGFloat, rotate: CGFloat) {
        switch effectiveStatus {
        case .waiting:
            return (0, 0.5,
                    config.x + sin(config.y) * 100,
                    config.y + cos(config.x) * 50,
                    config.rotate + 20)
        case .active:
            return (1, config.scale * 1.4, config.x, config.y, config.rotate)
        case .passed:
                        let drift = min(max((t - word.end) / 5, 0), 1)
            return (0.82, config.scale, config.x, config.y, config.rotate + config.passedRotate * drift)
        }
    }

    var body: some View {
        let pose = pose
        HStack(spacing: 0) {
            ForEach(chars.indices, id: \.self) { index in
                charView(index)
            }
        }
        .font(.system(size: fontSize, weight: .bold))
        .blur(radius: bodyBlur)
        .opacity(pose.opacity)
        .animation(.easeOut(duration: 0.12), value: effectiveStatus)
        .rotationEffect(.degrees(pose.rotate))
        .scaleEffect(pose.scale)
        .offset(x: pose.dx, y: pose.dy)
        .animation(.spring(response: 0.44, dampingFraction: 0.71), value: effectiveStatus)
        .onAppear { appeared = true }
    }

    @ViewBuilder
    private func charView(_ index: Int) -> some View {
        let glow = charGlow(index)
        let text = Text(String(chars[index])).foregroundStyle(bodyColor)
        if glow > 0.01 {
            text
                .shadow(color: theme.accent.opacity(0.7 * glow), radius: 8 * glow)
                .shadow(color: theme.accent.opacity(glow), radius: 16 * glow)
        } else {
            text
        }
    }
}

private struct ClassicFlowLayout: Layout {
    var justify: ClassicLineLayout.Justify
    var align: ClassicLineLayout.Align

    private struct Row {
        var items: [Int]
        var width: CGFloat
        var height: CGFloat
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
                                                let rowGap = (rows.first?.height ?? 0) * 1.4
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height }
            + CGFloat(max(rows.count - 1, 0)) * rowGap
        let width = maxWidth.isFinite ? maxWidth : (rows.map(\.width).max() ?? 0)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
                let rowGap = (rows.first?.height ?? 0) * 1.4
                let totalHeight = rows.reduce(CGFloat(0)) { $0 + $1.height }
            + CGFloat(max(rows.count - 1, 0)) * rowGap
        var y = bounds.minY + max((bounds.height - totalHeight) / 2, 0)

        for row in rows {
            let count = row.items.count
                        let free = max(bounds.width - row.width, 0)
            var gap: CGFloat = 0
            var lead: CGFloat = 0
            switch justify {
            case .start: break
            case .center: lead = free / 2
            case .end: lead = free
            case .between:
                if count > 1 { gap = free / CGFloat(count - 1) }
            case .around:
                                gap = free / CGFloat(count)
                lead = gap / 2
            }

            var x = bounds.minX + lead
            for (position, index) in row.items.enumerated() {
                let size = subviews[index].sizeThatFits(.unspecified)
                if position > 0 { x += gap }
                let itemY: CGFloat
                switch align {
                case .start: itemY = y
                case .center: itemY = y + (row.height - size.height) / 2
                case .end: itemY = y + row.height - size.height
                }
                subviews[index].place(at: CGPoint(x: x, y: itemY), proposal: ProposedViewSize(size))
                x += size.width
            }
            y += row.height + rowGap
        }
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row(items: [], width: 0, height: 0)
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !current.items.isEmpty, current.width + size.width > maxWidth {
                rows.append(current)
                current = Row(items: [], width: 0, height: 0)
            }
            current.items.append(index)
            current.width += size.width
            current.height = max(current.height, size.height)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

struct ClassicLyricsView: View {
    let scheduler: LyricScheduler
    let theme: ThemeColors

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        GeometryReader { geo in
            let fontSize = Self.mainFontSize(width: geo.size.width)
                        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                let t = PlayerCenter.shared.lyricClock
                let now = context.date.timeIntervalSinceReferenceDate
                let active = activeLine(at: t)

                ZStack {
                    if let line = active {
                                                                                                let enterMode = Self.transitionMode(for: line)
                        let enterT: Double = enterMode == "none" ? 0 : enterMode == "fast" ? 0.16 : 0.3
                        let enterP = enterT <= 0 ? 1 : min(max((t - line.start) / enterT, 0), 1)
                                                                        if let prev = previousVisibleLine(before: line),
                           line.start - prev.end < 1.5 {
                                                        let exitMode = Self.transitionMode(for: prev)
                            let exitT: Double = exitMode == "none" ? 0.12 : exitMode == "fast" ? 0.16 : 0.3
                            let exitP = min(max((t - line.start) / exitT, 0), 1)
                            if exitP < 1 {
                                                                let e = exitMode == "normal" ? exitP : easeOut(exitP)
                                let (sc, bl) = exitMode == "none" ? (1.02, 6.0)
                                    : exitMode == "fast" ? (1.04, 10.0) : (1.1, 20.0)
                                lineContent(line: prev, fontSize: fontSize, t: t, now: now,
                                            poseOpacity: 1 - e, poseScale: 1 + (sc - 1) * e, poseBlur: bl * e)
                            }
                        }
                                                let pose = Self.enterPose(p: enterP, mode: enterMode)
                        lineContent(line: line, fontSize: fontSize, t: t, now: now,
                                    poseOpacity: pose.op, poseScale: pose.scale, poseBlur: pose.blur)
                    } else {
                        Text("等待音乐")
                            .font(.system(size: Self.emptyFontSize(width: geo.size.width)))
                            .foregroundStyle(theme.secondary.opacity(0.5))
                    }
                }
                .overlay(alignment: .bottom) {
                    subtitleOverlay(activeLine: active, t: t, fontSize: geo.size.width)
                }
            }
        }
    }

        static func transitionMode(for line: LyricLine) -> String {
        let cls = RenderHints.timingClass(rawDuration: max(line.end - line.start, 0))
        if cls == "micro" { return "none" }
        if cls == "short" { return "fast" }
        return "normal"
    }

        static func revealMode(for line: LyricLine) -> String {
        let cls = RenderHints.timingClass(rawDuration: max(line.end - line.start, 0))
        if cls == "micro" { return "instant" }
        if cls == "short" { return "fast" }
        return "normal"
    }

        static func enterPose(p: Double, mode: String) -> (op: Double, scale: Double, blur: Double) {
        if mode == "none" { return (1, 1, 0) }
        if mode == "fast" {
            let e = easeOut(p)
            return (0.35 + 0.65 * e, 0.96 + 0.04 * e, 4 * (1 - e))
        }
        return (p, 0.9 + 0.1 * p, 10 * (1 - p))
    }

    private func activeLine(at t: Double) -> LyricLine? {
        let lines = scheduler.lyrics.lines
        guard let index = scheduler.activeLineIndex(at: t) else { return nil }
        let line = lines[index]
        let deadline: Double
        if index + 1 < lines.count {
            deadline = lines[index + 1].start
        } else {
            deadline = line.end + 3
        }
        guard t <= deadline else { return nil }
                return line.plainText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : line
    }

    private func lineContent(line: LyricLine, fontSize: CGFloat, t: Double, now: Double,
                             poseOpacity: Double, poseScale: CGFloat, poseBlur: CGFloat) -> some View {
        let seed = line.start
        let isInterlude = line.plainText == "......"
        let layout = ClassicLayout.lineLayout(seed: seed, isInterlude: isInterlude)
        let configs = ClassicLayout.wordConfigs(words: line.words, seed: seed, fontSize: fontSize, isInterlude: isInterlude)
        let breath = Self.breath(now: now)
        let reveal = Self.revealMode(for: line)
        let renderEnd = RenderHints.renderEndTime(line: line)

        return ClassicFlowLayout(justify: layout.justify, align: layout.align) {
            ForEach(Array(line.words.enumerated()), id: \.offset) { index, word in
                ClassicWordView(word: word, config: configs[index], fontSize: fontSize, theme: theme, t: t,
                                revealMode: reveal, lineRenderEnd: renderEnd)
                    .padding(.trailing, configs[index].marginRight)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: 1152 + 64, maxHeight: .infinity)
        .scaleEffect(breath.scale * poseScale)
        .offset(y: breath.y)
        .opacity(poseOpacity)
        .blur(radius: poseBlur)
    }

        private func previousVisibleLine(before line: LyricLine) -> LyricLine? {
        let lines = scheduler.lyrics.lines
        guard let index = lines.firstIndex(where: { $0.start == line.start }) else { return nil }
        var i = index - 1
        while i >= 0 {
            let candidate = lines[i]
            if !candidate.plainText.trimmingCharacters(in: .whitespaces).isEmpty { return candidate }
            i -= 1
        }
        return nil
    }

    @ViewBuilder
    private func subtitleOverlay(activeLine: LyricLine?, t: Double, fontSize width: CGFloat) -> some View {
        if let activeLine {
            let lines = scheduler.lyrics.lines
            let index = scheduler.activeLineIndex(at: t) ?? 0
            let upcoming = lines[(index + 1)...]
                .prefix(2)
                .filter { hasReadableText($0.plainText) }
            if !upcoming.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(upcoming.enumerated()), id: \.offset) { _, line in
                        Text(line.plainText)
                            .font(.system(size: Self.upcomingFontSize(width: width)))
                            .foregroundStyle(theme.secondary)
                            .lineLimit(1)
                            .blur(radius: 1)
                            .frame(maxWidth: 560)
                    }
                }
                .opacity(0.6)
                .padding(.bottom, verticalSizeClass == .compact ? 96 : 150)
                .allowsHitTesting(false)
            }
        }
    }

        static func mainFontSize(width: CGFloat) -> CGFloat {
        min(max(width * 0.06, 36), 72)
    }

        static func emptyFontSize(width: CGFloat) -> CGFloat {
        min(max(width * 0.035, 24), 36)
    }

        static func upcomingFontSize(width: CGFloat) -> CGFloat {
        min(max(width * 0.02, 14), 16)
    }

    static func breath(now: Double) -> (y: CGFloat, scale: CGFloat) {
        let phase = now.truncatingRemainder(dividingBy: 7) / 7
        return (
            CGFloat(keyframe(phase, [0, -14, 0, 6.3, 0])),
            CGFloat(keyframe(phase, [1, 1.01, 1, 0.995, 1]))
        )
    }

        private static func keyframe(_ p: Double, _ values: [Double]) -> Double {
        let n = values.count - 1
        guard n > 0 else { return values.first ?? 0 }
        let x = min(max(p, 0), 1) * Double(n)
        let segment = min(Int(x), n - 1)
        let local = x - Double(segment)
        let e = easeInOut(local)
        return values[segment] + (values[segment + 1] - values[segment]) * e
    }

    private func hasReadableText(_ text: String) -> Bool {
        text.range(of: #"[\p{L}\p{N}]"#, options: .regularExpression) != nil
    }
}

private func easeInOut(_ x: Double) -> Double {
    let c = min(max(x, 0), 1)
    return c * c * (3 - 2 * c)
}

private func easeOut(_ x: Double) -> Double {
    let c = min(max(x, 0), 1)
    return 1 - pow(1 - c, 3)
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
