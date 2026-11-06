import CoreText
import SwiftUI
import UIKit

enum CappellaConstants {
    static let shortLineCharLimit = 12
    static let maxVisibleMessages = 20
    static let avatarGridSize = 3
    static let leftAvatarIndices = [0, 3, 6, 1, 4]
    static let rightAvatarIndex = 8
    static let layoutCacheLimit = 32
    static let widthLookaheadSeconds: Double = 0.2
    static let bubbleFontWeight = 400
    static let interludeText = "......"
    static let defaultCharFadeMs: Double = 220
    static let minCharFadeMs: Double = 40
}

struct CappellaMotion {
        let forceRightEveryLines = 5
    let shortLineCarryChance: Double = 0.68
        let sideSequence: [Bool] = [false, true, false, true, true]
    let sideFlipChance: Double = 0.18
    let randomEmoChance: Double = 0.1
    let minLinesBetweenRandomEmos = 3
    let maxRandomEmoRatio: Double = 1.0 / 8.0
        let rowEnterY: Double = 22
    let rowEnterScale: Double = 0.98
    let rowEnterDuration: Double = 0.32
    let rowExitY: Double = -18
    let rowExitScale: Double = 0.965
    let rowExitDuration: Double = 0.24
    let springStiffness: Double = 340
    let springDamping: Double = 28
    let springMass: Double = 0.72
    let activeScale: Double = 1.12
    let passedScale: Double = 0.92
    let passedOpacity: Double = 0.82
    let activeFontMultiplier: Double = 1.34
    let inactiveFontMultiplier: Double = 0.94
    let activePaddingX: Double = 20
    let activePaddingY: Double = 16
    let inactivePaddingX: Double = 16
    let inactivePaddingY: Double = 12
    let activeMinHeight: Double = 64
    let inactiveMinHeight: Double = 44
    let glowOpacity: Double = 0.4
    let glowDuration: Double = 1.8
    let glowRightAlpha: Double = 0.34
    let glowLeftAlpha: Double = 0.18
    let activeShadowAlpha: Double = 0.34
    let emoActiveSize: Double = 160
    let emoInactiveSize: Double = 110
    let emoEnterScale: Double = 0.6
    let emoSizeTransitionDuration: Double = 0.25

    static let standard = CappellaMotion()
}

enum CappellaEmoji {
    static let emoPool: [String] = ["😄", "😍", "🙂", "😴", "🥱", "😪", "🎧", "✨", "🎶"]
    static let leftAvatarPool: [String] = [
        "🐣", "🦊", "🐼", "🐧", "🐳", "🦉", "🐝", "🦁",
        "🐿️", "🐨", "🦔", "🐙", "🦜", "🐢", "🦋", "🐹",
    ]
}

struct CappellaMessage: Identifiable {
    enum Kind { case title, lyric, emo }

    let id: String
    let kind: Kind
        let sideRight: Bool
    let avatarIndex: Int
        var text: String = ""
        var line: LyricLine?
    var lineIndex: Int = 0
        var emoji: String?
    var activationStart: Double = 0
    var activationEnd: Double = 0
}

enum CappellaSeed {
    static func fnv1a(_ input: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for unit in input.utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 16777619
        }
        return hash
    }

        static func jsNum(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return value.description
    }

    static func seedUnit(_ parts: [String]) -> Double {
        Double(fnv1a(parts.joined(separator: "|"))) / 4294967295.0
    }
}

enum CappellaMessages {

        static func pickStableEmo(_ pool: [String], _ seedParts: [String]) -> String? {
        guard !pool.isEmpty else { return nil }
        let index = Int(CappellaSeed.seedUnit(seedParts) * Double(pool.count)) % pool.count
        return pool[index < 0 ? 0 : index]
    }

        static func countCompactChars(_ text: String) -> Int {
        text.filter { !$0.isWhitespace }.count
    }

