import NaturalLanguage
import SwiftUI
import UIKit

struct TiltLyricsView: View {
    let scheduler: LyricScheduler
    let theme: ThemeColors

        @MainActor private static var layoutCache: [Double: TiltLayout] = [:]

    var body: some View {
        GeometryReader { geo in
            let vw = geo.size.width
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
                let t = PlayerCenter.shared.lyricClock
                let lines = scheduler.lyrics.lines
                let active = scheduler.activeLineIndex(at: t).flatMap { idx in
                    t <= RenderHints.renderEndTime(line: lines[idx]) ? lines[idx] : nil
                }

                ZStack {
                    if let line = active {
                        tiltBlock(line: line, t: t, vw: vw)
                    } else {
                        Text("等待音乐")
                            .font(.system(size: 24))
                            .foregroundStyle(theme.secondary.opacity(0.5))
                    }
                }
            }
        }
    }

    private func tiltBlock(line: LyricLine, t: Double, vw: CGFloat) -> some View {
        let layout = Self.layout(for: line, vw: vw)
        let renderEnd = RenderHints.renderEndTime(line: line)
                var targetIndex = -1
        for (i, seg) in layout.segments.enumerated() where t >= seg.visibleAt {
            targetIndex = i
        }
        let lineOut = t < line.start - 0.1 || t > renderEnd

        return VStack(spacing: vw >= 640 ? 16 : 12) {
            ForEach(layout.segments.indices, id: \.self) { si in
                TiltSegmentView(
                    segment: layout.segments[si],
                    scaleMultiplier: layout.scaleMultiplier,
                    visible: !lineOut && si <= targetIndex,
                    theme: theme,
                    line: line,
                    t: t,
                    vw: vw
                )
            }
        }
    }

    @MainActor
    private static func layout(for line: LyricLine, vw: CGFloat) -> TiltLayout {
        if let cached = layoutCache[line.start] { return cached }
        let built = TiltLayoutBuilder.build(fullText: line.plainText, seed: line.start, vw: vw)
        layoutCache[line.start] = built
        if layoutCache.count > 64 { layoutCache.removeAll(keepingCapacity: true) }
        return built
    }
}

struct TiltSegment {
    var text: String
    var isTilt: Bool
    var isShortLastLine: Bool
        var charOffset: Int
        var visibleAt: Double = 0
}

struct TiltLayout {
    var segments: [TiltSegment]
    var scaleMultiplier: CGFloat
}

enum TiltLayoutBuilder {
        static let splitProbability = 0.75
    static let tiltStyleProbability = 0.35

    static let lineThresholds: [Double] = [0.45, 1.05, 1.7]
    static let resplitThreshold: Double = 1.6
    static let scaleFloorNormal: CGFloat = 0.55
    static let scaleFloorTilt: CGFloat = 0.5
    static let rem: CGFloat = 16

        static func seededRandom(_ seed: Double, _ offset: Double) -> Double {
        let x = sin(seed * 1000 + offset) * 10000
        return x - x.rounded(.down)
    }

    static func determineLineCount(charCount: Int, seed: Double) -> Int {
        let normalized = log(Double(charCount) + 4) / log(20 + 4)
        let jitter = seededRandom(seed, 1) * 0.6 + 0.7
        let score = normalized * jitter * splitProbability
        if score < lineThresholds[0] { return 1 }
        if score < lineThresholds[1] { return 2 }
        if score < lineThresholds[2] { return 3 }
        return 4
    }

