import SwiftUI

private enum CadenzaMath {
    static func clamp(_ v: Double, _ min: Double, _ max: Double) -> Double {
        Swift.min(Swift.max(v, min), max)
    }
    static func mix(_ from: Double, _ to: Double, _ amount: Double) -> Double {
        from + (to - from) * amount
    }
    static func easeOutCubic(_ v: Double) -> Double {
        1 - pow(1 - clamp(v, 0, 1), 3)
    }
    static func easeInOutQuad(_ v: Double) -> Double {
        let n = clamp(v, 0, 1)
        return n < 0.5 ? 2 * n * n : 1 - pow(-2 * n + 2, 2) / 2
    }
        static func graphemes(_ text: String) -> [String] {
        text.map { String($0) }
    }
    static func isCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { sc in
            (0x4E00...0x9FA5).contains(sc.value)
                || (0x3040...0x30FF).contains(sc.value)
                || (0xAC00...0xD7AF).contains(sc.value)
        }
    }
        static func seededRandom(_ seed: Double, _ offset: Double) -> Double {
        let x = sin(seed + offset) * 10000
        return x - x.rounded(.down)
    }
}

private let ACTIVE_PULSE_FREQUENCY = 10.0

private enum CadenzaWordStatus { case waiting, passed, active }

private struct GraphemeTiming {
    var start: Double
    var end: Double
}

private func buildWordGraphemeTimings(_ word: LyricWord) -> [GraphemeTiming] {
    let glyphs = CadenzaMath.graphemes(word.text)
    guard !glyphs.isEmpty else { return [] }
    let duration = max(word.end - word.start, 0)
    let unit = duration / Double(glyphs.count)
    return glyphs.enumerated().map { i, _ in
        GraphemeTiming(
            start: word.start + unit * Double(i),
            end: i == glyphs.count - 1 ? word.end : word.start + unit * Double(i + 1)
        )
    }
}

private struct LineRenderTiming {
    var renderEndTime: Double
    var wordRevealMode: String
    var lastWordEndTime: Double
    var linePassHold: Double
    var enterDuration: Double
    var exitDuration: Double
}

private func resolveLineRenderTiming(_ line: LyricLine) -> LineRenderTiming {
    let rawDuration = max(line.end - line.start, 0)
    let timingClass = RenderHints.timingClass(rawDuration: rawDuration)
    let wordRevealMode: String = timingClass == "micro" ? "instant" : timingClass == "short" ? "fast" : "normal"
    let transitionModeNone = timingClass == "micro"
    let transitionModeFast = timingClass == "short"

    let enter: Double, exit: Double, hold: Double
    if transitionModeNone {
        enter = 0; exit = 0; hold = 0
    } else if transitionModeFast {
        enter = CadenzaMath.clamp(rawDuration * 0.45, 0.045, 0.06)
        exit = CadenzaMath.clamp(rawDuration * 0.22, 0.03, 0.04)
        hold = wordRevealMode == "instant" ? 0 : 0.03
    } else {
        enter = min(0.42, max(0.22, max(rawDuration, 0.12) * 0.34))
        exit = min(0.32, max(0.18, max(rawDuration, 0.12) * 0.18))
        hold = wordRevealMode == "instant" ? 0 : 0.06
    }
    return LineRenderTiming(
        renderEndTime: RenderHints.renderEndTime(line: line),
        wordRevealMode: wordRevealMode,
        lastWordEndTime: line.words.last?.end ?? line.end,
        linePassHold: hold,
        enterDuration: enter,
        exitDuration: exit
    )
}

private func getWordStatus(_ t: Double, _ timing: LineRenderTiming, _ word: LyricWord) -> CadenzaWordStatus {
    let lookahead = timing.wordRevealMode == "fast" ? 0.045 : timing.wordRevealMode == "instant" ? 0 : 0.18
    let activeEnd = timing.wordRevealMode == "instant" ? timing.renderEndTime : word.end
    if t >= word.start - lookahead && t <= activeEnd { return .active }
    if t > activeEnd { return .passed }
    return .waiting
}

private func getWordProgress(_ t: Double, _ mode: String, _ word: LyricWord) -> Double {
    if mode == "instant" { return t < word.start ? 0 : 1 }
    let minDuration = mode == "fast" ? 0.045 : 0.01
    let duration = max(word.end - word.start, minDuration)
    return CadenzaMath.clamp((t - word.start) / duration, 0, 1)
}

private func keyframedGlow(_ progress: Double) -> Double {
    if progress <= 0 || progress >= 1 { return 0 }
    if progress < 0.3 { return CadenzaMath.easeOutCubic(progress / 0.3) }
    return 1 - CadenzaMath.clamp((progress - 0.3) / 0.7, 0, 1)
}

private func glowEnvelope(_ t: Double, _ timing: LineRenderTiming, _ word: LyricWord) -> Double {
    if timing.wordRevealMode == "instant" {
        guard t >= word.start && t <= timing.renderEndTime else { return 0 }
        return keyframedGlow(CadenzaMath.clamp((t - word.start) / 0.067, 0, 1))
    }
    if timing.wordRevealMode == "fast" {
        let duration = max(word.end - word.start, 0.045)
        if t < word.start { return 0 }
        if t <= word.end {
            let p = CadenzaMath.clamp((t - word.start) / duration, 0, 1)
            if p < 0.14 { return CadenzaMath.easeOutCubic(p / 0.14) }
            if p < 0.82 { return 1 }
            return CadenzaMath.mix(1, 0.92, (p - 0.82) / 0.18)
        }
        let fadeOut = CadenzaMath.clamp((t - word.end) / 0.14, 0, 1)
        return pow(1 - fadeOut, 2)
    }
    let duration = max(word.end - word.start, 0.1)
    if t < word.start { return 0 }
    if t <= word.end {
        let p = CadenzaMath.clamp((t - word.start) / duration, 0, 1)
        if p < 0.18 { return CadenzaMath.easeOutCubic(p / 0.18) }
        if p < 0.9 { return 1 }
        return CadenzaMath.mix(1, 0.9, (p - 0.9) / 0.1)
    }
    let fadeOut = CadenzaMath.clamp((t - word.end) / 0.9, 0, 1)
    return 0.9 * pow(1 - fadeOut, 2)
}

