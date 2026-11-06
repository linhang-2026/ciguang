import NaturalLanguage
import SwiftUI
import UIKit

struct PartitaLayoutUnit {
    var text: String
    var words: [LyricWord]
    var start: Double
    var end: Double
    var isSemantic: Bool
    var isSticky: Bool = false
}

struct PartitaChunkConfig {
    var x: Double
    var y: Double
    var rotate: Double
    var scale: Double
    var passedRotate: Double
}

struct PartitaWordConfig {
    var x: Double
    var y: Double
    var rotate: Double
    var scale: Double
    var passedRotate: Double
}

struct PartitaChunk {
    var displayWords: [LyricWord]
    var wordConfigs: [PartitaWordConfig]
    var config: PartitaChunkConfig
    var chunkStart: Double
    var chunkEndWord: LyricWord
    var rowIndex: Int
}

struct PartitaLayout {
    var chunks: [PartitaChunk]
    var totalGraphemes: Int
}

enum PartitaLayoutBuilder {

        static let useSemanticLayout = true
    static let showGuideLines = true
    static let staggerMin: Double = 20
    static let staggerMax: Double = 100

        private static let cjkRegex = try! NSRegularExpression(pattern: #"[\x{4E00}-\x{9FA5}\x{3040}-\x{30FF}\x{AC00}-\x{D7AF}]"#)
    private static let apostropheOnlyRegex = try! NSRegularExpression(pattern: #"^['’]\s*$"#)
    private static let contractionSuffixRegex = try! NSRegularExpression(pattern: #"^(s|t|m|d|ll|re|ve|em)\s*$"#, options: .caseInsensitive)
    private static let directContractionRegex = try! NSRegularExpression(pattern: #"^['’](s|t|m|d|ll|re|ve|em)\s*$"#, options: .caseInsensitive)
    private static let trailingApostropheRegex = try! NSRegularExpression(pattern: #"['’]\s*$"#)
    private static let trailingWordCharRegex = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]$"#)
    private static let inlineContractionRegex = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+['’](s|t|m|d|ll|re|ve|em)"#, options: [.caseInsensitive])
    private static let stickyTrailingPunctuationRegex = try! NSRegularExpression(pattern: #"^[,.;:!?，。！？、：；）】》」』〉〕］)}\]"'’”’]+$"#)
    private static let punctuationOnlyRegex = try! NSRegularExpression(pattern: #"^[\s\p{P}\p{S}]+$"#)

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func hasCJK(_ text: String) -> Bool {
        matches(cjkRegex, text)
    }

        private static func splitGraphemes(_ text: String) -> [Character] {
        Array(text)
    }

        private static func trimmedEnd(_ text: String) -> String {
        var sub = Substring(text)
        while let last = sub.last, last.isWhitespace {
            sub = sub.dropLast()
        }
        return String(sub)
    }

    static func build(line: LyricLine, windowHeight: Double) -> PartitaLayout {
        let fullText = line.plainText
        let totalGraphemes = max(
            splitGraphemes(fullText.filter { !$0.isWhitespace }).count,
            line.words.count,
            1
        )
        let layoutUnits = buildLayoutUnits(line: line)

        let baseRowHeight = 100.0
        let availableHeight = windowHeight * 0.65
        let targetRowCount = max(1, Int(floor(availableHeight / baseRowHeight)))
        let actualRowCount = min(layoutUnits.count, targetRowCount)

                var seed = line.start
        func random() -> Double {
            let x = sin(seed) * 10000
            seed += 1
            return x - x.rounded(.down)
        }

                var chunkLengths: [Int] = []
        chunkLengths.reserveCapacity(actualRowCount)
        var remainingUnits = layoutUnits.count
        var remainingChunks = actualRowCount
        for c in 0..<actualRowCount {
            let isLastChunk = c == actualRowCount - 1
            let avg = Double(remainingUnits) / Double(max(remainingChunks, 1))
            var chunkLength = 1
            if isLastChunk {
                chunkLength = remainingUnits
            } else {
                let maxLen = Int(ceil(avg * 1.5))
                let randVal = random()
                chunkLength = max(1, min(maxLen, Int((avg + (randVal - 0.5) * avg).rounded())))
            }
            chunkLength = max(1, min(chunkLength, remainingUnits - (remainingChunks - 1)))
            chunkLengths.append(chunkLength)
            remainingUnits -= chunkLength
            remainingChunks -= 1
        }

                var chunks: [PartitaChunk] = []
        var unitIndex = 0
        for (rowIndex, length) in chunkLengths.enumerated() {
            let chunkUnits = Array(layoutUnits[unitIndex..<unitIndex + length])
            unitIndex += length
            let chunkWords = chunkUnits.flatMap(\.words)
            if chunkWords.isEmpty { continue }
            let displayWords = buildDisplayWords(units: chunkUnits)

            let mergedText = chunkWords.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined()
            let graphemeCount = splitGraphemes(mergedText.filter { !$0.isWhitespace }).count
            let rowBias = Double(rowIndex) - Double(actualRowCount - 1) / 2
            let isStaggeredLeft = rowIndex % 2 == 0

            let staggerMagnitude = staggerMin + random() * max(staggerMax - staggerMin, 0)
            let staggerX = isStaggeredLeft ? -staggerMagnitude : staggerMagnitude
            let staggerScale = 0.8 + random() * 0.9

            let chunkConfig = PartitaChunkConfig(
                x: staggerX,
                y: rowBias * 2.5,
                rotate: 0,
                scale: staggerScale,
                passedRotate: (rowIndex % 2 == 0 ? 1 : -1) * 3
            )

                        var wordConfigs: [PartitaWordConfig] = []
            wordConfigs.reserveCapacity(displayWords.count)
            let wordSeedBase = displayWords[0].start
            for idx in displayWords.indices {
                let wordSeed = wordSeedBase + Double(idx) * 7.13
                func rnd(_ offset: Double) -> Double {
                    let x = sin(wordSeed + offset) * 10000
                    return x - x.rounded(.down)
                }
                wordConfigs.append(PartitaWordConfig(
                    x: (rnd(1) - 0.5) * 12,
                    y: (rnd(2) - 0.5) * 12,
                    rotate: (rnd(3) - 0.5) * 6,
                    scale: chunkConfig.scale,
                    passedRotate: (rnd(8) - 0.5) * 20
                ))
            }

            chunks.append(PartitaChunk(
                displayWords: displayWords,
                wordConfigs: wordConfigs,
                config: chunkConfig,
                chunkStart: chunkWords[0].start,
                chunkEndWord: chunkWords[chunkWords.count - 1],
                rowIndex: rowIndex
            ))
        }

        return PartitaLayout(chunks: chunks, totalGraphemes: totalGraphemes)
    }

    private static func buildLayoutUnits(line: LyricLine) -> [PartitaLayoutUnit] {
        let rawUnits: [PartitaLayoutUnit]
        if useSemanticLayout {
            rawUnits = buildSemanticUnits(line: line)
        } else {
            rawUnits = line.words.map {
                PartitaLayoutUnit(text: $0.text, words: [$0], start: $0.start, end: $0.end, isSemantic: false)
            }
        }
        return applySticky(units: rawUnits)
    }

    private static func buildSemanticUnits(line: LyricLine) -> [PartitaLayoutUnit] {
        let fallback: [PartitaLayoutUnit] = line.words.map {
            PartitaLayoutUnit(text: $0.text, words: [$0], start: $0.start, end: $0.end, isSemantic: false)
        }
                guard hasCJK(line.plainText) else { return fallback }
        let segments = segmentWords(line.plainText)
        guard let mapped = mapSegmentsToWords(segments, line.words) else { return fallback }
        return mapped
    }

        private static func segmentWords(_ text: String) -> [(text: String, isWordLike: Bool)] {
        var result: [(String, Bool)] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let segment = String(text[range])
            result.append((segment, isWordLikeText(segment)))
            return true
        }
        return result
    }

    private static func isWordLikeText(_ text: String) -> Bool {
        !matches(punctuationOnlyRegex, text)
    }

    private static func isWhitespaceOnly(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy(\.isWhitespace)
    }

        private static func mapSegmentsToWords(
        _ segments: [(text: String, isWordLike: Bool)],
        _ words: [LyricWord]
    ) -> [PartitaLayoutUnit]? {
        var units: [PartitaLayoutUnit] = []
        var wordIndex = 0

        for segment in segments {
            let segmentText = segment.text
            if segmentText.isEmpty || isWhitespaceOnly(segmentText) { continue }

            let startWordIndex = wordIndex
            var collectedText = ""

            while wordIndex < words.count && collectedText.utf16.count < segmentText.utf16.count {
                collectedText += words[wordIndex].text
                wordIndex += 1
                if !segmentText.hasPrefix(collectedText) {
                    return nil
                }
            }

            if collectedText != segmentText {
                return nil
            }

            let segmentWords = Array(words[startWordIndex..<wordIndex])
            guard let first = segmentWords.first, let last = segmentWords.last else {
                return nil
            }

                        if !segment.isWordLike && !units.isEmpty {
                units[units.count - 1].text += segmentText
                units[units.count - 1].words.append(contentsOf: segmentWords)
                units[units.count - 1].end = last.end
                continue
            }

            units.append(PartitaLayoutUnit(
                text: segmentText,
                words: segmentWords,
                start: first.start,
                end: last.end,
                isSemantic: segment.isWordLike && hasCJK(segmentText) && segmentWords.count > 1
            ))
        }

        if wordIndex != words.count || units.isEmpty {
            return nil
        }
        return units
    }

    private static func canAttachToPrevious(_ text: String) -> Bool {
        matches(trailingWordCharRegex, trimmedEnd(text))
    }

    private static func endsWithApostrophe(_ text: String) -> Bool {
        matches(trailingApostropheRegex, trimmedEnd(text))
    }

    private static func isApostropheOnlyUnit(_ unit: PartitaLayoutUnit) -> Bool {
        matches(apostropheOnlyRegex, unit.text.trimmingCharacters(in: .whitespaces))
    }

    private static func isContractionSuffixUnit(_ unit: PartitaLayoutUnit) -> Bool {
        matches(contractionSuffixRegex, unit.text.trimmingCharacters(in: .whitespaces))
    }

    private static func isDirectContractionUnit(_ unit: PartitaLayoutUnit) -> Bool {
        matches(directContractionRegex, unit.text.trimmingCharacters(in: .whitespaces))
    }

    private static func isStickyTrailingPunctuationUnit(_ unit: PartitaLayoutUnit) -> Bool {
        matches(stickyTrailingPunctuationRegex, unit.text.trimmingCharacters(in: .whitespaces))
    }

    private static func isStickyTrailingPunctuationWord(_ word: LyricWord) -> Bool {
        matches(stickyTrailingPunctuationRegex, word.text.trimmingCharacters(in: .whitespaces))
    }

    private static func hasAttachedTrailingPunctuation(_ unit: PartitaLayoutUnit) -> Bool {
        guard unit.words.count > 1, let last = unit.words.last else { return false }
        return isStickyTrailingPunctuationWord(last)
    }

    private static func hasInlineContraction(_ unit: PartitaLayoutUnit) -> Bool {
        unit.words.count > 1 && !unit.isSemantic && matches(inlineContractionRegex, unit.text)
    }

    private static func appendUnitToStickyUnit(_ target: inout PartitaLayoutUnit, _ unit: PartitaLayoutUnit) {
        target.text += unit.text
        target.words.append(contentsOf: unit.words)
        target.end = unit.end
        target.isSticky = true
    }

    private static func applySticky(units: [PartitaLayoutUnit]) -> [PartitaLayoutUnit] {
        var merged: [PartitaLayoutUnit] = []
        var index = 0

        while index < units.count {
            let current = units[index]
            guard let previous = merged.last else {
                merged.append(current)
                index += 1
                continue
            }
            let next = index + 1 < units.count ? units[index + 1] : nil

                        if isApostropheOnlyUnit(current), let next,
               canAttachToPrevious(previous.text), isContractionSuffixUnit(next) {
                appendUnitToStickyUnit(&merged[merged.count - 1], current)
                appendUnitToStickyUnit(&merged[merged.count - 1], next)
                index += 2
                continue
            }

            if isDirectContractionUnit(current), canAttachToPrevious(previous.text) {
                appendUnitToStickyUnit(&merged[merged.count - 1], current)
                index += 1
                continue
            }

            if isContractionSuffixUnit(current), endsWithApostrophe(previous.text) {
                appendUnitToStickyUnit(&merged[merged.count - 1], current)
                index += 1
                continue
            }

            if isStickyTrailingPunctuationUnit(current), canAttachToPrevious(previous.text) {
                appendUnitToStickyUnit(&merged[merged.count - 1], current)
                index += 1
                continue
            }

            merged.append(current)
            index += 1
        }

        return merged.map { unit in
            var u = unit
            if hasAttachedTrailingPunctuation(u) || hasInlineContraction(u) {
                u.isSticky = true
            }
            return u
        }
    }

    private static func buildDisplayWords(units: [PartitaLayoutUnit]) -> [LyricWord] {
        units.flatMap { unit -> [LyricWord] in
                        if !unit.isSticky || unit.isSemantic {
                return unit.words
            }
            return [LyricWord(text: unit.text, start: unit.start, end: unit.end)]
        }
    }
}

struct PartitaRenderProfile {
    enum RevealMode { case instant, fast, normal }
    enum TransitionMode { case none, fast, normal }

    let lineRenderEnd: Double
    let transitionMode: TransitionMode
    let revealMode: RevealMode
    let lookahead: Double

    init(line: LyricLine) {
        let rawDuration = max(line.end - line.start, 0)
        let timingClass = RenderHints.timingClass(rawDuration: rawDuration)
        switch timingClass {
        case "micro":
            transitionMode = .none
            revealMode = .instant
            lookahead = 0.03
        case "short":
            transitionMode = .fast
            revealMode = .fast
            lookahead = 0.08
        default:
            transitionMode = .normal
            revealMode = .normal
            lookahead = 0.15
        }
        lineRenderEnd = RenderHints.renderEndTime(line: line)
    }

        func activeEnd(of word: LyricWord) -> Double {
        switch revealMode {
        case .instant:
            return lineRenderEnd
        case .fast:
            return min(lineRenderEnd, max(word.end, word.start + 0.12))
        case .normal:
            return word.end
        }
    }

        func displayDuration(of word: LyricWord) -> Double {
        let minDuration: Double = revealMode == .instant ? 0.08 : revealMode == .fast ? 0.12 : 0.1
        return max(activeEnd(of: word) - word.start, minDuration)
    }
}

struct PartitaLineMotion {
    let enterDuration: Double
    let exitDuration: Double
    let exitEaseInOut: Bool
    let enterOpacity: Double
    let enterScale: Double
    let enterBlur: Double
    let exitScale: Double
    let exitBlur: Double

    init(transitionMode: PartitaRenderProfile.TransitionMode) {
        switch transitionMode {
        case .none:
                        enterDuration = 0
            exitDuration = 0.12
            exitEaseInOut = false
            enterOpacity = 1
            enterScale = 1
            enterBlur = 0
            exitScale = 1.02
            exitBlur = 6
        case .fast:
                        enterDuration = 0.16
            exitDuration = 0.16
            exitEaseInOut = true
            enterOpacity = 0.35
            enterScale = 0.96
            enterBlur = 4
            exitScale = 1.04
            exitBlur = 10
        case .normal:
                        enterDuration = 0.3
            exitDuration = 0.3
            exitEaseInOut = false
            enterOpacity = 0
            enterScale = 0.9
            enterBlur = 10
            exitScale = 1.1
            exitBlur = 20
        }
    }
}

enum PartitaSpring {
        static func value(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        let decay = exp(-10 * t)
        return 1 - decay * (cos(10 * t) + sin(10 * t))
    }
}

private struct PartitaWordView: View {
    let word: LyricWord
    let config: PartitaWordConfig
    let fontSize: CGFloat
    let theme: ThemeColors
    let profile: PartitaRenderProfile
    let t: Double

    private var chars: [Character] { Array(word.text) }
    private var activation: Double { word.start - profile.lookahead }
    private var passedAt: Double { profile.activeEnd(of: word) }
    private var duration: Double { profile.displayDuration(of: word) }

        private var waitX: Double { config.x + sin(config.y) * 100 }
    private var waitY: Double { config.y + cos(config.x) * 50 }
    private var waitRotate: Double { config.rotate + 20 }

    private var pose: (opacity: Double, scale: Double, x: Double, y: Double, rotate: Double) {
        let a = activation
        let p = passedAt
        if t < a {
            return (0, 0.5, waitX, waitY, waitRotate)
        }
        if t <= p {
                        let s = PartitaSpring.value(t - a)
            let op = easeOut(min((t - a) / 0.1, 1))
            let activeScale = config.scale * 1.4
            return (
                op,
                0.5 + (activeScale - 0.5) * s,
                waitX + (config.x - waitX) * s,
                waitY + (config.y - waitY) * s,
                waitRotate + (config.rotate - waitRotate) * s
            )
        }
                        let sExit = PartitaSpring.value(p - a)
        let pExit = easeOut(min((t - p) / 0.5, 1))
        let pRotate = min((t - p) / 5, 1)
        let scaleAtExit = 0.5 + (config.scale * 1.4 - 0.5) * sExit
        let xAtExit = waitX + (config.x - waitX) * sExit
        let yAtExit = waitY + (config.y - waitY) * sExit
        let rotateAtExit = waitRotate + (config.rotate - waitRotate) * sExit
        return (
            1 + (0.82 - 1) * pExit,
            scaleAtExit + (config.scale - scaleAtExit) * pExit,
            xAtExit + (config.x - xAtExit) * pExit,
            yAtExit + (config.y - yAtExit) * pExit,
            rotateAtExit + (config.rotate + config.passedRotate - rotateAtExit) * pRotate
        )
    }

        private var bodyColor: Color {
        let a = activation
        let p = passedAt
        if t < a { return theme.primary }
        if t <= p {
            return mixColor(theme.primary, theme.accent, min((t - a) / duration, 1))
        }
        let colorDur: Double = profile.revealMode == .instant ? 0.12 : profile.revealMode == .fast ? 0.24 : 0.8
        return mixColor(theme.accent, theme.primary, easeInOut(min((t - p) / colorDur, 1)))
    }

        private var bodyBlur: CGFloat {
        let a = activation
        guard t >= a else { return 10 }
        let filterDur: Double = profile.revealMode == .instant ? 0.08 : profile.revealMode == .fast ? 0.12 : 0.2
        return 10 * (1 - CGFloat(min((t - a) / filterDur, 1)))
    }

    private func charGlow(_ index: Int) -> Double {
        let a = activation
        let p = passedAt
        guard t >= a else { return 0 }
        let count = chars.count
        var value: Double = 0

        switch profile.revealMode {
        case .normal:
            if count > 1 {
                                let wordDuration = max(word.end - word.start, 0.001)
                let charDuration = wordDuration / Double(count)
                let delay = charDuration * Double(index)
                let rampDuration = charDuration * 6
                let progress = (t - a - delay) / rampDuration
                if progress > 0 && progress < 1 {
                    value = progress < 0.3
                        ? easeInOut(progress / 0.3)
                        : 1 - easeInOut((progress - 0.3) / 0.7)
                }
            } else {
                                let progress = (t - a) / duration
                if progress > 0 {
                    value = easeInOut(min(progress / 0.9, 1))
                }
            }
        case .fast:
                        let dur = min(max(duration, 0.12), 0.2)
            let progress = (t - a) / dur
            if progress > 0 && progress < 1 {
                value = progress < 0.4
                    ? easeInOut(progress / 0.4)
                    : 1 - easeInOut((progress - 0.4) / 0.6)
            }
        case .instant:
                        let dur = min(duration, 0.12)
            let progress = (t - a) / dur
            if progress > 0 && progress < 1 {
                value = progress < 0.35
                    ? easeOut(progress / 0.35)
                    : 1 - easeOut((progress - 0.35) / 0.65)
            }
        }

        if t > p {
            let fadeDuration: Double = profile.revealMode == .instant ? 0.12 : profile.revealMode == .fast ? 0.22 : 0.9
            value *= 1 - easeOut(min((t - p) / fadeDuration, 1))
        }
        return min(max(value, 0), 1)
    }

        private var glowRadii: (inner: Double, outer: Double) {
        switch profile.revealMode {
        case .normal: return (8, 16)
        case .fast: return (7.2, 12.8)
        case .instant: return (5.6, 9.6)
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
        .rotationEffect(.degrees(pose.rotate))
        .scaleEffect(pose.scale)
        .offset(x: pose.x, y: pose.y)
    }

    @ViewBuilder
    private func charView(_ index: Int) -> some View {
        let glow = charGlow(index)
        let text = Text(String(chars[index])).foregroundStyle(bodyColor)
        if glow > 0.01 {
            let radii = glowRadii
            text
                .shadow(color: theme.accent.opacity(0.7 * glow), radius: radii.inner * glow)
                .shadow(color: theme.accent.opacity(glow), radius: radii.outer * glow)
        } else {
            text
        }
    }
}

private struct PartitaChunkView: View {
    let chunk: PartitaChunk
    let fontSize: CGFloat
    let theme: ThemeColors
    let profile: PartitaRenderProfile
    let t: Double

    private var guideLeft: Bool { chunk.rowIndex % 2 == 0 }
    private var chunkStart: Double { chunk.chunkStart }
    private var chunkEnd: Double { profile.activeEnd(of: chunk.chunkEndWord) }
    private var activation: Double { chunkStart - profile.lookahead }

    private var pose: (opacity: Double, scale: Double, x: Double) {
        if t < activation {
            let from = chunk.config.x + (guideLeft ? -40 : 40)
            return (0, 0.85, from)
        }
        if t <= chunkEnd {
            let s = PartitaSpring.value(t - activation)
            let op = easeOut(min((t - activation) / 0.1, 1))
            let from = chunk.config.x + (guideLeft ? -40 : 40)
            return (op, 0.85 + 0.15 * s, from + (chunk.config.x - from) * s)
        }
        return (1, 1, chunk.config.x)
    }

        private var guideProgress: Double {
        easeOut(min(max((t - activation) / 0.4, 0), 1))
    }

        private var guideColor: Color {
        if t >= activation && t <= chunkEnd { return theme.accent }
        if t > chunkEnd { return .white.opacity(0.22) }
        return .white.opacity(0.14)
    }

    var body: some View {
        let pose = pose
        let progress = guideProgress
        HStack(spacing: 0) {
            ForEach(chunk.displayWords.indices, id: \.self) { index in
                PartitaWordView(
                    word: chunk.displayWords[index],
                    config: chunk.wordConfigs[index],
                    fontSize: fontSize,
                    theme: theme,
                    profile: profile,
                    t: t
                )
                .padding(.trailing, 12.8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.2)
        .overlay {
            if PartitaLayoutBuilder.showGuideLines {
                guideLines(progress: progress)
            }
        }
        .opacity(pose.opacity)
        .rotationEffect(.degrees(chunk.config.rotate))
        .scaleEffect(pose.scale)
        .offset(x: pose.x, y: chunk.config.y)
    }

    @ViewBuilder
    private func guideLines(progress: Double) -> some View {
        let color = guideColor
        let isActive = t >= activation && t <= chunkEnd
        if guideLeft {
            ZStack(alignment: .bottomLeading) {
                                Rectangle()
                    .fill(color)
                    .frame(width: 1, height: 32)
                    .shadow(color: theme.accent.opacity(69.0 / 255.0), radius: isActive ? 10 : 0)
                    .scaleEffect(y: progress, anchor: .bottom)
                    .offset(x: -8, y: 16)
                    .opacity(progress)
                                Rectangle()
                    .fill(color)
                    .frame(height: 1)
                    .shadow(color: theme.accent.opacity(53.0 / 255.0), radius: isActive ? 10 : 0)
                    .padding(.leading, -16)
                    .padding(.trailing, -20)
                    .scaleEffect(x: progress, anchor: .leading)
                    .offset(y: 8)
                    .opacity(progress)
            }
        } else {
            ZStack(alignment: .bottomTrailing) {
                Rectangle()
                    .fill(color)
                    .frame(width: 1, height: 32)
                    .shadow(color: theme.accent.opacity(69.0 / 255.0), radius: isActive ? 10 : 0)
                    .scaleEffect(y: progress, anchor: .bottom)
                    .offset(x: 8, y: 16)
                    .opacity(progress)
                Rectangle()
                    .fill(color)
                    .frame(height: 1)
                    .shadow(color: theme.accent.opacity(53.0 / 255.0), radius: isActive ? 10 : 0)
                    .padding(.trailing, -16)
                    .padding(.leading, -20)
                    .scaleEffect(x: progress, anchor: .trailing)
                    .offset(y: 8)
                    .opacity(progress)
            }
        }
    }
}

struct PartitaLyricsView: View {
    let scheduler: LyricScheduler
    let theme: ThemeColors

    init(scheduler: LyricScheduler, theme: ThemeColors) {
        self.scheduler = scheduler
        self.theme = theme
    }

    @Environment(\.verticalSizeClass) private var verticalSizeClass

        @MainActor private static var layoutCache: [Double: PartitaLayout] = [:]
    @MainActor private static var heightBucket = -1

        private static let preheatMinLead = 0.18
    private static let preheatMaxLead = 1.2

    var body: some View {
        GeometryReader { geo in
            let vw = geo.size.width
            let vh = geo.size.height
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                let t = PlayerCenter.shared.lyricClock
                let now = context.date.timeIntervalSinceReferenceDate
                let lines = scheduler.lyrics.lines
                let activeIndex = activeLineIndex(at: t, lines: lines)
                let active = activeIndex.map { lines[$0] }

                                let _ = Self.preheatUpcoming(activeIndex: activeIndex, lines: lines, t: t, windowHeight: vh)

                let breath = Self.breath(now: now)

                                ZStack {
                    lineStage(activeIndex: activeIndex, active: active, lines: lines, t: t, vw: vw, vh: vh)
                }
                .frame(height: vh * 0.7)
                .padding(32)
                .scaleEffect(breath.scale)
                .offset(y: breath.y)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    subtitleOverlay(activeIndex: activeIndex, t: t, vw: vw)
                }
            }
        }
    }

    private func activeLineIndex(at t: Double, lines: [LyricLine]) -> Int? {
        guard var index = scheduler.activeLineIndex(at: t) else { return nil }
        while index >= 0 {
            if t <= RenderHints.renderEndTime(line: lines[index]) {
                return index
            }
            index -= 1
        }
        return nil
    }

        private func upcomingLine(activeIndex: Int?, lines: [LyricLine], t: Double) -> LyricLine? {
        if let index = activeIndex {
            return index + 1 < lines.count ? lines[index + 1] : nil
        }
        return lines.first { $0.start > t }
    }

        private static func preheatUpcoming(activeIndex: Int?, lines: [LyricLine], t: Double, windowHeight: Double) {
        let upcoming: LyricLine?
        if let index = activeIndex {
            upcoming = index + 1 < lines.count ? lines[index + 1] : nil
        } else {
            upcoming = lines.first { $0.start > t }
        }
        guard let line = upcoming else { return }
        let lead = line.start - t
        if lead >= preheatMinLead && lead <= preheatMaxLead {
            _ = layout(for: line, windowHeight: windowHeight)
        }
    }

    @ViewBuilder
    private func lineStage(activeIndex: Int?, active: LyricLine?, lines: [LyricLine], t: Double, vw: CGFloat, vh: Double) -> some View {
        if let activeLine = active {
            let index = activeIndex ?? 0
            let profile = PartitaRenderProfile(line: activeLine)
            let motion = PartitaLineMotion(transitionMode: profile.transitionMode)

                        if index >= 1 {
                let prev = lines[index - 1]
                let prevRenderEnd = RenderHints.renderEndTime(line: prev)
                let switchAt = min(prevRenderEnd, activeLine.start)
                let prevMotion = PartitaLineMotion(
                    transitionMode: PartitaRenderProfile(line: prev).transitionMode
                )
                let exitProgress = (t - switchAt) / prevMotion.exitDuration
                if t >= switchAt, exitProgress < 1 {
                    let e = prevMotion.exitEaseInOut ? easeInOut(exitProgress) : easeOut(exitProgress)
                    lineContent(
                        line: prev, t: t, vw: vw, vh: vh,
                        poseOpacity: 1 - e,
                        poseScale: 1 + (prevMotion.exitScale - 1) * e,
                        poseBlur: prevMotion.exitBlur * e
                    )
                }
                                if prevRenderEnd < activeLine.start {
                    let emptyExit = (t - activeLine.start) / 0.3
                    if emptyExit < 1 {
                        emptyView(opacity: 1 - easeOut(max(emptyExit, 0)), vw: vw)
                    }
                }
            }

                        let enterProgress: Double = motion.enterDuration > 0
                ? easeOut(min(max((t - activeLine.start) / motion.enterDuration, 0), 1))
                : 1
            lineContent(
                line: activeLine, t: t, vw: vw, vh: vh,
                poseOpacity: motion.enterOpacity + (1 - motion.enterOpacity) * enterProgress,
                poseScale: motion.enterScale + (1 - motion.enterScale) * enterProgress,
                poseBlur: motion.enterBlur * (1 - enterProgress)
            )
        } else if let lastIndex = scheduler.activeLineIndex(at: t) {
                        let prev = lines[lastIndex]
            let prevRenderEnd = RenderHints.renderEndTime(line: prev)
            let prevMotion = PartitaLineMotion(
                transitionMode: PartitaRenderProfile(line: prev).transitionMode
            )
            let exitProgress = (t - prevRenderEnd) / prevMotion.exitDuration
            if exitProgress < 1 {
                let e = prevMotion.exitEaseInOut ? easeInOut(exitProgress) : easeOut(exitProgress)
                lineContent(
                    line: prev, t: t, vw: vw, vh: vh,
                    poseOpacity: 1 - e,
                    poseScale: 1 + (prevMotion.exitScale - 1) * e,
                    poseBlur: prevMotion.exitBlur * e
                )
            }
            emptyView(opacity: easeOut(min(max((t - prevRenderEnd) / 0.3, 0), 1)), vw: vw)
        } else {
                        emptyView(opacity: 1, vw: vw)
        }
    }

    private func lineContent(
        line: LyricLine,
        t: Double,
        vw: CGFloat,
        vh: Double,
        poseOpacity: Double,
        poseScale: Double,
        poseBlur: Double
    ) -> some View {
        let layout = Self.layout(for: line, windowHeight: vh)
        let profile = PartitaRenderProfile(line: line)
        let density: Double = layout.totalGraphemes > 40 ? 0.8 : 1.0
        let fontSize = Self.mainFontSize(width: vw, density: density)

        return VStack(spacing: 9.6) {
            ForEach(layout.chunks.indices, id: \.self) { index in
                PartitaChunkView(
                    chunk: layout.chunks[index],
                    fontSize: fontSize,
                    theme: theme,
                    profile: profile,
                    t: t
                )
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 60.8, minHeight: 384)
        .opacity(poseOpacity)
        .blur(radius: poseBlur)
        .scaleEffect(poseScale)
    }

    private func emptyView(opacity: Double, vw: CGFloat) -> some View {
        Text("等待音乐")
            .font(.system(size: Self.emptyFontSize(width: vw)))
            .foregroundStyle(theme.secondary.opacity(0.5))
            .opacity(opacity)
    }

    @ViewBuilder
    private func subtitleOverlay(activeIndex: Int?, t: Double, vw: CGFloat) -> some View {
        if let index = activeIndex {
            let lines = scheduler.lyrics.lines
            let upcoming = lines[(min(index + 1, lines.count))...]
                .prefix(2)
                .filter { hasReadableText($0.plainText) }
            if !upcoming.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(upcoming.enumerated()), id: \.offset) { _, line in
                        Text(line.plainText)
                            .font(.system(size: Self.upcomingFontSize(width: vw)))
                            .foregroundStyle(theme.secondary)
                            .lineLimit(1)
                            .blur(radius: 1)
                            .frame(maxWidth: 672)
                    }
                }
                .opacity(0.6)
                .padding(.bottom, verticalSizeClass == .compact ? 96 : 150)
                .allowsHitTesting(false)
            }
        }
    }

    @MainActor
    private static func layout(for line: LyricLine, windowHeight: Double) -> PartitaLayout {
        let bucket = Int((windowHeight / 24).rounded())
        if bucket != heightBucket {
            heightBucket = bucket
            layoutCache.removeAll(keepingCapacity: true)
        }
        if let cached = layoutCache[line.start] {
            return cached
        }
        let built = PartitaLayoutBuilder.build(line: line, windowHeight: windowHeight)
        layoutCache[line.start] = built
        if layoutCache.count > 48 {
            layoutCache.removeAll(keepingCapacity: true)
        }
        return built
    }

        static func mainFontSize(width: CGFloat, density: Double) -> CGFloat {
        let d = CGFloat(density)
        return min(max(width * 0.055 * d, 40 * d), 72 * d)
    }

        static func emptyFontSize(width: CGFloat) -> CGFloat {
        min(max(width * 0.028, 19.2), 30.4)
    }

        static func upcomingFontSize(width: CGFloat) -> CGFloat {
        min(max(width * 0.018, 14), 16)
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