        static func measure(_ text: String, px: CGFloat, italic: Bool) -> CGFloat {
        let font = italic
            ? UIFont.italicSystemFont(ofSize: px)
            : UIFont.systemFont(ofSize: px, weight: .regular)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    static func build(fullText: String, seed: Double, vw: CGFloat) -> TiltLayout {
        let measureMaxPx = max(vw * 0.06875, 5.625 * rem)
        let availableWidth = max(320, vw) * 0.85

        let charCount = fullText.trimmingCharacters(in: .whitespaces).count
        let isEllipsisOnly = fullText.trimmingCharacters(in: .whitespaces).allSatisfy {
            " ….·。".contains($0) && !$0.isLetter && !$0.isNumber
        }

        let merged: [String]
        if isEllipsisOnly {
            merged = [fullText]
        } else {
            let numLines = determineLineCount(charCount: charCount, seed: seed)
            merged = SentenceSplit.splitIntoSentences(fullText, targetCount: numLines, timeSeed: seed)
        }

                var candidates: [Int] = []
        for i in merged.indices where seededRandom(seed, 100 + Double(i)) < tiltStyleProbability {
            candidates.append(i)
        }
        var finalTiltIndex = -1
        if !candidates.isEmpty {
            finalTiltIndex = candidates[Int(seededRandom(seed, 200) * Double(candidates.count)) % candidates.count]
        }

        var offsetAccum = 0
        var segments: [TiltSegment] = merged.enumerated().map { i, text in
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            let leading = text.count - text.trimmingCharacters(in: .whitespaces).count
            let seg = TiltSegment(
                text: trimmed,
                isTilt: i == finalTiltIndex,
                isShortLastLine: false,
                charOffset: offsetAccum + leading
            )
            offsetAccum += text.count
            return seg
        }

        func markShortLastLine(_ segs: inout [TiltSegment]) {
            guard segs.count >= 2 else { return }
            let last = segs[segs.count - 1]
            guard !last.isTilt, last.text.count <= 2 else { return }
            let prev = segs[segs.count - 2]
            if last.text.count * 2 <= prev.text.count {
                segs[segs.count - 1].isShortLastLine = true
            }
        }

        func overflowScale(tiltWidth: CGFloat, normalWidth: CGFloat) -> CGFloat {
            let tiltOverflow = tiltWidth > 0 ? tiltWidth / availableWidth : 0
            let normalOverflow = normalWidth > 0 ? normalWidth / availableWidth : 0
            let maxOverflow = max(tiltOverflow, normalOverflow)
            guard maxOverflow > 1 else { return 1 }
            if tiltOverflow >= normalOverflow, tiltWidth > 0 {
                return max(scaleFloorTilt, availableWidth / tiltWidth)
            }
            if normalWidth > 0 {
                return max(scaleFloorNormal, availableWidth / normalWidth)
            }
            return 1
        }

        var scaleMultiplier: CGFloat = 1
        let tiltWidth = segments.filter(\.isTilt).map { measure($0.text, px: measureMaxPx, italic: true) }.max() ?? 0
        let normalWidth = segments.filter { !$0.isTilt }.map { measure($0.text, px: measureMaxPx, italic: false) }.max() ?? 0
        let maxOverflow = max(
            tiltWidth > 0 ? tiltWidth / availableWidth : 0,
            normalWidth > 0 ? normalWidth / availableWidth : 0
        )

        if maxOverflow >= resplitThreshold {
                        let targetWidth = availableWidth * (resplitThreshold - 0.15)
            let totalEst = measure(fullText, px: measureMaxPx, italic: false)
            let extra = min(4, max(segments.count + 1, Int(ceil(totalEst / targetWidth))))
            if extra > segments.count {
                let resplit = SentenceSplit.splitIntoSentences(fullText, targetCount: extra, timeSeed: seed)
                var reOffset = 0
                var newSegments: [TiltSegment] = resplit.enumerated().map { _, text in
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    let leading = text.count - text.trimmingCharacters(in: .whitespaces).count
                    let seg = TiltSegment(text: trimmed, isTilt: false, isShortLastLine: false, charOffset: reOffset + leading)
                    reOffset += text.count
                    return seg
                }
                if !newSegments.isEmpty, seededRandom(seed, 300) < tiltStyleProbability {
                    let picked = Int(seededRandom(seed, 301) * Double(newSegments.count)) % newSegments.count
                    newSegments[picked].isTilt = true
                }
                let postTilt = newSegments.filter(\.isTilt).map { measure($0.text, px: measureMaxPx, italic: true) }.max() ?? 0
                let postNormal = newSegments.filter { !$0.isTilt }.map { measure($0.text, px: measureMaxPx, italic: false) }.max() ?? 0
                markShortLastLine(&newSegments)
                return TiltLayout(segments: newSegments, scaleMultiplier: overflowScale(tiltWidth: postTilt, normalWidth: postNormal))
            }
        }

        if maxOverflow > 1 {
            scaleMultiplier = overflowScale(tiltWidth: tiltWidth, normalWidth: normalWidth)
        }

        markShortLastLine(&segments)
        return TiltLayout(segments: segments, scaleMultiplier: scaleMultiplier)
    }
}

private struct TiltSegmentView: View {
    let segment: TiltSegment
    let scaleMultiplier: CGFloat
    let visible: Bool
    let theme: ThemeColors
    let line: LyricLine
    let t: Double
    let vw: CGFloat