private func charGlow(_ t: Double, _ word: LyricWord, glyphIndex: Int, glyphCount: Int, _ timings: [GraphemeTiming]) -> Double {
    let duration = max(word.end - word.start, 0.1)
    let single = duration / Double(max(glyphCount, 1))
    let charDuration: Double
    let charStart: Double
    if glyphIndex < timings.count {
        charDuration = max(timings[glyphIndex].end - timings[glyphIndex].start, 0.001)
        charStart = timings[glyphIndex].start
    } else {
        charDuration = single
        charStart = word.start + single * Double(glyphIndex)
    }
    let animationDuration = charDuration * 6
    let elapsed = t - charStart
    let active = elapsed <= 0 ? 0 : keyframedGlow(elapsed / animationDuration)
    if t <= word.end { return active }
    let fadeOut = pow(1 - CadenzaMath.clamp((t - word.end) / 0.9, 0, 1), 2)
    return active * fadeOut
}

private func bodyMix(_ t: Double, _ timing: LineRenderTiming, _ word: LyricWord) -> Double {
    if timing.wordRevealMode == "instant" {
        if t < word.start { return 0 }
        return t <= timing.renderEndTime ? 1 : 0
    }
    if t < word.start { return 0 }
    if t <= word.end { return getWordProgress(t, timing.wordRevealMode, word) }
    let fadeOut = CadenzaMath.clamp((t - word.end) / (timing.wordRevealMode == "fast" ? 0.12 : 0.8), 0, 1)
    return 1 - fadeOut
}

private struct LineEnvelope { var opacity: Double; var scale: Double; var blur: Double }

private func lineEnvelope(_ t: Double, _ line: LyricLine, _ timing: LineRenderTiming, timingClass: String) -> LineEnvelope {
    if timingClass == "micro" { return LineEnvelope(opacity: 1, scale: 1, blur: 0) }
    let linePassStart = max(timing.lastWordEndTime, line.start) + timing.linePassHold

    if timingClass == "short" {
        let exitStart = max(line.start + timing.enterDuration + 0.01, linePassStart, timing.renderEndTime - timing.exitDuration)
        let enterP = CadenzaMath.easeOutCubic(CadenzaMath.clamp((t - line.start) / timing.enterDuration, 0, 1))
        var opacity = CadenzaMath.mix(0.65, 1, enterP)
        var scale = CadenzaMath.mix(0.97, 1, enterP)
        var blur = CadenzaMath.mix(4, 0, enterP)
        let exitP = CadenzaMath.easeOutCubic(CadenzaMath.clamp((t - exitStart) / timing.exitDuration, 0, 1))
        if exitP > 0 {
            opacity = CadenzaMath.mix(opacity, 0, exitP)
            scale = CadenzaMath.mix(scale, 1.03, exitP)
            blur = max(blur, CadenzaMath.mix(0, 6, exitP))
        }
        return LineEnvelope(opacity: CadenzaMath.clamp(opacity, 0, 1), scale: scale, blur: blur)
    }

    let preEnter = min(0.1, timing.enterDuration * 0.35)
    let enterP = CadenzaMath.easeOutCubic(CadenzaMath.clamp((t - (line.start - preEnter)) / (timing.enterDuration + preEnter), 0, 1))
    var opacity = CadenzaMath.mix(0, 1, enterP)
    var scale = CadenzaMath.mix(0.9, 1, enterP)
    var blur = CadenzaMath.mix(10, 0, enterP)
    let exitStart = max(linePassStart, timing.renderEndTime - timing.exitDuration)
    let exitP = CadenzaMath.easeOutCubic(CadenzaMath.clamp((t - exitStart) / timing.exitDuration, 0, 1))
    if exitP > 0 {
        opacity *= 1 - exitP
        scale = CadenzaMath.mix(scale, 1.1, exitP)
        blur = max(blur, CadenzaMath.mix(0, 20, exitP))
    }
    return LineEnvelope(opacity: CadenzaMath.clamp(opacity, 0, 1), scale: scale, blur: blur)
}

private func passedDrift(_ t: Double, _ word: LyricWord) -> Double {
    if t <= word.end { return 0 }
    return CadenzaMath.easeInOutQuad(CadenzaMath.clamp((t - word.end) / 5, 0, 1))
}

private struct SegmentMeta {
    var graphemeStart: Int
    var graphemeEnd: Int
    var text: String
    var width: CGFloat
}

private struct WordRange {
    var wordIndex: Int
    var word: LyricWord
    var start: Int
    var end: Int
    var timings: [GraphemeTiming]
}

private struct WordFragment {
    var wordIndex: Int
    var word: LyricWord
    var text: String
    var startX: CGFloat
    var endX: CGFloat
    var fragmentStartInWord: Int
    var wordGraphemeCount: Int
    var wordTimings: [GraphemeTiming]
    var fragmentIndexInWord: Int
    var fragmentCountInWord: Int
    var isSplitAcrossLines: Bool
}