    static func build(lines: [LyricLine], titleText: String, motion: CappellaMotion) -> [CappellaMessage] {
        let emoPool = CappellaEmoji.emoPool
        let showEmoMessages = !emoPool.isEmpty

        var messages: [CappellaMessage] = [
            CappellaMessage(
                id: "title",
                kind: .title,
                sideRight: true,
                avatarIndex: CappellaConstants.avatarGridSize * CappellaConstants.avatarGridSize - 1,
                text: titleText
            )
        ]

        guard !lines.isEmpty else {
                        if showEmoMessages,
               let fallback = pickStableEmo(emoPool, ["no-lyrics", titleText, CappellaSeed.jsNum(Double(motion.forceRightEveryLines))]) {
                messages.append(
                    CappellaMessage(
                        id: "emo-no-lyrics",
                        kind: .emo,
                        sideRight: true,
                        avatarIndex: CappellaConstants.rightAvatarIndex,
                        lineIndex: 0,
                        emoji: fallback,
                        activationStart: 0,
                        activationEnd: 999_999
                    )
                )
            }
            return messages
        }

        var sideSequenceCursor = 0
        var nextLeftAvatarCursor = 0
        var lastLyricSender: (sideRight: Bool, avatarIndex: Int)?
        var lyricMessagesSinceRandomEmo = Double.infinity
        var randomEmoCount = 0
        let randomEmoCap = Int(floor(Double(lines.count) * motion.maxRandomEmoRatio))

        for (lineIndex, line) in lines.enumerated() {
            let nextLine = lineIndex + 1 < lines.count ? lines[lineIndex + 1] : nil
            let fullText = line.plainText
            let isShortLine = countCompactChars(fullText) <= CappellaConstants.shortLineCharLimit
            let shouldForceRight = (lineIndex + 1) % motion.forceRightEveryLines == 0
            let shouldCarrySender = !shouldForceRight
                && isShortLine
                && lastLyricSender != nil
                && CappellaSeed.seedUnit(["carry", CappellaSeed.jsNum(line.start), CappellaSeed.jsNum(Double(lineIndex))]) <= motion.shortLineCarryChance
            let baseSide = motion.sideSequence[sideSequenceCursor % motion.sideSequence.count]
            let shouldFlipSide = !shouldForceRight
                && CappellaSeed.seedUnit(["flip", CappellaSeed.jsNum(line.start), CappellaSeed.jsNum(Double(lineIndex))]) < motion.sideFlipChance
            let resolvedSide = shouldFlipSide ? !baseSide : baseSide

            let sender: (sideRight: Bool, avatarIndex: Int)
            if shouldForceRight {
                sender = (true, CappellaConstants.rightAvatarIndex)
            } else if shouldCarrySender, let carried = lastLyricSender {
                sender = carried
            } else {
                sender = (resolvedSide, resolvedSide ? CappellaConstants.rightAvatarIndex : nextLeftAvatarCursor)
            }

            let isInterlude = fullText == CappellaConstants.interludeText
            let effectiveRenderEndTime = min(
                RenderHints.renderEndTime(line: line),
                nextLine?.start ?? Double.infinity
            )

            if isInterlude, showEmoMessages,
               let emoImage = pickStableEmo(emoPool, ["interlude", CappellaSeed.jsNum(line.start), CappellaSeed.jsNum(Double(lineIndex))]) {
                messages.append(
                    CappellaMessage(
                        id: "emo-\(CappellaSeed.jsNum(line.start))-\(lineIndex)",
                        kind: .emo,
                        sideRight: sender.sideRight,
                        avatarIndex: sender.avatarIndex,
                        line: line,
                        lineIndex: lineIndex,
                        emoji: emoImage,
                        activationStart: line.start,
                        activationEnd: max(line.start + 0.12, effectiveRenderEndTime)
                    )
                )
            } else {
                messages.append(
                    CappellaMessage(
                        id: "line-\(CappellaSeed.jsNum(line.start))-\(lineIndex)",
                        kind: .lyric,
                        sideRight: sender.sideRight,
                        avatarIndex: sender.avatarIndex,
                        line: line,
                        lineIndex: lineIndex
                    )
                )
            }
            lyricMessagesSinceRandomEmo += 1

            let rawDuration = max(line.end - line.start, 0)
            let canAppendRandomEmo = !isInterlude
                && showEmoMessages
                && motion.randomEmoChance > 0
                && randomEmoCount < randomEmoCap
                && lyricMessagesSinceRandomEmo >= Double(motion.minLinesBetweenRandomEmos)
                && RenderHints.timingClass(rawDuration: rawDuration) == "normal"

            if canAppendRandomEmo {
                let score = CappellaSeed.seedUnit([
                    "random-emo",
                    CappellaSeed.jsNum(line.start),
                    CappellaSeed.jsNum(line.end),
                    CappellaSeed.jsNum(Double(lineIndex)),
                    CappellaSeed.jsNum(motion.randomEmoChance),
                ])
                if score < motion.randomEmoChance,
                   let reaction = pickStableEmo(emoPool, [
                       "reaction",
                       CappellaSeed.jsNum(line.start),
                       CappellaSeed.jsNum(line.end),
                       CappellaSeed.jsNum(Double(lineIndex)),
                       sender.sideRight ? "right" : "left",
                   ]) {
                    messages.append(
                        CappellaMessage(
                            id: "emo-reaction-\(CappellaSeed.jsNum(line.start))-\(lineIndex)",
                            kind: .emo,
                            sideRight: sender.sideRight,
                            avatarIndex: sender.avatarIndex,
                            line: line,
                            lineIndex: lineIndex,
                            emoji: reaction,
                            activationStart: line.end,
                            activationEnd: max(line.end + 0.08, effectiveRenderEndTime)
                        )
                    )
                    randomEmoCount += 1
                    lyricMessagesSinceRandomEmo = 0
                }
            }

                        if shouldForceRight {
                sideSequenceCursor = 0
                lastLyricSender = nil
            } else if !shouldCarrySender {
                if !sender.sideRight {
                    nextLeftAvatarCursor += 1
                }
                sideSequenceCursor += 1
                lastLyricSender = sender
            } else {
                lastLyricSender = sender
            }
        }

        return messages
    }
}

struct CappellaRevealPlan {
    let characters: [Character]
        let revealTimes: [Double]
        let fadeDurationsMs: [Double]
        let timestampReadyTime: Double
}

enum CappellaReveal {