        private func easeOutQuart(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return 1 - pow(1 - c, 2.2)
    }

        private var visibleAt: Double {
        if let range = wordRange() {
            return line.words[range.lowerBound].start - 0.25
        }
        return line.start - 0.25
    }

    private var chars: [Character] { Array(segment.text) }

        private func wordRange() -> Range<Int>? {
        let fullChars = Array(line.plainText)
        let words = line.words
        guard !words.isEmpty else { return nil }
        let segStart = segment.charOffset
        let segEnd = segStart + segment.text.count
        guard segStart >= 0, segStart < fullChars.count || segStart == 0 else { return nil }

        var startIdx: Int? = nil
        var endIdx = words.count - 1
        var pos = 0
        for (wi, word) in words.enumerated() {
            let wChars = Array(word.text)
            let wStart = pos
            let wEnd = pos + wChars.count
            if wStart <= segStart, wEnd > segStart { startIdx = wi }
            if wStart < segEnd, wEnd >= segEnd { endIdx = wi; break }
            pos = wEnd
        }
                guard let s = startIdx else { return nil }
        return s..<max(s, endIdx) + 1
    }

        private func charTimings() -> [(start: Double, end: Double)] {
        let nonSpaceChars = chars.filter { !$0.isWhitespace }
        guard !nonSpaceChars.isEmpty else { return [] }
        var timings: [(Double, Double)] = []

        if let range = wordRange() {
            var ci = 0
            for word in line.words[range] {
                let wordChars = Array(word.text).filter { !$0.isWhitespace }
                guard !wordChars.isEmpty else { continue }
                let dur = max(word.end - word.start, 0.05)
                let charDur = dur / Double(wordChars.count)
                for k in 0..<wordChars.count {
                    guard ci < nonSpaceChars.count else { break }
                    timings.append((word.start + Double(k) * charDur, word.start + Double(k + 1) * charDur))
                    ci += 1
                }
            }
        }

        if timings.count != nonSpaceChars.count {
                        let segStart = wordRange().map { line.words[$0.lowerBound].start } ?? line.start
            let segEnd = wordRange().map { line.words[$0.upperBound].end } ?? RenderHints.renderEndTime(line: line)
            let avg = max(segEnd - segStart, 0.3) / Double(nonSpaceChars.count)
            timings = (0..<nonSpaceChars.count).map { (segStart + Double($0) * avg, segStart + Double($0 + 1) * avg) }
        }
        return timings
    }

        private func pulseIntensity(timing: (start: Double, end: Double)) -> Double {
        let rawDur = max(timing.1 - timing.0, 0.05)
        let duration = min(max(rawDur, 0.2), 0.9)
        let elapsed = t - timing.0
        if elapsed < 0 { return 0 }
        if elapsed <= duration {
            return sin(elapsed / duration * .pi)
        }
        let after = elapsed - duration
        let ramp = duration * 1.2
        if after >= ramp { return 0.25 }
        return 0.25 * (after / ramp)
    }

    var body: some View {
        let baseFontScale = scaleMultiplier
        let boost = segment.isShortLastLine ? 1.18 : 1.0
                let normalPx = min(max(vw * 0.06875, 50), 90) * baseFontScale * boost
        let tiltPx = min(max(vw * 0.06875, 50), 90) * baseFontScale
        let fontPx = segment.isTilt ? tiltPx : normalPx
        let yOffset = tiltPx / 6
        let letterSpacing = fontPx * (segment.isTilt ? 0.15 : 0.08)

        let colors: (normal: Color, tilt: Color) = (theme.primary, theme.accent)
        let color = segment.isTilt ? colors.tilt : colors.normal

                let lineP = easeOutQuart((t - visibleAt) / (segment.isTilt ? 0.6 : 0.55))
        let lineOpacity = visible ? lineP : 0
        let lineY = (segment.isTilt ? 24.0 : 20.0) * (1 - (visible ? lineP : 0))
        let lineScale = segment.isTilt ? (visible ? 0.92 + 0.08 * lineP : 0.92) : 1

        let timings = charTimings()

        HStack(spacing: 0) {
            ForEach(chars.indices, id: \.self) { ci in
                charView(
                    ci: ci, timings: timings,
                    fontPx: fontPx, letterSpacing: letterSpacing,
                    color: color, yOffset: yOffset
                )
            }
        }
        .opacity(lineOpacity)
        .offset(y: lineY)
        .scaleEffect(lineScale)
    }