private struct WordPlacement {
    var id: String
    var wordIndex: Int
    var word: LyricWord
    var text: String
    var glyphs: [String]
    var isCJKText: Bool
    var x: Double
    var y: Double
    var width: CGFloat
    var height: CGFloat
    var scale: Double
    var passedRotate: Double
    var passedDriftX: Double
    var passedDriftY: Double
    var fragmentStartInWord: Int
    var wordGraphemeCount: Int
    var wordTimings: [GraphemeTiming]
    var isInterlude: Bool
}

private struct CadenzaPreparedState {
    var fontPx: CGFloat
    var lineHeight: CGFloat
    var maxWidth: CGFloat
    var lineCount: Int
    var placements: [WordPlacement]

        struct LineView {
        var width: CGFloat
        var fragments: [WordFragment]
    }
    var lineViews: [LineView]
}

private enum CadenzaLayout {
        static func measureWidth(_ text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

        static func buildSegments(_ text: String, font: UIFont) -> (segments: [SegmentMeta], graphemes: [String]) {
        var segments: [SegmentMeta] = []
        var graphemes: [String] = []
        var cursor = 0
        var buffer = ""
        var bufferWidth: CGFloat = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            segments.append(SegmentMeta(graphemeStart: cursor, graphemeEnd: cursor + buffer.count, text: buffer, width: bufferWidth))
            cursor += buffer.count
            graphemes.append(contentsOf: buffer.map { String($0) })
            buffer = ""
            bufferWidth = 0
        }

        for ch in text {
            if ch.isLetter || ch.isNumber {
                buffer.append(ch)
            } else {
                flush()
                let s = String(ch)
                segments.append(SegmentMeta(graphemeStart: cursor, graphemeEnd: cursor + 1, text: s, width: measureWidth(s, font: font)))
                cursor += 1
                graphemes.append(s)
            }
        }
        flush()
        return (segments, graphemes)
    }

        static func findWordRanges(_ line: LyricLine, _ graphemes: [String]) -> [WordRange] {
        var ranges: [WordRange] = []
        var cursor = 0
        for (wordIndex, word) in line.words.enumerated() {
            let target = CadenzaMath.graphemes(word.text)
            var start = -1
            if !target.isEmpty {
                var i = cursor
                while i <= graphemes.count - target.count {
                    var matched = true
                    for j in 0..<target.count where graphemes[i + j] != target[j] {
                        matched = false
                        break
                    }
                    if matched { start = i; break }
                    i += 1
                }
            }
            if start == -1 { start = Int(CadenzaMath.clamp(Double(cursor), 0, Double(graphemes.count))) }
            let end = Int(CadenzaMath.clamp(Double(start + target.count), Double(start), Double(graphemes.count)))
            ranges.append(WordRange(wordIndex: wordIndex, word: word, start: start, end: end, timings: buildWordGraphemeTimings(word)))
            cursor = end
        }
        return ranges
    }

        static func wrapSegments(_ segments: [SegmentMeta], maxWidth: CGFloat) -> [[SegmentMeta]] {
        var lines: [[SegmentMeta]] = []
        var current: [SegmentMeta] = []
        var currentWidth: CGFloat = 0
        for segment in segments {
            if !current.isEmpty && currentWidth + segment.width > maxWidth {
                lines.append(current)
                current = []
                currentWidth = 0
            }
            current.append(segment)
            currentWidth += segment.width
        }
        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? [[]] : lines
    }

        static func buildFragments(
        lineViews: [[SegmentMeta]],
        graphemes: [String],
        ranges: [WordRange],
        fontPx: CGFloat
    ) -> [CadenzaPreparedState.LineView] {
                var lineBounds: [(start: Int, end: Int)] = []
        var offset = 0
        for segs in lineViews {
            let count = segs.reduce(0) { $0 + ($1.graphemeEnd - $1.graphemeStart) }
            lineBounds.append((offset, offset + count))
            offset += count
        }

                var glyphWidths: [CGFloat] = []
        for segs in lineViews {
            for seg in segs {
                let n = max(seg.graphemeEnd - seg.graphemeStart, 1)
                let w = seg.width / CGFloat(n)
                for _ in 0..<(seg.graphemeEnd - seg.graphemeStart) { glyphWidths.append(w) }
            }
        }

        var result: [CadenzaPreparedState.LineView] = []
        var fragmentCountByWord: [Int: Int] = [:]
        var allFragments: [(lineIndex: Int, wordIndex: Int, fragment: WordFragment)] = []

        for (lineIndex, segs) in lineViews.enumerated() {
            let (lineStart, lineEnd) = lineBounds[lineIndex]
            let lineWidth = segs.reduce(0) { $0 + $1.width }
            var fragments: [WordFragment] = []
            for range in ranges {
                guard range.end > lineStart || range.start < lineEnd else { continue }
                guard !(range.end <= lineStart || range.start >= lineEnd) else { continue }
                let fs = max(range.start, lineStart)
                let fe = min(range.end, lineEnd)
                guard fe > fs else { continue }
                var startX: CGFloat = 0
                for g in lineStart..<fs { startX += glyphWidths.indices.contains(g) ? glyphWidths[g] : 0 }
                var endX = startX
                for g in fs..<fe { endX += glyphWidths.indices.contains(g) ? glyphWidths[g] : 0 }
                fragments.append(WordFragment(
                    wordIndex: range.wordIndex,
                    word: range.word,
                    text: graphemes[fs..<fe].joined(),
                    startX: startX,
                    endX: endX,
                    fragmentStartInWord: fs - range.start,
                    wordGraphemeCount: max(range.end - range.start, 1),
                    wordTimings: range.timings,
                    fragmentIndexInWord: 0,
                    fragmentCountInWord: 1,
                    isSplitAcrossLines: false
                ))
            }
            for f in fragments {
                fragmentCountByWord[f.wordIndex, default: 0] += 1
            }
            allFragments.append(contentsOf: fragments.enumerated().map { (lineIndex, $0.element.wordIndex, $0.element) })
            result.append(CadenzaPreparedState.LineView(width: lineWidth, fragments: fragments))
        }

                var seenByWord: [Int: Int] = [:]
        for lineIndex in result.indices {
            for fi in result[lineIndex].fragments.indices {
                let wordIndex = result[lineIndex].fragments[fi].wordIndex
                result[lineIndex].fragments[fi].fragmentCountInWord = fragmentCountByWord[wordIndex] ?? 1
                result[lineIndex].fragments[fi].fragmentIndexInWord = seenByWord[wordIndex] ?? 0
                result[lineIndex].fragments[fi].isSplitAcrossLines = (fragmentCountByWord[wordIndex] ?? 1) > 1
                seenByWord[wordIndex] = (seenByWord[wordIndex] ?? 0) + 1
            }
        }
        _ = allFragments
        return result
    }