        static func characterCountAtTime(_ times: [Double], _ currentTime: Double) -> Int {
        var low = 0
        var high = times.count
        while low < high {
            let mid = (low + high) / 2
            if times[mid] <= currentTime {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

            static func buildPlan(line: LyricLine) -> CappellaRevealPlan {
        let characters = Array(line.plainText)
        guard !characters.isEmpty else {
            return CappellaRevealPlan(characters: [], revealTimes: [], fadeDurationsMs: [], timestampReadyTime: line.end)
        }

        var revealTimes = [Double](repeating: .infinity, count: characters.count)
        var fadeDurationsMs = [Double](repeating: CappellaConstants.defaultCharFadeMs, count: characters.count)
        let words = line.words

        if words.isEmpty {
                        let unit = max(line.end - line.start, 0) / Double(characters.count)
            for index in characters.indices {
                let start = line.start + unit * Double(index)
                let end = index == characters.count - 1 ? line.end : line.start + unit * Double(index + 1)
                revealTimes[index] = start
                fadeDurationsMs[index] = max((end - start) * 1000, CappellaConstants.minCharFadeMs)
            }
        } else {
            var cursor = 0
            var lastResolvedTime = line.start

            for word in words {
                let wordGraphemes = Array(word.text)
                guard !wordGraphemes.isEmpty else { continue }

                                var matchedStart = -1
                if cursor <= characters.count - wordGraphemes.count {
                    search: for index in cursor...(characters.count - wordGraphemes.count) {
                        for offset in wordGraphemes.indices where characters[index + offset] != wordGraphemes[offset] {
                            continue search
                        }
                        matchedStart = index
                        break
                    }
                }
                let start = matchedStart >= 0 ? matchedStart : cursor
                let end = min(start + wordGraphemes.count, characters.count)

                                for gapIndex in cursor..<start where gapIndex < revealTimes.count {
                    revealTimes[gapIndex] = word.start
                    fadeDurationsMs[gapIndex] = CappellaConstants.minCharFadeMs
                }

                                let unit = max(word.end - word.start, 0) / Double(wordGraphemes.count)
                for localIndex in 0..<(end - start) {
                    let timingStart = word.start + unit * Double(localIndex)
                    let timingEnd = localIndex == wordGraphemes.count - 1 ? word.end : word.start + unit * Double(localIndex + 1)
                    revealTimes[start + localIndex] = timingStart
                    fadeDurationsMs[start + localIndex] = max((timingEnd - timingStart) * 1000, CappellaConstants.minCharFadeMs)
                    lastResolvedTime = max(lastResolvedTime, timingEnd)
                }
                cursor = max(cursor, end)
            }

                        for index in cursor..<revealTimes.count where revealTimes[index].isInfinite {
                revealTimes[index] = lastResolvedTime
                fadeDurationsMs[index] = CappellaConstants.minCharFadeMs
            }
        }

                var readyTime = line.start
        for index in revealTimes.indices where revealTimes[index].isFinite {
            readyTime = max(readyTime, revealTimes[index] + (fadeDurationsMs[index] / 1000))
        }

        return CappellaRevealPlan(
            characters: characters,
            revealTimes: revealTimes,
            fadeDurationsMs: fadeDurationsMs,
            timestampReadyTime: readyTime
        )
    }
}

enum CappellaTextMeasure {

    @MainActor private static var cache: [String: CGSize] = [:]
    private static let cacheLimit = 256

    @MainActor
    static func measure(
        text: String,
        fontSize: CGFloat,
        lineHeightPx: CGFloat,
        maxTextWidth: CGFloat,
        paddingX: CGFloat,
        paddingY: CGFloat
    ) -> CGSize {
        let key = "\(text.hashValue)|\(Int(fontSize * 100))|\(Int(lineHeightPx * 100))|\(Int(maxTextWidth))|\(Int(paddingX))|\(Int(paddingY))"
        if let cached = cache[key] {
            return cached
        }

        let safeText = text.isEmpty ? " " : text
        let font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        let attributed = NSAttributedString(string: safeText, attributes: [.font: font])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: max(1, maxTextWidth), height: 1_000_000), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let ctLines = (CTFrameGetLines(frame) as NSArray) as? [CTLine] ?? []
        let lineCount = max(ctLines.count, 1)

        var textWidth: Double = 0
        for ctLine in ctLines {
            textWidth = max(textWidth, CTLineGetTypographicBounds(ctLine, nil, nil, nil))
        }
        textWidth = max(textWidth, Double(fontSize))

        let size = CGSize(
            width: ceil(min(textWidth, Double(maxTextWidth)) + Double(paddingX) * 2 + 2),
            height: ceil(Double(lineCount) * Double(lineHeightPx) + Double(paddingY) * 2 + 2)
        )

        if cache[key] == nil && cache.count >= cacheLimit {
            cache.removeAll(keepingCapacity: true)
        }
        cache[key] = size
        return size
    }
}

struct CappellaPreparedMetrics {
    let characters: [Character]
        let sizes: [CGSize]
    let revealTimes: [Double]
        let bubbleTargetTimes: [Double]
    let fadeDurationsMs: [Double]
    let timestampReadyTime: Double
}

enum CappellaBubbleMetrics {

    @MainActor private static var cache: [String: CappellaPreparedMetrics] = [:]

    @MainActor
    static func metrics(
        for line: LyricLine,
        fontSize: CGFloat,
        lineHeightPx: CGFloat,
        maxTextWidth: CGFloat,
        paddingX: CGFloat,
        paddingY: CGFloat
    ) -> CappellaPreparedMetrics {
        let key = [
            CappellaSeed.jsNum(line.start),
            CappellaSeed.jsNum(line.end),
            "\(line.words.count)",
            "\(line.plainText.hashValue)",
            "\(Int(fontSize * 1000))",
            "\(Int(lineHeightPx * 1000))",
            "\(Int(maxTextWidth))",
            "\(Int(paddingX))",
            "\(Int(paddingY))",
        ].joined(separator: "|")
        if let cached = cache[key] {
            return cached
        }

        let plan = CappellaReveal.buildPlan(line: line)
        let bubbleTargetTimes = plan.revealTimes.map { $0 - CappellaConstants.widthLookaheadSeconds }

        var sizes: [CGSize] = []
        sizes.reserveCapacity(plan.characters.count + 1)
        var prefix = ""
                sizes.append(
            CappellaTextMeasure.measure(
                text: prefix, fontSize: fontSize, lineHeightPx: lineHeightPx,
                maxTextWidth: maxTextWidth, paddingX: paddingX, paddingY: paddingY
            )
        )
        for character in plan.characters {
            prefix.append(character)
            sizes.append(
                CappellaTextMeasure.measure(
                    text: prefix, fontSize: fontSize, lineHeightPx: lineHeightPx,
                    maxTextWidth: maxTextWidth, paddingX: paddingX, paddingY: paddingY
                )
            )
        }

        let prepared = CappellaPreparedMetrics(
            characters: plan.characters,
            sizes: sizes,
            revealTimes: plan.revealTimes,
            bubbleTargetTimes: bubbleTargetTimes,
            fadeDurationsMs: plan.fadeDurationsMs,
            timestampReadyTime: plan.timestampReadyTime
        )

        if cache[key] == nil && cache.count >= CappellaConstants.layoutCacheLimit {
            cache.removeAll(keepingCapacity: true)
        }
        cache[key] = prepared
        return prepared
    }
}

enum CappellaLayout {

        static func visibleLineIndex(at t: Double, lines: [LyricLine]) -> Int {
        var index = -1
        for (i, line) in lines.enumerated() where line.start <= t {
            index = i
        }
        return index
    }

        static func state(
        _ message: CappellaMessage,
        currentTime: Double,
        currentLineIndex: Int
    ) -> (isActive: Bool, isPassed: Bool) {
        if message.kind == .emo {
            let active = currentTime >= message.activationStart && currentTime < message.activationEnd
            return (active, currentTime >= message.activationEnd)
        }
        if message.kind == .title {
            return (false, false)
        }
        return (message.lineIndex == currentLineIndex, message.lineIndex < currentLineIndex)
    }

        static func bubbleColors(
        _ message: CappellaMessage,
        _ theme: ThemeColors
    ) -> (background: Color, border: Color, text: Color) {
        if message.sideRight {
            return (
                mixColor(theme.accent, theme.primary, 0.18, 0.94),
                mixColor(theme.accent, theme.primary, 0.34, 0.3),
                theme.background
            )
        }
        let tone = Double(abs(message.avatarIndex) % 9) / 8.0
        let accentMix = 0.18 + tone * 0.62
        return (
            mixColor(theme.secondary, theme.accent, accentMix, 1),
            mixColor(theme.secondary, theme.accent, min(accentMix + 0.18, 1), 0.26),
            theme.primary
        )
    }

        static func mixColor(_ from: Color, _ to: Color, _ amount: Double, _ alpha: Double) -> Color {
        let clamped = min(max(amount, 0), 1)
        let uiFrom = UIColor(from)
        let uiTo = UIColor(to)
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0
        uiFrom.getRed(&fr, green: &fg, blue: &fb, alpha: nil)
        uiTo.getRed(&tr, green: &tg, blue: &tb, alpha: nil)
        let r = Double(fr) + (Double(tr) - Double(fr)) * clamped
        let g = Double(fg) + (Double(tg) - Double(fg)) * clamped
        let b = Double(fb) + (Double(tb) - Double(fb)) * clamped
        return Color(red: r, green: g, blue: b).opacity(min(max(alpha, 0), 1))
    }

        static func formatTimestamp(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    @MainActor private static var estCache: [String: CGFloat] = [:]
    private static let estCacheLimit = 256

    @MainActor
    static func estimatedHeight(
        _ message: CappellaMessage,
        isActive: Bool,
        motion: CappellaMotion,
        baseFontSize: Double,
        maxTextWidth: Double
    ) -> CGFloat {
        let key = "\(message.id)|\(isActive)|\(Int(maxTextWidth))"
        if let cached = estCache[key] {
            return cached
        }

        let height: CGFloat
        if message.kind == .emo {
                        let imageSize = isActive ? motion.emoActiveSize : motion.emoInactiveSize
            let overflow = isActive && motion.activeScale > 1
                ? ceil(imageSize * (motion.activeScale - 1))
                : 0
            height = CGFloat(imageSize + overflow + 48 + 12)
        } else {
            let fontSize = message.kind == .title
                ? baseFontSize
                : baseFontSize * (isActive ? motion.activeFontMultiplier : motion.inactiveFontMultiplier)
            let paddingX = isActive ? motion.activePaddingX : motion.inactivePaddingX
            let paddingY = isActive ? motion.activePaddingY : motion.inactivePaddingY
            let lineHeightPx = fontSize * 1.45
            let text = message.kind == .title ? message.text : (message.line?.plainText ?? "")
            let measured = CappellaTextMeasure.measure(
                text: text,
                fontSize: CGFloat(fontSize),
                lineHeightPx: CGFloat(lineHeightPx),
                maxTextWidth: CGFloat(maxTextWidth),
                paddingX: CGFloat(paddingX),
                paddingY: CGFloat(paddingY)
            ).height
            let minHeight = max(
                isActive ? motion.activeMinHeight : motion.inactiveMinHeight,
                lineHeightPx + paddingY * 2
            )
            let rendered = max(measured, CGFloat(minHeight))
            let overflow = isActive && motion.activeScale > 1
                ? ceil(Double(rendered) * (motion.activeScale - 1))
                : 0
            height = rendered + CGFloat(overflow) + 12
        }

        if estCache[key] == nil && estCache.count >= estCacheLimit {
            estCache.removeAll(keepingCapacity: true)
        }
        estCache[key] = height
        return height
    }

        @MainActor
    static func visibleMessages(
        _ messages: [CappellaMessage],
        visibleLineIndex: Int,
        viewportHeight: Double,
        currentLineIndex: Int,
        currentTime: Double,
        motion: CappellaMotion,
        baseFontSize: Double,
        maxTextWidth: Double
    ) -> [CappellaMessage] {
        let visible = messages.filter { message in
            switch message.kind {
            case .title:
                return true
            case .emo:
                return currentTime >= message.activationStart
            case .lyric:
                return message.lineIndex <= visibleLineIndex
            }
        }

        let usableHeight = CGFloat(max(200, viewportHeight - 240))
        var accumulated: CGFloat = 0
        var result: [CappellaMessage] = []

        for message in visible.reversed() {
            let isActive = state(message, currentTime: currentTime, currentLineIndex: currentLineIndex).isActive
            let estHeight = estimatedHeight(
                message,
                isActive: isActive,
                motion: motion,
                baseFontSize: baseFontSize,
                maxTextWidth: maxTextWidth
            )
            if accumulated + estHeight > usableHeight && result.count >= 2 {
                break
            }
            accumulated += estHeight
            result.insert(message, at: 0)
            if result.count >= CappellaConstants.maxVisibleMessages {
                break
            }
        }
        return result
    }
}

enum CappellaAnim {

            static func bezier(_ x: Double, _ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double) -> Double {
        let clamped = min(max(x, 0), 1)
        func component(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        var low = 0.0
        var high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if component(mid, p1x, p2x) < clamped {
                low = mid
            } else {
                high = mid
            }
        }
        let t = (low + high) / 2
        return component(t, p1y, p2y)
    }

    static func easeOut(_ x: Double) -> Double { bezier(x, 0, 0, 0.58, 1) }
    static func easeIn(_ x: Double) -> Double { bezier(x, 0.42, 0, 1, 1) }

        static func spring(from: Double, to: Double, elapsed: Double, motion: CappellaMotion) -> Double {
        let k = motion.springStiffness
        let c = motion.springDamping
        let m = motion.springMass
        let omega0 = sqrt(k / m)
        let zeta = c / (2 * sqrt(k * m))
        let delta = from - to
        let clampedElapsed = max(elapsed, 0)
        let decay = exp(-zeta * omega0 * clampedElapsed)

        if zeta < 1 {
            let omegaD = omega0 * sqrt(1 - zeta * zeta)
            let cosT = cos(omegaD * clampedElapsed)
            let sinT = sin(omegaD * clampedElapsed)
            return to + decay * (delta * cosT + (zeta * omega0 * delta / omegaD) * sinT)
        }
                let r = sqrt(zeta * zeta - 1) * omega0
        let term1 = delta * (r + zeta * omega0) / (2 * r)
        let term2 = delta * (r - zeta * omega0) / (2 * r)
        return to + term1 * exp(-(zeta * omega0 - r) * clampedElapsed) - term2 * exp(-(zeta * omega0 + r) * clampedElapsed)
    }
}

final class CappellaRuntime {
    struct Entry {
        var firstSeen: Double
        var lastSeen: Double
        var exitStart: Double?
    }

    private var entries: [String: Entry] = [:]
        private var initialized = false

    func sync(visibleIds: [String], now: Double) {
        let visibleSet = Set(visibleIds)
        if !initialized {
            for id in visibleSet {
                entries[id] = Entry(firstSeen: -100_000, lastSeen: now, exitStart: nil)
            }
            initialized = true
            return
        }

        for id in visibleSet {
            if var entry = entries[id] {
                entry.lastSeen = now
                if entry.exitStart != nil {
                                        entry = Entry(firstSeen: now, lastSeen: now, exitStart: nil)
                }
                entries[id] = entry
            } else {
                entries[id] = Entry(firstSeen: now, lastSeen: now, exitStart: nil)
            }
        }
        for (id, entry) in entries where !visibleSet.contains(id) && entry.exitStart == nil {
            entries[id]?.exitStart = entry.lastSeen
        }
    }

    func entry(_ id: String) -> Entry? {
        entries[id]
    }

        func purge(now: Double, exitDuration: Double) {
        for (id, entry) in entries {
            if let exitStart = entry.exitStart, now - exitStart > exitDuration + 0.1 {
                entries[id] = nil
            }
        }
        if entries.count > 96 {
            entries = entries.filter { $0.value.exitStart == nil }
        }
    }
}

struct CappellaLyricsView: View {
    let scheduler: LyricScheduler
    let theme: ThemeColors
    let titleText: String
    let artistText: String?

    @State private var runtime = CappellaRuntime()

        @MainActor private static var messagesCache: (key: String, messages: [CappellaMessage])?

    private struct RenderItem: Identifiable {
        let message: CappellaMessage
        let entry: CappellaRuntime.Entry
        var id: String { message.id }
    }

    init(scheduler: LyricScheduler, theme: ThemeColors, title: String?, artist: String?) {
        self.scheduler = scheduler
        self.theme = theme
        self.artistText = artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                self.titleText = trimmedTitle.isEmpty ? "未在播放" : trimmedTitle
    }

    var body: some View {
        GeometryReader { geo in
            let vw = geo.size.width
            let vh = geo.size.height
                        let baseFontSize: Double = 18
                        let maxPanelWidth = min(max(Double(vw) - 32, 1), 896)
            let bubbleGroupRatio = vw >= 640 ? 0.68 : 0.78
            let maxTextWidth = max(96, (maxPanelWidth * bubbleGroupRatio - 56).rounded(.down))

            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                railContent(
                    date: context.date,
                    vw: vw,
                    vh: vh,
                    baseFontSize: baseFontSize,
                    maxTextWidth: maxTextWidth
                )
            }
        }
    }

    @ViewBuilder
    private func railContent(date: Date, vw: CGFloat, vh: CGFloat, baseFontSize: Double, maxTextWidth: Double) -> some View {
                let now = date.timeIntervalSinceReferenceDate
                let t = PlayerCenter.shared.lyricClock
                let lines = scheduler.lyrics.lines
                let messages = Self.messages(lines: lines, titleText: titleText)
                let currentLineIndex = CappellaLayout.visibleLineIndex(at: t, lines: lines)
                let visible = CappellaLayout.visibleMessages(
                    messages,
                    visibleLineIndex: currentLineIndex,
                    viewportHeight: Double(vh),
                    currentLineIndex: currentLineIndex,
                    currentTime: t,
                    motion: .standard,
                    baseFontSize: baseFontSize,
                    maxTextWidth: maxTextWidth
                )

                let _ = runtime.sync(visibleIds: visible.map(\.id), now: now)
                let _ = runtime.purge(now: now, exitDuration: CappellaMotion.standard.rowExitDuration)

                                let visibleIds = Set(visible.map(\.id))
                let renderItems = messages.compactMap { message -> RenderItem? in
                    if visibleIds.contains(message.id) {
                        return runtime.entry(message.id).map { RenderItem(message: message, entry: $0) }
                    }
                    if let entry = runtime.entry(message.id), entry.exitStart != nil {
                        return RenderItem(message: message, entry: entry)
                    }
                    return nil
                }

                                let padH: CGFloat = vw >= 1024 ? 56 : (vw >= 640 ? 32 : 16)
                let padB: CGFloat = vw >= 640 ? 160 : 144
                let padT: CGFloat = vw >= 1024 ? 80 : (vw >= 640 ? 64 : 48)

                VStack(spacing: 12) {
                    ForEach(renderItems) { item in
                        CappellaMessageRowView(
                            message: item.message,
                            entry: item.entry,
                            t: t,
                            now: now,
                            currentLineIndex: currentLineIndex,
                            nextLineStart: Self.nextLineStart(of: item.message, lines: lines),
                            theme: theme,
                            motion: .standard,
                            baseFontSize: baseFontSize,
                            maxTextWidth: maxTextWidth,
                            avatarSeed: titleText,
                            avatarChar: avatarCharacter
                        )
                    }
                }
                .frame(maxWidth: 896)
                .padding(.horizontal, padH)
                .padding(.top, padT)
                .padding(.bottom, padB)
                .frame(maxHeight: .infinity, alignment: .top)
                .frame(maxWidth: .infinity)
    }

        private static func nextLineStart(of message: CappellaMessage, lines: [LyricLine]) -> Double? {
        guard message.kind == .lyric else { return nil }
        let index = message.lineIndex + 1
        return index < lines.count ? lines[index].start : nil
    }

        private var avatarCharacter: String {
        let source = artistText?.first ?? titleText.first ?? "♪"
        return source.isLetter && source.isASCII ? String(source).uppercased() : String(source)
    }

    @MainActor
    private static func messages(lines: [LyricLine], titleText: String) -> [CappellaMessage] {
        let key = "\(titleText)|\(lines.count)|\(lines.first?.start ?? 0)|\(lines.last?.end ?? 0)"
        if let cached = messagesCache, cached.key == key {
            return cached.messages
        }
        let built = CappellaMessages.build(lines: lines, titleText: titleText, motion: .standard)
        messagesCache = (key, built)
        return built
    }
}

private struct CappellaMessageRowView: View {
    let message: CappellaMessage
    let entry: CappellaRuntime.Entry
        let t: Double
        let now: Double
    let currentLineIndex: Int
    let nextLineStart: Double?
    let theme: ThemeColors
    let motion: CappellaMotion
    let baseFontSize: Double
    let maxTextWidth: Double
    let avatarSeed: String
    let avatarChar: String

    private var state: (isActive: Bool, isPassed: Bool) {
        CappellaLayout.state(message, currentTime: t, currentLineIndex: currentLineIndex)
    }

    private var isRight: Bool { message.sideRight }
    private var isEmo: Bool { message.kind == .emo }
    private var isActive: Bool { state.isActive }

        private var fontSize: CGFloat {
        if message.kind == .title { return CGFloat(baseFontSize) }
        return CGFloat(baseFontSize * (isActive ? motion.activeFontMultiplier : motion.inactiveFontMultiplier))
    }

    private var paddingX: CGFloat { CGFloat(isActive ? motion.activePaddingX : motion.inactivePaddingX) }
    private var paddingY: CGFloat { CGFloat(isActive ? motion.activePaddingY : motion.inactivePaddingY) }
    private var lineHeight: CGFloat { fontSize * 1.45 }
    private var textMaxWidth: CGFloat { CGFloat(maxTextWidth) }

        private var preparedMetrics: CappellaPreparedMetrics? {
        guard message.kind == .lyric, isActive, let line = message.line else { return nil }
        return CappellaBubbleMetrics.metrics(
            for: line,
            fontSize: fontSize,
            lineHeightPx: lineHeight,
            maxTextWidth: textMaxWidth,
            paddingX: paddingX,
            paddingY: paddingY
        )
    }

    private var rowTransform: (opacity: Double, y: Double, scale: Double) {
        if let exitStart = entry.exitStart {
            let p = min(max((now - exitStart) / motion.rowExitDuration, 0), 1)
            let e = CappellaAnim.easeIn(p)
            return (1 - e, motion.rowExitY * e, 1 + (motion.rowExitScale - 1) * e)
        }
        let p = min(max((now - entry.firstSeen) / motion.rowEnterDuration, 0), 1)
        let e = CappellaAnim.easeOut(p)
        return (e, motion.rowEnterY * (1 - e), motion.rowEnterScale + (1 - motion.rowEnterScale) * e)
    }

    private var groupState: (scale: Double, opacity: Double) {
        guard message.kind != .title else { return (1, 1) }
        var segments: [(time: Double, scale: Double, opacity: Double)] = []
        if message.kind == .emo {
            segments = [
                (message.activationStart, motion.activeScale, 1),
                (message.activationEnd, motion.passedScale, motion.passedOpacity),
            ]
        } else if let line = message.line {
            segments = [
                (line.start, motion.activeScale, 1),
                (nextLineStart ?? Double.infinity, motion.passedScale, motion.passedOpacity),
            ]
        }

        var index = -1
        for (i, segment) in segments.enumerated() where t >= segment.time {
            index = i
        }
        guard index >= 0 else { return (1, 1) }
        let segment = segments[index]
        let fromScale = index == 0 ? 1 : segments[index - 1].scale
        let fromOpacity = index == 0 ? 1 : segments[index - 1].opacity
        let elapsed = t - segment.time
        if elapsed >= 3 || segment.time.isInfinite {
            return (segment.scale, segment.opacity)
        }
        let scale = CappellaAnim.spring(from: fromScale, to: segment.scale, elapsed: elapsed, motion: motion)
        let opacity = CappellaAnim.spring(from: fromOpacity, to: segment.opacity, elapsed: elapsed, motion: motion)
        return (scale, opacity)
    }

            private var scaleOverflowBase: Double {
        if isEmo {
            return isActive ? motion.emoActiveSize : motion.emoInactiveSize
        }
        if message.kind == .lyric, let metrics = preparedMetrics, let lastHeight = metrics.sizes.last?.height {
            return Double(lastHeight)
        }
        return motion.activeMinHeight
    }

    private var marginTop: CGFloat {
        let base = max(scaleOverflowBase, 40)
        return CGFloat(max(0, ceil(base * (groupState.scale - 1))))
    }

        private var animSize: CGSize? {
        if isEmo {
                        let from = motion.emoInactiveSize
            let to = motion.emoActiveSize
            let elapsed: Double
            let target: Double
            if t >= message.activationEnd {
                elapsed = t - message.activationEnd
                target = from
            } else {
                elapsed = t - message.activationStart
                target = to
            }
            let p = CappellaAnim.easeOut(min(max(elapsed / motion.emoSizeTransitionDuration, 0), 1))
            let size = from + (target - from) * p
            return CGSize(width: size, height: size)
        }

        guard message.kind == .lyric, let line = message.line else { return nil }

        if isActive, let metrics = preparedMetrics, !metrics.bubbleTargetTimes.isEmpty, metrics.sizes.count > 1 {
                                    let targetCount = CappellaReveal.characterCountAtTime(metrics.bubbleTargetTimes, t)
            let clamped = min(targetCount, metrics.sizes.count - 1)
            if clamped == 0 { return metrics.sizes[0] }
            let transitionStart = metrics.bubbleTargetTimes[clamped - 1]
            if transitionStart <= line.start {
                return metrics.sizes[clamped]
            }
            let p = CappellaAnim.easeOut(min(max((t - transitionStart) / 0.2, 0), 1))
            let from = metrics.sizes[clamped - 1]
            let to = metrics.sizes[clamped]
            return CGSize(width: from.width + (to.width - from.width) * CGFloat(p),
                          height: from.height + (to.height - from.height) * CGFloat(p))
        }

                let inactive = CappellaTextMeasure.measure(
            text: line.plainText,
            fontSize: fontSize,
            lineHeightPx: lineHeight,
            maxTextWidth: textMaxWidth,
            paddingX: paddingX,
            paddingY: paddingY
        )
        if let nextStart = nextLineStart, t >= nextStart, t - nextStart < 0.2 {
            let activeFull = CappellaTextMeasure.measure(
                text: line.plainText,
                fontSize: CGFloat(baseFontSize * motion.activeFontMultiplier),
                lineHeightPx: CGFloat(baseFontSize * motion.activeFontMultiplier * 1.45),
                maxTextWidth: textMaxWidth,
                paddingX: CGFloat(motion.activePaddingX),
                paddingY: CGFloat(motion.activePaddingY)
            )
            let p = CGFloat(CappellaAnim.easeOut((t - nextStart) / 0.2))
            return CGSize(width: activeFull.width + (inactive.width - activeFull.width) * p,
                          height: activeFull.height + (inactive.height - activeFull.height) * p)
        }
        return inactive
    }

        private var bubbleMinWidth: CGFloat? {
        guard !isEmo, isActive else { return nil }
        return 72
    }

    private var bubbleMinHeight: CGFloat {
        CGFloat(max(
            isActive ? motion.activeMinHeight : motion.inactiveMinHeight,
            Double(lineHeight) + Double(paddingY) * 2
        ))
    }

    private var timestamp: (text: String, p: Double)? {
        guard let line = message.line else { return nil }
        let visibleAt: Double
        if message.kind == .emo {
            visibleAt = message.activationEnd
        } else {
                        let readyTime = preparedMetrics?.timestampReadyTime ?? line.end
            visibleAt = min(nextLineStart ?? Double.infinity, readyTime)
        }
        guard t >= visibleAt else { return nil }
        let p = CappellaAnim.easeOut(min(max((t - visibleAt) / 0.18, 0), 1))
        return (CappellaLayout.formatTimestamp(line.end), p)
    }

    var body: some View {
        Group {
            if isEmo {
                HStack(alignment: .bottom, spacing: 12) {
                    if isRight {
                        emoBody
                        avatarView
                    } else {
                        avatarView
                        emoBody
                    }
                }
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    if isRight {
                        bubbleBody
                        avatarView
                    } else {
                        avatarView
                        bubbleBody
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isRight ? .trailing : .leading)
                .scaleEffect(CGFloat(groupState.scale), anchor: isRight ? .bottomTrailing : .bottomLeading)
        .opacity(groupState.opacity)
        .offset(y: marginTop)
                .offset(y: CGFloat(rowTransform.y))
        .scaleEffect(CGFloat(rowTransform.scale))
        .opacity(rowTransform.opacity)
                .padding(.top, isEmo ? 48 : 0)
    }

    private var avatarView: some View {
        CappellaAvatarView(
            sideRight: isRight,
            avatarIndex: message.avatarIndex,
            theme: theme,
            seed: avatarSeed,
            rightCharacter: avatarChar
        )
    }

    private var bubbleShape: UnevenRoundedRectangle {
                UnevenRoundedRectangle(
            topLeadingRadius: 24,
            bottomLeadingRadius: isRight ? 24 : 6,
            bottomTrailingRadius: isRight ? 6 : 24,
            topTrailingRadius: 24
        )
    }

    private var bubbleBody: some View {
        let colors = CappellaLayout.bubbleColors(message, theme)
        let size = animSize
        let shadowColor: Color = isActive
            ? CappellaLayout.mixColor(theme.background, theme.accent, 0.2, motion.activeShadowAlpha)
            : Color.black.opacity(0.1)
        let uiFont = UIFont.systemFont(ofSize: fontSize, weight: .regular)

        return ZStack(alignment: .topLeading) {
            Text(bubbleAttributedText(colors: colors))
                .font(.system(size: fontSize, weight: .regular))
                .lineSpacing(lineHeight - uiFont.lineHeight)
                .padding(.top, max(0, (lineHeight - uiFont.lineHeight) / 2))
                .frame(width: textMaxWidth, alignment: .leading)
        }
        .padding(.horizontal, paddingX)
        .padding(.vertical, paddingY)
        .frame(
            width: size.map { max($0.width, bubbleMinWidth ?? 0) },
            height: size.map { max($0.height, bubbleMinHeight) },
            alignment: .topLeading
        )
        .frame(minHeight: bubbleMinHeight)
                .overlay(alignment: .topLeading) {
            if isActive, let size {
                CappellaBubbleGlowView(
                    size: size,
                    color: Color.white.opacity(isRight ? motion.glowRightAlpha : motion.glowLeftAlpha),
                    opacity: motion.glowOpacity,
                    duration: motion.glowDuration,
                    now: now
                )
                .clipShape(bubbleShape)
                .allowsHitTesting(false)
            }
        }
        .background(bubbleShape.fill(colors.background))
        .overlay(bubbleShape.stroke(colors.border, lineWidth: 1))
        .shadow(color: shadowColor, radius: isActive ? 24 : 7.5, y: isActive ? 18 : 5)
                .overlay(alignment: .bottom) {
            if let ts = timestamp, let size {
                let tsWidth = CGFloat(ts.text.count) * 6.6 + 1
                Text(ts.text)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.secondary)
                    .fixedSize()
                    .opacity(0.62 * ts.p)
                    .offset(
                        x: isRight ? -(size.width / 2 + 8 + tsWidth / 2) : (size.width / 2 + 8 + tsWidth / 2),
                        y: -4 + CGFloat(1 - ts.p) * 4
                    )
                    .allowsHitTesting(false)
            }
        }
    }

            private func bubbleAttributedText(colors: (background: Color, border: Color, text: Color)) -> AttributedString {
        guard message.kind == .lyric, isActive, let metrics = preparedMetrics else {
            return AttributedString(message.kind == .title ? message.text : (message.line?.plainText ?? ""))
        }
        let baseColor = UIColor(colors.text)
        let visibleCount = CappellaReveal.characterCountAtTime(metrics.revealTimes, t)
        var result = AttributedString()
        for (index, character) in metrics.characters.enumerated() {
            var run = AttributedString(String(character))
            if index < visibleCount {
                let fadeSeconds = metrics.fadeDurationsMs[index] / 1000
                let p = CappellaAnim.easeOut(min(max((t - metrics.revealTimes[index]) / fadeSeconds, 0), 1))
                run.foregroundColor = Color(uiColor: baseColor.withAlphaComponent(p))
            } else {
                run.foregroundColor = Color(uiColor: baseColor.withAlphaComponent(0))
            }
            result += run
        }
        return result
    }

    private var emoBody: some View {
        let size = animSize ?? CGSize(width: motion.emoInactiveSize, height: motion.emoInactiveSize)
                let entryP = entry.exitStart == nil
            ? CappellaAnim.easeOut(min(max((now - entry.firstSeen) / motion.rowEnterDuration, 0), 1))
            : 1
        let wiggle = -1.6 * cos(2 * .pi * (now.truncatingRemainder(dividingBy: 1.9) / 1.9))

        return ZStack {
            Text(message.emoji ?? "")
                .font(.system(size: size.width * 0.72))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .rotationEffect(.degrees(wiggle))
        .scaleEffect(CGFloat(motion.emoEnterScale + (1 - motion.emoEnterScale) * entryP))
        .opacity(entryP)
        .overlay(alignment: .bottom) {
            if let ts = timestamp {
                let tsWidth = CGFloat(ts.text.count) * 6.6 + 1
                Text(ts.text)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.secondary)
                    .fixedSize()
                    .opacity(0.62 * ts.p)
                    .offset(
                        x: isRight ? -(size.width / 2 + 8 + tsWidth / 2) : (size.width / 2 + 8 + tsWidth / 2),
                        y: 2 + CGFloat(1 - ts.p) * 4
                    )
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct CappellaAvatarView: View {
    let sideRight: Bool
    let avatarIndex: Int
    let theme: ThemeColors
    let seed: String
    let rightCharacter: String

            private var leftEmoji: String {
        let pool = CappellaEmoji.leftAvatarPool
        guard !pool.isEmpty else { return "🐣" }
        let offset = Int(CappellaSeed.fnv1a("\(seed)|left|\(pool.count)") % UInt32(pool.count))
        let index = abs(avatarIndex + offset) % pool.count
        return pool[index]
    }

        private var gradientColors: [Color] {
        if sideRight {
            return [theme.primary, theme.accent]
        }
        let tone = Double(abs(avatarIndex) % 9) / 8.0
        return [
            CappellaLayout.mixColor(theme.primary, theme.accent, 0.2 + tone * 0.5, 1),
            theme.accent,
        ]
    }

    var body: some View {
        ZStack {
            Circle().fill(theme.secondary)
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if sideRight {
                Text(rightCharacter)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.background)
                    .minimumScaleFactor(0.5)
            } else {
                Text(leftEmoji)
                    .font(.system(size: 19))
            }
        }
        .frame(width: 40, height: 40)
        .overlay(Circle().stroke(Color.white.opacity(0.24), lineWidth: 1))
        .shadow(color: .black.opacity(0.1), radius: 7.5, y: 5)
    }
}

private struct CappellaBubbleGlowView: View {
    let size: CGSize
    let color: Color
    let opacity: Double
    let duration: Double
    let now: Double

    var body: some View {
        let progress = now.truncatingRemainder(dividingBy: duration) / duration
                        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: color, location: 0.23),
                .init(color: .clear, location: 0.34),
                .init(color: .clear, location: 0.50),
                .init(color: .clear, location: 0.50),
                .init(color: color, location: 0.73),
                .init(color: .clear, location: 0.84),
                .init(color: .clear, location: 1),
            ],
            startPoint: UnitPoint(x: -0.09, y: 0.34),
            endPoint: UnitPoint(x: 1.09, y: 0.66)
        )
        .frame(width: size.width * 2, height: size.height)
        .offset(x: -CGFloat(progress) * size.width)
        .frame(width: size.width, height: size.height, alignment: .leading)
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}