    @ViewBuilder
    private func charView(
        ci: Int, timings: [(start: Double, end: Double)],
        fontPx: CGFloat, letterSpacing: CGFloat, color: Color, yOffset: CGFloat
    ) -> some View {
        let ch = chars[ci]
        let isSpace = ch.isWhitespace
                let visualIndex = chars[0..<ci].filter { !$0.isWhitespace }.count

                let computed: (charP: Double, intensity: Double) = {
            if isSpace { return (visible ? 1 : 0, 0) }
            if visible, visualIndex < timings.count {
                let delay = Double(visualIndex) * (segment.isTilt ? 0.05 : 0.04)
                let p = easeOutQuart((t - visibleAt - delay) / 0.5)
                return (p, pulseIntensity(timing: timings[visualIndex]))
            }
            return (0, 0)
        }()
        let charP = computed.charP
        let intensity = computed.intensity

                let stagger: CGFloat = visualIndex % 2 == 0 ? -1 : 1
        let charY = segment.isTilt && !isSpace
            ? stagger * yOffset * (2 - CGFloat(charP))
            : 0
        let charScale = 1 + CGFloat(intensity) * (segment.isTilt ? 0.18 : 0.15)

        Text(isSpace ? "\u{00A0}" : String(ch))
            .font(.system(size: fontPx, weight: segment.isTilt ? .light : .regular))
            .italic(segment.isTilt)
            .tracking(isSpace ? 0 : letterSpacing)
            .foregroundStyle(color)
            .opacity(charP)
            .scaleEffect(charScale)
            .offset(y: charY)
            .frame(minWidth: isSpace ? fontPx * (segment.isTilt ? 0.35 : 0.25) : nil)
    }
}

enum SentenceSplit {

    static let cjkRange: [ClosedRange<UInt32>] = [
        0x4E00...0x9FA5, 0x3040...0x30FF, 0xAC00...0xD7AF,
    ]

    static func isCJK(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return false }
        return cjkRange.contains { $0.contains(v) }
    }

    static func hasCJK(_ text: String) -> Bool {
        text.contains { isCJK($0) }
    }

    static func splitIntoSentences(_ text: String, targetCount: Int, timeSeed: Double) -> [String] {
        if targetCount >= 0, targetCount <= 1 {
            return [text]
        }

        var sentences = [text]
        let maxLevel = 5
        for level in 1...maxLevel {
            if sentences.count >= abs(targetCount), targetCount > 0 { break }
            sentences = sentences.flatMap { splitByLevel($0, level: level) }
        }

        if targetCount > 0, sentences.count < targetCount {
            sentences = secondarySplit(sentences, targetCount: targetCount, timeSeed: timeSeed)
        }
        if sentences.count > 1, targetCount > 0, sentences.count > targetCount {
            sentences = mergeSentences(sentences, targetCount: targetCount)
        }
        return sentences
    }

    private static func splitByLevel(_ text: String, level: Int) -> [String] {
        switch level {
        case 1: return splitByPunctuation(text)
        case 2: return splitByBracketsQuotes(text)
        case 3: return splitByWesternWords(text)
        case 4: return splitCJKBySpace(text)
        case 5: return splitBySpecialChars(text)
        default: return [text]
        }
    }

        private static func splitByPunctuation(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(text)
        var i = 0
        let isPunct: (Character) -> Bool = { "，。；！？、…·.,;!?".contains($0) && !$0.isLetter }

        while i < chars.count {
            if isPunct(chars[i]) {
                var j = i
                while j < chars.count, isPunct(chars[j]) { j += 1 }
                var tail = String(chars[i..<j])
                                if j < chars.count, chars[j].isWhitespace {
                    tail.append(chars[j])
                    j += 1
                }
                if !current.isEmpty {
                    result.append(current + tail)
                } else if !result.isEmpty {
                    result[result.count - 1] += tail
                } else {
                    result.append(tail)
                }
                current = ""
                i = j
            } else {
                current.append(chars[i])
                i += 1
            }
        }
        if !current.isEmpty { result.append(current) }
        return result.filter { !$0.isEmpty }
    }

        private static let pairedSymbols: [(open: Character, close: Character)] = [
        ("「", "」"), ("『", "』"), ("《", "》"), ("【", "】"), ("｛", "｝"),
        ("［", "］"), ("[", "]"), ("（", "）"), ("(", ")"), ("\"", "\""), ("'", "'"),
    ]