        static func buildPlacements(
        _ lineData: [CadenzaPreparedState.LineView],
        fontPx: CGFloat,
        lineHeight: CGFloat,
        maxWidth: CGFloat,
        seed: Double,
        isInterlude: Bool
    ) -> [WordPlacement] {
        let totalHeight = Double(max(lineData.count, 1)) * Double(lineHeight)
                let baseMargin: Double = 6
        let baseScale: Double = 1.01

                var emphasisMap: [Int: Double] = [:]
        if !isInterlude {
            let primaryFragments = lineData.flatMap { $0.fragments }.filter { $0.fragmentIndexInWord == 0 }
            let candidates = primaryFragments
                .filter { !$0.isSplitAcrossLines && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { fragment -> (fragment: WordFragment, score: Double) in
                    let graphemeCount = max(fragment.wordGraphemeCount, CadenzaMath.graphemes(fragment.word.text).count, 1)
                    let semanticWeight = CadenzaMath.isCJK(fragment.word.text) ? 0.18 : min(Double(graphemeCount) * 0.08, 0.36)
                    let centerBias = 1 - abs(Double(fragment.wordIndex) - Double(primaryFragments.count - 1) / 2) / Double(max(primaryFragments.count, 1))
                    return (fragment, semanticWeight + centerBias * 0.18)
                }
                .sorted { $0.score > $1.score }
            if let hero = candidates.first {
                let scoreBoost = 1 + CadenzaMath.clamp(hero.score - 0.48, 0, 0.52)
                emphasisMap[hero.fragment.wordIndex] = 1.46 * scoreBoost
            }
        }

                struct Plan {
            var fragment: WordFragment
            var lineIndex: Int
            var baseX: Double
            var baseY: Double
            var emphasis: Double
            var width: CGFloat
            var height: CGFloat
            var scale: Double
            var collisionWidth: CGFloat
            var collisionHeight: CGFloat
            var padding: Double
        }
        var plans: [Plan] = []
        for (lineIndex, lineView) in lineData.enumerated() {
            let lineLeft = -Double(lineView.width) / 2
            let baselineY = -totalHeight / 2 + Double(fontPx) + Double(lineIndex) * Double(lineHeight)
            for fragment in lineView.fragments {
                let emphasis = emphasisMap[fragment.wordIndex] ?? 1
                let width = max(fragment.endX - fragment.startX, fontPx * 0.18)
                let scale = emphasis > 1 ? baseScale * emphasis : baseScale
                let height = Double(fontPx) * scale * 0.95
                plans.append(Plan(
                    fragment: fragment,
                    lineIndex: lineIndex,
                    baseX: lineLeft + Double(fragment.startX),
                    baseY: baselineY,
                    emphasis: emphasis,
                    width: width,
                    height: height,
                    scale: scale,
                    collisionWidth: width * scale * (emphasis > 1 ? 1.48 : 1.26),
                    collisionHeight: height * (emphasis > 1 ? 1.36 : 1.24),
                    padding: baseMargin + (emphasis > 1 ? 10 : 2)
                ))
            }
        }
        plans.sort { a, b in
            let d = b.emphasis - a.emphasis
            if abs(d) > 0.001 { return d > 0 }
            if a.lineIndex != b.lineIndex { return a.lineIndex < b.lineIndex }
            return a.fragment.startX < b.fragment.startX
        }

        var primaryPlanByWord: [Int: Plan] = [:]
        for plan in plans where primaryPlanByWord[plan.fragment.wordIndex] == nil {
            primaryPlanByWord[plan.fragment.wordIndex] = plan
        }
        let heroWordIndex = emphasisMap.sorted { $0.value > $1.value }.first?.key
        let heroPlan = heroWordIndex.flatMap { primaryPlanByWord[$0] }
        let heroMetrics = heroPlan.map { plan in
            (centerX: Double(plan.width * CGFloat(plan.scale)) / 2,
             centerY: -plan.height * 0.46,
             width: Double(plan.width * CGFloat(plan.scale)))
        }

                var occupiedRects: [(left: Double, top: Double, right: Double, bottom: Double)] = []
        var occupiedBands: [Int: [Int]] = [:]
        let collisionBandSize = max(24.0, (Double(lineHeight) * 0.9).rounded())
        func bandIndex(_ v: Double) -> Int { Int(floor(v / collisionBandSize)) }
        func registerRect(_ rect: (left: Double, top: Double, right: Double, bottom: Double)) {
            let idx = occupiedRects.count
            occupiedRects.append(rect)
            for band in bandIndex(rect.top)...bandIndex(rect.bottom) {
                occupiedBands[band, default: []].append(idx)
            }
        }
        func evaluateRect(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> (intersects: Bool, overlapArea: Double) {
            guard !occupiedRects.isEmpty else { return (false, 0) }
            var intersects = false
            var overlapArea = 0.0
            var seen = Set<Int>()
            for band in bandIndex(top)...bandIndex(bottom) {
                guard let bucket = occupiedBands[band] else { continue }
                for rectIndex in bucket where !seen.contains(rectIndex) {
                    seen.insert(rectIndex)
                    let rect = occupiedRects[rectIndex]
                    let ow = max(0, min(right, rect.right) - max(left, rect.left))
                    let oh = max(0, min(bottom, rect.bottom) - max(top, rect.top))
                    if ow <= 0 || oh <= 0 { continue }
                    intersects = true
                    overlapArea += ow * oh
                }
            }
            return (intersects, overlapArea)
        }
        func pushRect(_ left: Double, _ top: Double, _ width: CGFloat, _ height: Double, _ padding: Double) {
            registerRect((
                left: left - padding,
                top: top - height - padding,
                right: left + Double(width) + padding,
                bottom: top + padding
            ))
        }

        var placements: [WordPlacement] = []

        for (planIndex, plan) in plans.enumerated() {
            let fragment = plan.fragment
            let wordSeed = seed + Double(fragment.wordIndex) * 17 + Double(plan.lineIndex) * 31 + Double(planIndex) * 13
            let passedRotate = (CadenzaMath.seededRandom(wordSeed, 3) - 0.5) * 12
            let step = max(10.0, (Double(fontPx) * 0.14).rounded())
            let maxRadius: Double = plan.emphasis > 1
                ? max(20, Double(lineHeight) * 0.5)
                : max(Double(lineHeight) * 2.2, Double(plan.collisionWidth) * 0.75, 56)
            var preferredX = plan.emphasis > 1 ? -Double(plan.width) / 2 : plan.baseX
            var preferredY = plan.emphasis > 1 ? 0 : plan.baseY

                        if !isInterlude && plan.emphasis <= 1, let hero = heroMetrics {
                let wordCenterX = preferredX + Double(plan.width) / 2
                let wordCenterY = preferredY - plan.height * 0.46
                var dx = wordCenterX - hero.centerX
                var dy = wordCenterY - hero.centerY
                let distance = (dx * dx + dy * dy).squareRoot()
                if distance < 1 {
                    dx = preferredX >= 0 ? 1 : -1
                    dy = plan.lineIndex % 2 == 0 ? -0.65 : 0.65
                }
                let minHeroSeparation = hero.width * 0.34 + Double(plan.width) * 0.52 + plan.padding * 2
                if distance < minHeroSeparation {
                    let normalized = max((dx * dx + dy * dy).squareRoot(), 1)
                    let ux = dx / normalized, uy = dy / normalized
                    let push = minHeroSeparation - distance
                    preferredX += ux * push
                    preferredY += uy * push * 0.92
                }
            }

            let horizontalMin = -Double(maxWidth) / 2 - 72
            let horizontalMax = Double(maxWidth) / 2 + 72
            let verticalMin = -max(totalHeight * 0.9, Double(lineHeight) * 1.6)
            let verticalMax = max(totalHeight * 0.9, Double(lineHeight) * 1.45)
            var chosenX = preferredX, chosenY = preferredY
            var found = false
            var bestFallback = (x: preferredX, y: preferredY, score: Double.infinity)
            let baseAngle: Double = heroMetrics != nil && plan.emphasis <= 1
                ? atan2(preferredY, preferredX + Double(plan.width) / 2)
                : 0

            var radius: Double = 0
            while radius <= maxRadius && !found {
                let sampleCount: Int
                if radius == 0 { sampleCount = 1 }
                else if plan.emphasis > 1 { sampleCount = 8 }
                else {
                    let circumference = Double.pi * 2 * radius
                    let dense = max(step * 1.1, 10)
                    sampleCount = max(12, Int((circumference / dense).rounded()))
                }

                for sampleIndex in 0..<sampleCount {
                    let dx: Double, dy: Double
                    if radius == 0 {
                        dx = 0; dy = 0
                    } else {
                        let angle = baseAngle + (Double(sampleIndex) / Double(sampleCount)) * Double.pi * 2
                        let ellipseY = radius * (plan.emphasis > 1 ? 0.8 : 0.92)
                        dx = cos(angle) * radius
                        dy = sin(angle) * ellipseY
                    }
                    let left = preferredX + dx - plan.padding
                    let top = preferredY + dy - plan.collisionHeight - plan.padding
                    let right = left + Double(plan.collisionWidth) + plan.padding * 2
                    let bottom = top + plan.collisionHeight + plan.padding * 2
                    let withinBounds = left >= horizontalMin && right <= horizontalMax
                        && top >= verticalMin && bottom <= verticalMax
                    guard withinBounds else { continue }

                    let collision = evaluateRect(left, top, right, bottom)
                    let travel = (dx * dx + dy * dy).squareRoot()
                    let score = collision.overlapArea * 2.2 + travel
                    if score < bestFallback.score {
                        bestFallback = (preferredX + dx, preferredY + dy, score)
                    }
                    if !collision.intersects {
                        chosenX = preferredX + dx
                        chosenY = preferredY + dy
                        pushRect(chosenX, chosenY, plan.collisionWidth, plan.collisionHeight, plan.padding)
                        found = true
                        break
                    }
                }
                radius += step
            }
            if !found {
                chosenX = bestFallback.x
                chosenY = bestFallback.y
                pushRect(chosenX, chosenY, plan.collisionWidth, plan.collisionHeight, plan.padding)
            }

                        let outwardX = chosenX + Double(plan.width) / 2
            let outwardY = chosenY - plan.height * 0.46
            let outwardLength = max((outwardX * outwardX + outwardY * outwardY).squareRoot(), 1)
            let outwardUnitX = outwardX / outwardLength
            let outwardUnitY = outwardY / outwardLength
            let driftAmount = isInterlude
                ? 3 + CadenzaMath.seededRandom(wordSeed, 6) * 3
                : plan.emphasis > 1
                    ? 4 + CadenzaMath.seededRandom(wordSeed, 6) * 4
                    : 5 + CadenzaMath.seededRandom(wordSeed, 6) * 6
            let passedDriftX = outwardUnitX * driftAmount + (CadenzaMath.seededRandom(wordSeed, 7) - 0.5) * 2.4
            let passedDriftY = outwardUnitY * driftAmount * 0.72 + (CadenzaMath.seededRandom(wordSeed, 8) - 0.5) * 2

            placements.append(WordPlacement(
                id: "\(fragment.word.text)-\(fragment.wordIndex)-\(plan.lineIndex)-\(planIndex)-\(fragment.fragmentIndexInWord)",
                wordIndex: fragment.wordIndex,
                word: fragment.word,
                text: fragment.text,
                glyphs: CadenzaMath.graphemes(fragment.text),
                isCJKText: CadenzaMath.isCJK(fragment.text),
                x: chosenX,
                y: chosenY,
                width: plan.width,
                height: plan.height,
                scale: plan.scale,
                passedRotate: passedRotate,
                passedDriftX: passedDriftX,
                passedDriftY: passedDriftY,
                fragmentStartInWord: fragment.fragmentStartInWord,
                wordGraphemeCount: fragment.wordGraphemeCount,
                wordTimings: fragment.wordTimings,
                isInterlude: isInterlude
            ))
        }
        return placements
    }

        static func buildPreparedState(_ line: LyricLine, viewport: CGSize) -> CadenzaPreparedState {
                let graphemeCount = Double(max(CadenzaMath.graphemes(line.plainText).count, 1))
        let wordCount = Double(max(line.words.count, 1))
        let widthBase = CadenzaMath.clamp(Double(viewport.width) * 0.086, 34, 94)
        let lengthPenalty = graphemeCount > 12 ? min((graphemeCount - 12) * 1.8, 34) : 0
        let densityPenalty = wordCount > 7 ? min((wordCount - 7) * 1.5, 18) : 0
        let baseFontPx = CadenzaMath.clamp(widthBase - lengthPenalty - densityPenalty, 28, 104)
                let fontPx = CGFloat(CadenzaMath.clamp(baseFontPx * 1.12, 24, 132))
        let font = UIFont.systemFont(ofSize: fontPx, weight: .bold)

        let (segments, graphemes) = buildSegments(line.plainText, font: font)
        let lineHeight = (fontPx * (CadenzaMath.isCJK(line.plainText) ? 1.22 : 1.1)).rounded()
        let availableWidth = max(viewport.width - 48, 120)
        let minWidth = min(220, availableWidth)
        let wrapCompression = graphemes.count > 12
            ? CadenzaMath.clamp(0.92 - Double(graphemes.count - 12) * 0.018, 0.62, 0.92)
            : 0.92
                let compactWidthRatio = 0.72 * wrapCompression
        let maxWidth = CGFloat(CadenzaMath.clamp(min(Double(viewport.width) * compactWidthRatio, 820), Double(minWidth), Double(availableWidth)))

        let wrapped = wrapSegments(segments, maxWidth: maxWidth)
        let ranges = findWordRanges(line, graphemes)
        let lineViews = buildFragments(lineViews: wrapped, graphemes: graphemes, ranges: ranges, fontPx: fontPx)
        let isInterlude = line.plainText == "......"
        let placements = buildPlacements(
            lineViews,
            fontPx: fontPx,
            lineHeight: lineHeight,
            maxWidth: maxWidth,
            seed: line.start * 1000,
            isInterlude: isInterlude
        )
        return CadenzaPreparedState(
            fontPx: fontPx,
            lineHeight: lineHeight,
            maxWidth: maxWidth,
            lineCount: lineViews.count,
            placements: placements,
            lineViews: lineViews
        )
    }
}

private final class CadenzaRuntime {
    struct AnimatedState {
        var x: Double
        var y: Double
        var rotation: Double
        var scale: Double
        var bodyAlpha: Double
        var blur: Double
        var activeMix: Double
        var glowAlpha: Double
    }
    var states: [String: AnimatedState] = [:]
    var lastFrameTime: Double?
    var activeLineKey: Double?

    static let shared = CadenzaRuntime()
}

private extension Color {
        func mixed(with other: Color, amount: Double) -> Color {
        let a = UIColor(self); let b = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, al1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, al2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &al1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &al2)
        let t = CGFloat(CadenzaMath.clamp(amount, 0, 1))
        return Color(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t)
    }
    func withAlphaComponent(_ alpha: Double) -> Color {
        opacity(CadenzaMath.clamp(alpha, 0, 1))
    }
}

struct CadenzaLyricsView: View {
    let scheduler: LyricScheduler
    let theme: ThemeColors
    let viewport: CGSize

    init(scheduler: LyricScheduler, theme: ThemeColors, viewport: CGSize) {
        self.scheduler = scheduler
        self.theme = theme
        self.viewport = viewport
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = PlayerCenter.shared.lyricClock
            mainContent(t: t, frameDate: timeline.date)
        }
    }

    @ViewBuilder
    private func mainContent(t: Double, frameDate: Date) -> some View {
        if let lineIndex = scheduler.activeLineIndex(at: t), lineIndex < scheduler.lyrics.lines.count {
            let line = scheduler.lyrics.lines[lineIndex]
            let timing = resolveLineRenderTiming(line)
            let state = CadenzaLayout.buildPreparedStateCached(line, viewport: viewport)
            let framePlacements = buildFramePlacements(t: t, frameDate: frameDate, line: line, timing: timing, state: state)
            let envelope = lineEnvelope(t, line, timing, timingClass: RenderHints.timingClass(rawDuration: max(line.end - line.start, 0)))

            ZStack {
                ForEach(framePlacements) { frame in
                    placementView(frame, fontPx: state.fontPx, primary: theme.primary, accent: theme.accent)
                }
            }
                        .frame(width: viewport.width, height: viewport.height)
            .scaleEffect(envelope.scale, anchor: UnitPoint(x: 0.5, y: 0.42))
            .opacity(envelope.opacity)
            .blur(radius: envelope.blur > 0.05 ? envelope.blur / 2 : 0)
        } else {
                        let fontSize = CGFloat(CadenzaMath.clamp(24, Double(viewport.width) * 0.035, 36))
            Text("等待音乐")
                .font(.system(size: fontSize, weight: .regular))
                .foregroundColor(theme.secondary)
                .opacity(0.5)
                .frame(width: viewport.width, height: viewport.height * 0.7)
        }
    }