    private static func splitByBracketsQuotes(_ text: String) -> [String] {
        let result = extractOutermostPairs(Array(text))
        return result.count > 1 ? result : [text]
    }

    private static func extractOutermostPairs(_ chars: [Character]) -> [String] {
        guard let best = findOutermostPair(chars) else { return [String(chars)].filter { !$0.isEmpty } }
        var result: [String] = []
        let before = String(chars[0..<best.openStart])
        let paired = String(chars[best.openStart..<best.closeEnd])
        let remainder = String(chars[best.closeEnd...])
        if !before.isEmpty { result.append(contentsOf: extractOutermostPairs(Array(before))) }
        result.append(paired)
        if !remainder.isEmpty { result.append(contentsOf: extractOutermostPairs(Array(remainder))) }
        return result.filter { !$0.isEmpty }
    }

    private static func findOutermostPair(_ chars: [Character]) -> (openStart: Int, closeEnd: Int)? {
        var best: (openStart: Int, closeEnd: Int)? = nil
        for pair in pairedSymbols {
            guard let openIdx = chars.firstIndex(of: pair.open) else { continue }
            var closeIdx: Int? = nil
            var i = openIdx + 1
            while i < chars.count {
                if chars[i] == pair.close { closeIdx = i; break }
                i += 1
            }
            guard let ci = closeIdx else { continue }
            if best == nil || openIdx < best!.openStart {
                best = (openStart: openIdx, closeEnd: ci + 1)
            } else if openIdx == best!.openStart, ci + 1 > best!.closeEnd {
                best = (openStart: openIdx, closeEnd: ci + 1)
            }
        }
        return best
    }

        private static func splitByWesternWords(_ text: String) -> [String] {
        guard hasCJK(text) else { return [text] }
                let pattern = "[A-Za-z0-9]+(?:[A-Za-z0-9'\\-]*[A-Za-z0-9]+)?(?:\\s+[A-Za-z0-9]+(?:[A-Za-z0-9'\\-]*[A-Za-z0-9]+)?)+[.,;:!?。，；：！？]?\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [text] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))

        var hasMultiWord = false
        for m in matches {
            let block = ns.substring(with: m.range)
            let wordCount = block.split(whereSeparator: { $0.isWhitespace }).count
            if wordCount > 1 { hasMultiWord = true; break }
        }
        guard hasMultiWord else { return [text] }

        var parts: [String] = []
        var lastIndex = 0
        for m in matches {
            let blockStart = m.range.location
            let blockEnd = m.range.location + m.range.length
            let before = ns.substring(with: NSRange(location: lastIndex, length: blockStart - lastIndex))
                        let skipBoundary: Bool
            if let sep = before.last {
                if sep == "-" {
                    skipBoundary = true
                } else if ":：/／|｜".contains(sep) {
                    let count = text.filter { String($0) == String(sep) }.count
                    skipBoundary = count >= 2
                } else {
                    skipBoundary = false
                }
            } else {
                skipBoundary = false
            }
            if skipBoundary {
                parts.append(before + ns.substring(with: m.range))
            } else if blockStart > lastIndex {
                parts.append(before)
                parts.append(ns.substring(with: m.range))
            } else {
                parts.append(ns.substring(with: m.range))
            }
            lastIndex = blockEnd
        }
        if lastIndex < ns.length {
            parts.append(ns.substring(from: lastIndex))
        }
        return parts.count > 1 ? parts : [text]
    }

        private static func splitCJKBySpace(_ text: String) -> [String] {
        guard hasCJK(text) else { return [text] }
        var segments: [String] = []
        var current = ""
        var inCjkBlock = false

        for ch in text {
            if isCJK(ch) {
                current.append(ch)
                inCjkBlock = true
            } else if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if ch.isWhitespace {
                if ch == "\u{3000}", !current.isEmpty {
                    current.append(ch)
                    segments.append(current)
                    current = ""
                    inCjkBlock = false
                } else if inCjkBlock, !current.isEmpty, let last = current.last, isCJK(last) {
                    current.append(ch)
                    segments.append(current)
                    current = ""
                    inCjkBlock = false
                } else if current.isEmpty, !segments.isEmpty {
                    segments[segments.count - 1].append(ch)
                } else {
                    current.append(ch)
                }
            } else {
                if current.isEmpty, !segments.isEmpty {
                    segments[segments.count - 1].append(ch)
                } else {
                    current.append(ch)
                }
            }
        }
        if !current.isEmpty {
            if !segments.isEmpty, current.allSatisfy({ $0.isWhitespace }) {
                segments[segments.count - 1] += current
            } else {
                segments.append(current)
            }
        }
        return segments.count > 1 ? segments : [text]
    }

        private static func splitBySpecialChars(_ text: String) -> [String] {
        let specials: Set<Character> = [":", "：", "/", "／", "\\", "|", "｜", "~", "～"]
        let parts = text.split(omittingEmptySubsequences: true) { specials.contains($0) }.map(String.init)
        guard parts.count > 1 else { return [text] }

        var result: [String] = []
        var searchStart = text.startIndex
        for part in parts {
            guard let range = text.range(of: part, range: searchStart..<text.endIndex) else { continue }
            if range.lowerBound > searchStart {
                let sep = String(text[searchStart..<range.lowerBound])
                if !result.isEmpty {
                    result[result.count - 1] += sep
                } else {
                    result.append(sep)
                }
            }
            result.append(part)
            searchStart = range.upperBound
        }
        if searchStart < text.endIndex {
            let tail = String(text[searchStart...])
            if !result.isEmpty {
                result[result.count - 1] += tail
            } else {
                result.append(tail)
            }
        }
        return result.filter { !$0.isEmpty }
    }

        private static func secondarySplit(_ sentences: [String], targetCount: Int, timeSeed: Double) -> [String] {
        var sentences = sentences
        while sentences.count < targetCount {
            let candidates = sentences.enumerated().filter { $0.element.count > 2 }
            if candidates.isEmpty { break }

            var bestSplit: (index: Int, pos: String.Index)? = nil
            var bestScore: Double = -1
            for (idx, s) in candidates {
                if let mid = wordBoundaryNearMiddle(s) {
                    let textChars = Array(s)
                    let splitPos = mid
                    let balance = 1 - abs(Double(splitPos) - Double(textChars.count / 2)) / Double(max(textChars.count / 2, 1))
                    let score = balance * 10 + Double(wordCount(s))
                    if score > bestScore {
                        bestScore = score
                        bestSplit = (idx, s.index(s.startIndex, offsetBy: mid))
                    }
                }
            }

            if let split = bestSplit {
                let s = sentences[split.index]
                sentences.remove(at: split.index)
                let first = String(s[s.startIndex..<split.pos])
                let second = String(s[split.pos...])
                sentences.insert(first, at: split.index)
                sentences.insert(second, at: split.index + 1)
                continue
            }

                        func pseudoRandom(_ seed: Double) -> Double {
                let x = sin(seed) * 10000
                return x - x.rounded(.down)
            }
            let textHash = sentences.reduce(0) { acc, s in
                acc + s.unicodeScalars.reduce(0) { $0 + Int($1.value) }
            }
            let seed = Double(textHash) + Double(sentences.count) + timeSeed
            let pick = candidates.isEmpty ? 0 : Int(pseudoRandom(seed) * Double(candidates.count)) % candidates.count
            let (selIdx, sel) = candidates[pick]
            let chars = Array(sel)
            let mid = chars.count / 2
            let first = String(chars[0..<mid])
            let second = String(chars[mid...])
            sentences.remove(at: selIdx)
            sentences.insert(first, at: selIdx)
            sentences.insert(second, at: selIdx + 1)
        }
        return sentences
    }

        private static func wordBoundaryNearMiddle(_ text: String) -> Int? {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var boundaries: [Int] = []
        var offset = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let length = text.distance(from: range.lowerBound, to: range.upperBound)
            boundaries.append(offset)
            offset += length
            return true
        }
        guard boundaries.count >= 2 else { return nil }
        let mid = text.count / 2
        return boundaries.dropFirst().min(by: {
            abs($0 - mid) < abs($1 - mid)
        })
    }

    private static func wordCount(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

        private static func mergeSentences(_ sentences: [String], targetCount: Int) -> [String] {
        var sentences = sentences
        while sentences.count > targetCount {
            var bestMerge = 0
            var shortest = Int.max
            for i in 0..<(sentences.count - 1) {
                let combined = sentences[i].count + sentences[i + 1].count
                if combined < shortest {
                    shortest = combined
                    bestMerge = i
                }
            }
            let merged = sentences[bestMerge] + sentences[bestMerge + 1]
            sentences.replaceSubrange(bestMerge...bestMerge + 1, with: [merged])
        }
        return sentences
    }
}