        private func buildFramePlacements(t: Double, frameDate: Date, line: LyricLine, timing: LineRenderTiming, state: CadenzaPreparedState) -> [FramePlacement] {
        let width = Double(max(viewport.width, 1))
        let height = Double(max(viewport.height, 1))

        let runtime = CadenzaRuntime.shared
        let frameTime = frameDate.timeIntervalSinceReferenceDate
        let dt = runtime.lastFrameTime == nil
            ? 1.0 / 60
            : CadenzaMath.clamp(frameTime - runtime.lastFrameTime!, 1.0 / 240, 0.05)
        runtime.lastFrameTime = frameTime
        if runtime.activeLineKey != line.start {
            runtime.states.removeAll()
            runtime.activeLineKey = line.start
        }

        let verticalLift = sin(t * 2.3) * 3
        let focusY = height * 0.42 + verticalLift
        let isInstant = timing.wordRevealMode == "instant"

                var framePlacements: [FramePlacement] = []
        var ordered: [(CadenzaWordStatus, WordPlacement)] = []
        for placement in state.placements {
            ordered.append((getWordStatus(t, timing, placement.word), placement))
        }
        let order: [CadenzaWordStatus] = [.waiting, .passed, .active]
        for status in order {
            for entry in ordered where entry.0 == status {
                let placement = entry.1
                let passedAlpha: Double = isInstant ? 0 : 0.82
                let pulse = status == .active && !isInstant
                    ? 1 + sin(t * ACTIVE_PULSE_FREQUENCY + placement.word.start * 5) * 0.04
                    : 1
                let driftP = isInstant ? 0 : passedDrift(t, placement.word)
                let targetScale: Double = status == .waiting
                    ? (isInstant ? placement.scale : max(placement.scale * 0.5, 0.5))
                    : status == .active
                        ? (isInstant ? placement.scale : placement.scale * 1.3 * pulse)
                        : placement.scale
                let targetRotation: Double = status == .waiting
                    ? (isInstant ? 0 : 20)
                    : status == .passed
                        ? (isInstant ? 0 : placement.passedRotate * driftP)
                        : 0
                let targetX = width / 2 + placement.x
                    + (status == .passed ? placement.passedDriftX * driftP : 0)
                let targetY = focusY + placement.y
                    + (status == .passed ? placement.passedDriftY * driftP : 0)
                let targetBodyAlpha = status == .waiting ? 0 : status == .active ? 1 : passedAlpha
                let targetBlur: Double = status == .waiting && !isInstant ? 10 : 0
                let targetActiveMix = bodyMix(t, timing, placement.word)
                let targetGlowAlpha = glowEnvelope(t, timing, placement.word)

                let transformAmount = 1 - exp(-11 * dt)
                let visualAmount = 1 - exp(-14 * dt)
                let glowAmount = 1 - exp(-16 * dt)

                var animated: CadenzaRuntime.AnimatedState
                if let existing = runtime.states[placement.id] {
                    animated = existing
                    animated.x = CadenzaMath.mix(animated.x, targetX, transformAmount)
                    animated.y = CadenzaMath.mix(animated.y, targetY, transformAmount)
                    animated.rotation = CadenzaMath.mix(animated.rotation, targetRotation, transformAmount)
                    animated.scale = CadenzaMath.mix(animated.scale, targetScale, transformAmount)
                    animated.bodyAlpha = CadenzaMath.mix(animated.bodyAlpha, targetBodyAlpha, visualAmount)
                    animated.blur = CadenzaMath.mix(animated.blur, targetBlur, visualAmount)
                    animated.activeMix = CadenzaMath.mix(animated.activeMix, targetActiveMix, visualAmount)
                    animated.glowAlpha = CadenzaMath.mix(animated.glowAlpha, targetGlowAlpha, glowAmount)
                } else {
                    let shouldInitAsActive = isInstant && t >= placement.word.start
                    animated = CadenzaRuntime.AnimatedState(
                        x: targetX,
                        y: targetY,
                        rotation: shouldInitAsActive ? targetRotation : targetRotation + 16,
                        scale: shouldInitAsActive ? targetScale : max(placement.scale * 0.5, 0.5),
                        bodyAlpha: shouldInitAsActive ? targetBodyAlpha : 0,
                        blur: shouldInitAsActive ? targetBlur : 10,
                        activeMix: shouldInitAsActive ? targetActiveMix : 0,
                        glowAlpha: shouldInitAsActive ? targetGlowAlpha : 0
                    )
                }
                runtime.states[placement.id] = animated

                if animated.bodyAlpha < 0.015 && animated.glowAlpha < 0.015 { continue }

                                let shouldSplitGlow = timing.wordRevealMode == "normal" && !placement.isCJKText && placement.glyphs.count > 1
                var glyphGlows: [Double] = []
                if shouldSplitGlow {
                    for (glyphIndex, _) in placement.glyphs.enumerated() {
                        let absoluteIndex = placement.fragmentStartInWord + glyphIndex
                        glyphGlows.append(charGlow(t, placement.word, glyphIndex: absoluteIndex, glyphCount: max(placement.wordGraphemeCount, placement.glyphs.count), placement.wordTimings)
                            * CadenzaMath.clamp(animated.glowAlpha, 0, 1))
                    }
                }
                let wordGlow = glowEnvelope(t, timing, placement.word) * CadenzaMath.clamp(animated.glowAlpha, 0, 1)

                framePlacements.append(FramePlacement(
                    id: placement.id,
                    placement: placement,
                    x: animated.x,
                    y: animated.y,
                    rotation: animated.rotation,
                    scale: animated.scale,
                    bodyAlpha: animated.bodyAlpha,
                    blur: animated.blur,
                    activeMix: animated.activeMix,
                    glyphGlows: glyphGlows,
                    wordGlow: wordGlow
                ))
            }
        }
        return framePlacements
    }

        @ViewBuilder
    private func placementView(_ frame: FramePlacement, fontPx: CGFloat, primary: Color, accent: Color) -> some View {
        let placement = frame.placement
        let textColor = primary.mixed(with: accent, amount: frame.activeMix)
        let font = Font.system(size: fontPx, weight: .bold)

        Group {
            if !frame.glyphGlows.isEmpty {
                                HStack(spacing: 0) {
                    ForEach(Array(placement.glyphs.enumerated()), id: \.offset) { glyphIndex, glyph in
                        let glow = frame.glyphGlows.indices.contains(glyphIndex) ? frame.glyphGlows[glyphIndex] : 0
                        Text(glyph)
                            .font(font)
                            .foregroundColor(textColor)
                            .shadow(color: accent.withAlphaComponent(min(0.98, glow)), radius: 20)
                            .shadow(color: accent.withAlphaComponent(min(0.92, glow * 0.92)), radius: 20)
                            .shadow(color: accent.withAlphaComponent(min(0.35, glow * 0.26)), radius: 20)
                    }
                }
            } else {
                                Text(placement.text)
                    .font(font)
                    .foregroundColor(textColor)
                    .shadow(color: accent.withAlphaComponent(min(0.98, frame.wordGlow)), radius: 20)
                    .shadow(color: accent.withAlphaComponent(min(0.92, frame.wordGlow * 0.92)), radius: 20)
                    .shadow(color: accent.withAlphaComponent(min(0.35, frame.wordGlow * 0.26)), radius: 20)
            }
        }
                .position(
            x: frame.x + placement.width / 2,
            y: frame.y - placement.height * 0.21
        )
        .rotationEffect(.degrees(frame.rotation))
        .scaleEffect(frame.scale)
        .opacity(frame.bodyAlpha)
        .blur(radius: frame.blur > 0.05 ? frame.blur / 2 : 0)
    }
}

private struct FramePlacement: Identifiable {
    var id: String
    var placement: WordPlacement
    var x: Double
    var y: Double
    var rotation: Double
    var scale: Double
    var bodyAlpha: Double
    var blur: Double
    var activeMix: Double
    var glyphGlows: [Double]
    var wordGlow: Double
}

private enum CadenzaStateCache {
    static var cache: [Double: CadenzaPreparedState] = [:]
    static var cacheKeySize: CGSize = .zero

    static func preparedState(for line: LyricLine, viewport: CGSize) -> CadenzaPreparedState {
        if cacheKeySize != viewport { cache.removeAll(); cacheKeySize = viewport }
        if let cached = cache[line.start] { return cached }
        let state = CadenzaLayout.buildPreparedState(line, viewport: viewport)
        if cache.count > 32 { cache.removeAll() }
        cache[line.start] = state
        return state
    }
}

private extension CadenzaLayout {
    static func buildPreparedStateCached(_ line: LyricLine, viewport: CGSize) -> CadenzaPreparedState {
        CadenzaStateCache.preparedState(for: line, viewport: viewport)
    }
}
