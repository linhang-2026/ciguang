import SwiftUI
import UIKit

struct CladdaghLyricsView: View {
    let scheduler: LyricScheduler
    let theme: ThemeColors

        private static let focusScaleRatio: Double = 0.65
    private static let radiusScale: Double = 1.0
    private static let ellipseTiltDeg: Double = 45
    private static let showAxisLine = true
    private static let letterSpacingOffset: Double = 0

        private static let baseFontSize: Double = 72
    fileprivate static let maxArcSpan: Double = 4.25
    fileprivate static let baseTrackingEm: Double = 0.18
    private static let backFollowRatio: Double = 0.28
    private static let backOrbitFollowRatio: Double = 0.52
    private static let nextLineEntryLead: Double = 0.34
    private static let ellipseMinorRatio: Double = 0.09
    private static let focusVisibleDistRatio: Double = 0.48
    private static let maxGlyphBlurPx: Double = 8.0
    private static let maxTiltDeg: Double = 38
    private static let glowRadiusFactor: Double = 24
    private static let flashPopWindow: Double = 0.4
        private static let textSpacingScale: Double = 1.0

            @State private var appearedAt: Double?
        @State private var spring: CladdaghSpring?
        @State private var renderBase: Int?

        @MainActor private static var layoutCache: [String: CladdaghLayoutEntry] = [:]
    @MainActor private static var cacheRx: Double = -1

    var body: some View {
        GeometryReader { geo in
                        let rx = min(geo.size.width * 0.44, 560) * Self.radiusScale
            let ry = rx * 0.707

            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                let now = context.date.timeIntervalSinceReferenceDate
                let t = PlayerCenter.shared.lyricClock
                let lines = scheduler.lyrics.lines

                                                let centerIdx = Self.centerIndex(at: t, lines: lines)
                                let curLineOffset = spring?.value(at: now) ?? Double(centerIdx) * .pi
                                let base = renderBase ?? centerIdx

                                let activeLine = base >= 0 && base < lines.count ? lines[base] : nil
                let activeItems = activeLine.map { Self.layout(for: $0, rx: rx).items } ?? []
                let activeNext = base + 1 < lines.count ? lines[base + 1] : nil
                let activeRenderEnd: Double? = activeLine.map { line in
                    max(
                        RenderHints.renderEndTime(line: line),
                        activeNext.map { $0.start - Self.nextLineEntryLead } ?? (line.end + 10.0)
                    )
                }
                let activeWordOffset = CladdaghTimeline.wordOffset(activeItems, at: t, renderEnd: activeRenderEnd)
                let activeLineProgress = CladdaghTimeline.playbackProgress(activeItems, at: t, renderEnd: activeRenderEnd)
                let backOrbitFollow = .pi * Self.backOrbitFollowRatio * (1 - pow(1 - activeLineProgress, 1.35))

                                let entranceE = Self.easeCubicBezierOut(entranceProgress(at: now))
                let entranceBlurR = (1 - entranceE) * 2.0

                let ring = ZStack {
                    if Self.showAxisLine { axisLine }
                    if !lines.isEmpty, rx > 0, ry > 0 {
                        ForEach(Self.renderIndices(base: base, center: centerIdx, count: lines.count), id: \.self) { idx in
                            ringLine(idx: idx, center: centerIdx, t: t, curLineOffset: curLineOffset,
                                     rx: rx, lines: lines,
                                     activeWordOffset: activeWordOffset, backOrbitFollow: backOrbitFollow)
                        }
                    }
                }
                Group {
                    if entranceBlurR > 0.01 {
                        ring.blur(radius: CGFloat(entranceBlurR))
                    } else {
                        ring
                    }
                }
                .scaleEffect(CGFloat(0.96 + 0.04 * entranceE))
                .opacity(entranceE)
                .onChange(of: centerIdx) { old, new in
                    handleCenterChange(old: old, new: new)
                }
                .onAppear {
                    if appearedAt == nil { appearedAt = Date().timeIntervalSinceReferenceDate }
                }
            }
        }
    }

        private static func centerIndex(at t: Double, lines: [LyricLine]) -> Int {
        if let idx = schedulerIndex(at: t, lines: lines) { return idx }
        var i = lines.count - 1
        while i >= 0 {
            if t > lines[i].end { return i }
            i -= 1
        }
        return -1
    }

    private static func schedulerIndex(at t: Double, lines: [LyricLine]) -> Int? {
        _ = lines
                var low = 0, high = lines.count - 1, answer = -1
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].start <= t { answer = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return answer >= 0 ? answer : nil
    }

            private func handleCenterChange(old: Int, new: Int) {
        guard old != new else { return }
        let now = Date().timeIntervalSinceReferenceDate
        let newTarget = Double(new) * .pi
        renderBase = new
        if abs(Double(new - old)) > 1 {
            spring = CladdaghSpring(x0: newTarget, v0: 0, target: newTarget, t0: now)
        } else {
            let current = spring?.state(at: now) ?? (Double(old) * .pi, 0)
            spring = CladdaghSpring(x0: current.0, v0: current.1, target: newTarget, t0: now)
        }
    }

    private func entranceProgress(at now: Double) -> Double {
        guard let t0 = appearedAt else { return 0 }
        return min(max((now - t0) / 0.8, 0), 1)
    }

            private var axisLine: some View {
        let from = theme.primary
        var to = theme.accent
        if to == from { to = theme.secondary }
        if to == from { to = .white }
        let mixed = Self.mixColor(from, to, 0).opacity(0.2 + 0.75 * 0)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: mixed, location: 0.2),
                .init(color: mixed, location: 0.8),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 300, height: 4)
        .rotationEffect(.degrees(90 - Self.ellipseTiltDeg))
        .allowsHitTesting(false)
    }

    private func ringLine(idx: Int, center: Int, t: Double, curLineOffset: Double, rx: Double,
                          lines: [LyricLine], activeWordOffset: Double, backOrbitFollow: Double) -> some View {
        let glyphs = computeGlyphs(idx: idx, center: center, t: t, curLineOffset: curLineOffset, rx: rx,
                                  lines: lines, activeWordOffset: activeWordOffset, backOrbitFollow: backOrbitFollow)
        return ForEach(0..<glyphs.count, id: \.self) { i in
            let g = glyphs[i]
            glyphView(g)
                .rotationEffect(.degrees(g.tilt))
                .scaleEffect(CGFloat(g.scale))
                .offset(x: CGFloat(g.x), y: CGFloat(g.y))
                .opacity(g.opacity)
        }
    }

        private func computeGlyphs(idx: Int, center: Int, t: Double, curLineOffset: Double, rx: Double,
                               lines: [LyricLine], activeWordOffset: Double, backOrbitFollow: Double) -> [CladdaghGlyphRender] {
        let line = lines[idx]
        let items = Self.layout(for: line, rx: rx).items
        if items.isEmpty { return [] }

        let isUpcoming = idx > center
        let upcomingEntry: Double = isUpcoming
            ? Self.clamp((t - (line.start - Self.nextLineEntryLead)) / Self.nextLineEntryLead, 0, 1)
            : 0
        let lineDiff = abs(curLineOffset - Double(idx) * .pi) / .pi

                let currentLen = (center >= 0 && center < lines.count) ? CladdaghTimeline.visualLength(lines[center].plainText) : 0
        let targetLen = CladdaghTimeline.visualLength(line.plainText)
        var lengthFade = 1.0
        var lengthScale = 1.0
        if idx > center, currentLen > 10 {
            let fadeStrength = Self.clamp((currentLen - 10) / 8, 0, 1)
            let targetStrength = Self.clamp((targetLen - 5) / 5, 0.4, 1)
            let combined = fadeStrength * targetStrength
            let targetMinOpacity = 1.0 - combined
            let targetMinScale = 1.0 - combined * 0.25
            let transitionProgress = Self.clamp((lineDiff - 0.4) / 0.5, 0, 1)
            lengthFade = 1.0 - (1.0 - targetMinOpacity) * transitionProgress
            lengthScale = 1.0 - (1.0 - targetMinScale) * transitionProgress
        }

                let nextLine = idx + 1 < lines.count ? lines[idx + 1] : nil
        let ownRenderEnd = max(
            RenderHints.renderEndTime(line: line),
            nextLine.map { $0.start - Self.nextLineEntryLead } ?? (line.end + 10.0)
        )
        var wordOffset = CladdaghTimeline.wordOffset(items, at: t, renderEnd: ownRenderEnd)
        if idx >= center {
                        let backFollow = idx > center ? 1.0 : Self.clamp(lineDiff, 0, 1)
            wordOffset += (activeWordOffset * Self.backFollowRatio + backOrbitFollow) * backFollow
        }

                let rMajor = rx
        let rMinor = rx * Self.ellipseMinorRatio
                let thetaRot = -(Self.ellipseTiltDeg * .pi / 180)
        let cosT = cos(thetaRot)
        let sinT = sin(thetaRot)
        let maxVisibleDist = rx * Self.focusVisibleDistRatio
        let activeLineFactor = max(0, 1 - lineDiff)

        var out: [CladdaghGlyphRender] = []
        out.reserveCapacity(items.count)
        for item in items {
            let theta = Double(idx) * .pi + item.nominalAngle
            let psi = theta - curLineOffset - wordOffset
            let deltaDist = psi * rMajor
            let thetaCurve = deltaDist / rMajor
            let localCos = cos(thetaCurve)
            let d = (localCos + 1) / 2

                        let spacingFactor = 0.35 + 0.65 * pow(d, 1.2)
            let rawX = sin(thetaCurve) * rMajor * spacingFactor
            let rawY = localCos * rMinor
            let x = rawX * cosT - rawY * sinT
            let y = rawX * sinT + rawY * cosT

            let tangentX = cos(thetaCurve) * rMajor
            let tangentY = -sin(thetaCurve) * rMinor
            let rotTX = tangentX * cosT - tangentY * sinT
            let rotTY = tangentX * sinT + tangentY * cosT
            let tangentAngle = Self.normalizeReadableAngle(atan2(rotTY, rotTX) * 180 / .pi)

                        let distRatio = min(1, abs(deltaDist) / maxVisibleDist)
            let f = activeLineFactor * pow(1 - distRatio, 1.8)

            let distanceOpacity = 0.68 + 0.32 * pow(d, 1.9)
            var opacity = (0.35 + 0.65 * pow(d, 1.5) * (0.35 + 0.65 * f)) * distanceOpacity
            opacity *= Self.clamp(2 - lineDiff, 0, 1)
            if idx < center { opacity *= max(0, 1 - lineDiff) }
            opacity *= lengthFade
            if isUpcoming { opacity *= 0.18 + 0.82 * upcomingEntry }
            if lineDiff > 0.02 {
                let progress = Self.clamp((lineDiff - 0.3) / 0.6, 0, 1)
                let cosThreshold = 1.0 - 1.2 * progress
                if localCos > cosThreshold {
                    opacity *= Self.clamp(1 - (localCos - cosThreshold) / 0.15, 0, 1)
                }
            }
            if opacity <= 0.001 { continue }

            let scale = (0.22 + 0.98 * pow(d, 1.5)) * (1.0 + Self.focusScaleRatio * f) * lengthScale * item.scaleFactor
            let blurPx = Self.maxGlyphBlurPx * (1 - d) * (1 - 0.5 * f)
            let tilt = Self.clamp(tangentAngle * (0.4 + 0.6 * d), -Self.maxTiltDeg, Self.maxTiltDeg)

                        var charProgress: Double = 0
            if t >= item.end {
                charProgress = 1
            } else if t > item.start {
                let dur = item.end - item.start
                charProgress = dur > 0 ? (t - item.start) / dur : 1
            }

                        let baseGlow = Self.glowRadiusFactor * pow(f, 2.0)
            var mixRatio = 0.0
            var alpha = 0.55
            var flashPop = 0.0
            if charProgress >= 1 {
                mixRatio = 1
                alpha = 1
            } else if charProgress > 0 {
                                let progressFactor = min(1, charProgress * 15.0)
                alpha = 0.55 + 0.45 * progressFactor
                mixRatio = progressFactor
                if charProgress < Self.flashPopWindow {
                    flashPop = pow(1 - charProgress / Self.flashPopWindow, 2.0) * 0.65
                }
            }
            let glowPx = baseGlow * (1 + flashPop)
            let shadowFade = Self.clamp((glowPx - 0.5) / 2.0, 0, 1)
                        let shadow: (color: Color, radiusPx: Double)? = (glowPx > 0.5 && shadowFade > 0.01)
                ? (Self.mixColor(theme.primary, theme.accent, mixRatio).opacity(alpha * shadowFade), glowPx)
                : nil

            out.append(CladdaghGlyphRender(
                char: item.char,
                x: x,
                y: y,
                tilt: tilt,
                scale: scale,
                opacity: opacity,
                blurPx: blurPx >= 0.2 ? blurPx : 0,
                fillColor: Self.mixColor(theme.primary, theme.accent, mixRatio).opacity(alpha),
                shadow: shadow
            ))
        }
        return out
    }

            @ViewBuilder
    private func glyphView(_ g: CladdaghGlyphRender) -> some View {
        if let s = g.shadow, g.blurPx > 0 {
            glyphText(g).shadow(color: s.color, radius: CGFloat(s.radiusPx / 2)).blur(radius: CGFloat(g.blurPx / 2))
        } else if let s = g.shadow {
            glyphText(g).shadow(color: s.color, radius: CGFloat(s.radiusPx / 2))
        } else if g.blurPx > 0 {
            glyphText(g).blur(radius: CGFloat(g.blurPx / 2))
        } else {
            glyphText(g)
        }
    }

    private func glyphText(_ g: CladdaghGlyphRender) -> some View {
        Text(g.char)
            .font(.system(size: CGFloat(Self.baseFontSize), weight: .bold))
            .foregroundStyle(g.fillColor)
    }

    fileprivate static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }

        private static func normalizeReadableAngle(_ degrees: Double) -> Double {
        var n = degrees
        while n > 90 { n -= 180 }
        while n < -90 { n += 180 }
        return n
    }

        private static func easeCubicBezierOut(_ p: Double) -> Double {
        func coord(_ c1: Double, _ c2: Double, _ s: Double) -> Double {
            3 * (1 - s) * (1 - s) * s * c1 + 3 * (1 - s) * s * s * c2 + s * s * s
        }
        var lo = 0.0, hi = 1.0
        for _ in 0..<28 {
            let mid = 0.5 * (lo + hi)
            if coord(0.16, 0.3, mid) < p { lo = mid } else { hi = mid }
        }
        let s = 0.5 * (lo + hi)
        return coord(1.0, 1.0, s)
    }

        private static func mixColor(_ a: Color, _ b: Color, _ amount: Double) -> Color {
        let k = clamp(amount, 0, 1)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0
        UIColor(a).getRed(&ar, green: &ag, blue: &ab, alpha: nil)
        UIColor(b).getRed(&br, green: &bg, blue: &bb, alpha: nil)
        return Color(
            red: Double(ar + (br - ar) * k),
            green: Double(ag + (bg - ag) * k),
            blue: Double(ab + (bb - ab) * k)
        )
    }

        private static func renderIndices(base: Int, center: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var indices: [Int] = []
        for i in (base - 1)...(base + 2) where i >= 0 && i < count {
            indices.append(i)
        }
        if indices.isEmpty {
            indices.append(max(0, min(center, count - 1)))
        }
        return indices
    }

    @MainActor
    private static func layout(for line: LyricLine, rx: Double) -> CladdaghLineLayout {
        if cacheRx != rx {
            layoutCache.removeAll(keepingCapacity: true)
            cacheRx = rx
        }
        let key = "\(line.start)|\(line.plainText)"
        if let entry = layoutCache[key], entry.line == line {
            return entry.layout
        }
        let built = CladdaghLayoutBuilder.build(
            line: line,
            fontPx: baseFontSize,
            radiusPx: rx,
            spacingScale: textSpacingScale,
            letterSpacingOffsetPx: letterSpacingOffset
        )
        layoutCache[key] = CladdaghLayoutEntry(line: line, layout: built)
        if layoutCache.count > 64 {
            layoutCache.removeAll(keepingCapacity: true)
        }
        return built
    }
}

private struct CladdaghGlyphRender {
    var char: String
    var x: Double
    var y: Double
    var tilt: Double
    var scale: Double
    var opacity: Double
    var blurPx: Double
    var fillColor: Color
    var shadow: (color: Color, radiusPx: Double)?
}

private struct CladdaghLayoutEntry {
    var line: LyricLine
    var layout: CladdaghLineLayout
}

private struct CladdaghGlyphItem {
    var char: String
    var start: Double
    var end: Double
        var startAngle: Double
        var nominalAngle: Double
        var scaleFactor: Double
}

private struct CladdaghLineLayout {
    var items: [CladdaghGlyphItem]
}

private enum CladdaghLayoutBuilder {

    static func build(line: LyricLine, fontPx: Double, radiusPx: Double,
                      spacingScale: Double, letterSpacingOffsetPx: Double) -> CladdaghLineLayout {
        let timeline = CladdaghTimeline.adjustTimeline(
            CladdaghTimeline.buildLineGraphemeTimeline(line), line: line
        )
        let graphemes = Array(line.plainText)
        let n = graphemes.count
        if n == 0 || timeline.count != n { return CladdaghLineLayout(items: []) }

                        let font = UIFont.systemFont(ofSize: fontPx, weight: .bold)
        let kern = fontPx * 0.04
        var offsets = [Double](repeating: 0, count: n + 1)
        var fallbackWidth: Double = 0
        for i in 1...n {
            fallbackWidth += fallbackGraphemeWidth(graphemes[i - 1], fontPx: fontPx)
            let baseTracking = Double(max(0, i - 1)) * fontPx * CladdaghLyricsView.baseTrackingEm
            let extraOffset = Double(max(0, i - 1)) * letterSpacingOffsetPx
            let prefix = String(graphemes[0..<i])
            let measured = (prefix as NSString).size(withAttributes: [.font: font, .kern: kern]).width
            let width = measured.isFinite && measured > 0 ? Double(measured) : fallbackWidth
            offsets[i] = max(offsets[i - 1], width + baseTracking + extraOffset)
        }

                let safeSpacingScale = max(0.1, spacingScale)
        let totalWidth = offsets[n] * safeSpacingScale
        let safeRadius = max(radiusPx, fontPx * 2, 1)
        let totalSpan = totalWidth / safeRadius
        let scaleFactor = totalSpan > CladdaghLyricsView.maxArcSpan ? CladdaghLyricsView.maxArcSpan / totalSpan : 1.0

        var items: [CladdaghGlyphItem] = []
        items.reserveCapacity(n)
        for i in 0..<n {
            let centerPx = ((offsets[i] + offsets[i + 1]) / 2) * safeSpacingScale
            let startAngle = centerPx / safeRadius
            items.append(CladdaghGlyphItem(
                char: timeline[i].char,
                start: timeline[i].start,
                end: timeline[i].end,
                startAngle: startAngle,
                nominalAngle: (startAngle - totalSpan / 2) * scaleFactor,
                scaleFactor: scaleFactor
            ))
        }
        return CladdaghLineLayout(items: items)
    }

        private static func fallbackGraphemeWidth(_ c: Character, fontPx: Double) -> Double {
        if c.isWhitespace { return fontPx * 0.36 }
        if let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1,
           CladdaghTimeline.isCJKScalar(scalar) { return fontPx }
        return fontPx * 0.62
    }
}

private enum CladdaghTimeline {

    fileprivate struct GlyphTiming {
        var char: String
        var start: Double
        var end: Double
    }

        static func isCJKScalar(_ s: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FA5).contains(s.value)
            || (0x3040...0x30FF).contains(s.value)
            || (0xAC00...0xD7AF).contains(s.value)
    }

        static func visualLength(_ text: String) -> Double {
        var score = 0.0
        for u in text.utf16 {
            if (0x4E00...0x9FA5).contains(u) || (0x3040...0x30FF).contains(u) || (0xAC00...0xD7AF).contains(u) {
                score += 1.0
            } else {
                score += 0.5
            }
        }
        return score
    }

        static func buildLineGraphemeTimeline(_ line: LyricLine) -> [GlyphTiming] {
        let lineGraphemes = Array(line.plainText)
        if lineGraphemes.isEmpty { return [] }
        if line.words.isEmpty {
            return evenTimings(lineGraphemes, start: line.start, end: line.end)
        }

        var timeline = [GlyphTiming?](repeating: nil, count: lineGraphemes.count)
        var cursor = 0
        var lastResolvedTime = line.start
        for word in line.words {
            let wordGraphemes = Array(word.text)
            if wordGraphemes.isEmpty { continue }
            let matched = findSequence(lineGraphemes, wordGraphemes, from: cursor)
            let start = matched >= 0 ? matched : cursor
            let end = min(start + wordGraphemes.count, lineGraphemes.count)
            for gap in cursor..<start {
                timeline[gap] = GlyphTiming(char: String(lineGraphemes[gap]), start: word.start, end: word.start)
            }
            let wordTimings = evenTimings(wordGraphemes, start: word.start, end: word.end)
            for local in 0..<(end - start) where local < wordTimings.count {
                timeline[start + local] = GlyphTiming(
                    char: String(lineGraphemes[start + local]),
                    start: wordTimings[local].start,
                    end: wordTimings[local].end
                )
                lastResolvedTime = max(lastResolvedTime, wordTimings[local].end)
            }
            cursor = max(cursor, end)
        }
        for i in lineGraphemes.indices where timeline[i] == nil {
            timeline[i] = GlyphTiming(char: String(lineGraphemes[i]), start: lastResolvedTime, end: lastResolvedTime)
        }
        return timeline.compactMap { $0 }
    }

        private static func evenTimings(_ graphemes: [Character], start: Double, end: Double) -> [GlyphTiming] {
        if graphemes.isEmpty { return [] }
        let duration = max(end - start, 0)
        let unit = duration / Double(graphemes.count)
        return graphemes.enumerated().map { i, c in
            GlyphTiming(
                char: String(c),
                start: start + unit * Double(i),
                end: i == graphemes.count - 1 ? end : start + unit * Double(i + 1)
            )
        }
    }

    private static func findSequence(_ source: [Character], _ target: [Character], from: Int) -> Int {
        if target.isEmpty { return from }
        var index = from
        while index >= 0, index <= source.count - target.count {
            var matched = true
            for ti in 0..<target.count where source[index + ti] != target[ti] {
                matched = false
                break
            }
            if matched { return index }
            index += 1
        }
        return -1
    }

        static func adjustTimeline(_ timeline: [GlyphTiming], line: LyricLine) -> [GlyphTiming] {
        if timeline.isEmpty { return timeline }
        var a = timeline
        let n = a.count
        var i = 0
        while i < n {
            if a[i].start == a[i].end {
                var j = i
                while j < n, a[j].start == a[j].end { j += 1 }
                let gapCount = j - i
                var gapStart = i > 0 ? a[i - 1].end : line.start
                var gapEnd = j < n ? a[j].start : line.end
                let minNeeded = Double(gapCount) * 0.06
                var duration = gapEnd - gapStart
                if duration < minNeeded {
                    let deficit = minNeeded - duration
                    if i > 0, j < n {
                        let half = deficit / 2
                        let prevDuration = a[i - 1].end - a[i - 1].start
                        let prevSteal = min(half, max(0, prevDuration - 0.04))
                        let nextDuration = a[j].end - a[j].start
                        let nextSteal = min(deficit - prevSteal, max(0, nextDuration - 0.04))
                        gapStart -= prevSteal
                        gapEnd += nextSteal
                        a[i - 1].end = gapStart
                        a[j].start = gapEnd
                    } else if i > 0 {
                        let prevDuration = a[i - 1].end - a[i - 1].start
                        let prevSteal = min(deficit, max(0, prevDuration - 0.04))
                        gapStart -= prevSteal
                        a[i - 1].end = gapStart
                    } else if j < n {
                        let nextDuration = a[j].end - a[j].start
                        let nextSteal = min(deficit, max(0, nextDuration - 0.04))
                        gapEnd += nextSteal
                        a[j].start = gapEnd
                    }
                    duration = gapEnd - gapStart
                }
                let gapUnit = duration > 0 ? duration / Double(gapCount) : 0
                for k in i..<j {
                    let idxInGap = k - i
                    a[k].start = gapStart + gapUnit * Double(idxInGap)
                    a[k].end = gapStart + gapUnit * Double(idxInGap + 1)
                }
                i = j
            } else {
                i += 1
            }
        }
        return a
    }

            private static func fractionalActiveIndex(_ items: [CladdaghGlyphItem], _ t: Double, _ renderEnd: Double?) -> Double {
        if items.isEmpty { return 0 }
        if items.count == 1 {
            let item = items[0]
            let targetEnd = renderEnd ?? item.end
            let dur = max(0.2, targetEnd - item.start)
            if t <= item.start { return 0 }
            return (t - item.start) / dur
        }
        if t <= items[0].start { return 0 }

        let lastIdx = items.count - 1
        let last = items[lastIdx]
        if t >= last.start {
            if let renderEnd, renderEnd.isFinite, renderEnd > last.start {
                let progress = CladdaghLyricsView.clamp((t - last.start) / (renderEnd - last.start), 0, 1)
                return Double(lastIdx) + progress * 2.0
            }
            let prev = items[lastIdx - 1]
            let itemDur = last.end - last.start
            let gapDur = last.start - prev.start
            let stepDur = itemDur > 0 ? itemDur : (gapDur > 0 ? gapDur : 0.5)
            let progress = (t - last.start) / stepDur
            return Double(lastIdx) + min(progress, 1.8)
        }

        for i in 0..<(items.count - 1) {
            let tStart = items[i].start
            let tEnd = items[i + 1].start
            if t >= tStart, t < tEnd {
                if tEnd == tStart { return Double(i) }
                return Double(i) + (t - tStart) / (tEnd - tStart)
            }
        }
        return Double(lastIdx)
    }

        static func wordOffset(_ items: [CladdaghGlyphItem], at t: Double, renderEnd: Double?) -> Double {
        if items.isEmpty { return 0 }
        let fi = fractionalActiveIndex(items, t, renderEnd)
        let lastIdx = items.count - 1
        if fi <= Double(lastIdx) {
            let intPart = Int(floor(fi))
            let fracPart = fi - Double(intPart)
            let angleA = intPart < items.count ? items[intPart].nominalAngle : 0
            let angleB = items[min(intPart + 1, lastIdx)].nominalAngle
            return angleA + (angleB - angleA) * fracPart
        }
        let lastAngle = items[lastIdx].nominalAngle
        let prevAngle = items[max(0, lastIdx - 1)].nominalAngle
        let step = lastAngle - prevAngle
        return lastAngle + step * (fi - Double(lastIdx))
    }

        static func playbackProgress(_ items: [CladdaghGlyphItem], at t: Double, renderEnd: Double?) -> Double {
        if items.isEmpty { return 0 }
        if items.count == 1 {
            let item = items[0]
            let targetEnd = renderEnd ?? item.end
            let duration = max(0.001, targetEnd - item.start)
            return CladdaghLyricsView.clamp((t - item.start) / duration, 0, 1)
        }
        let fi = fractionalActiveIndex(items, t, renderEnd)
        return CladdaghLyricsView.clamp(fi / Double(max(1, items.count - 1)), 0, 1)
    }
}

private struct CladdaghSpring {
    static let stiffness: Double = 55
    static let damping: Double = 14
    static let mass: Double = 0.9

    var x0: Double
    var v0: Double
    var target: Double
    var t0: Double

    private static var omega0: Double { sqrt(stiffness / mass) }
    private static var zeta: Double { damping / (2 * sqrt(stiffness * mass)) }

    func value(at now: Double) -> Double {
        state(at: now).x
    }

        func state(at now: Double) -> (x: Double, v: Double) {
        let t = max(0, now - t0)
        let w0 = Self.omega0
        let z = Self.zeta
        let a = x0 - target
        if t == 0 { return (x0, v0) }
        if z < 1 {
            let wd = w0 * sqrt(1 - z * z)
            let decay = exp(-z * w0 * t)
            let b = (v0 + z * w0 * a) / wd
            let cosT = cos(wd * t)
            let sinT = sin(wd * t)
            let x = target + decay * (a * cosT + b * sinT)
            let v = decay * (-z * w0 * (a * cosT + b * sinT) + (-a * wd * sinT + b * wd * cosT))
            return (x, v)
        }
        if abs(z - 1) < 1e-6 {
            let decay = exp(-w0 * t)
            let d = v0 + w0 * a
            let x = target + (a + d * t) * decay
            let v = decay * (d - w0 * (a + d * t))
            return (x, v)
        }
        let sq = sqrt(z * z - 1)
        let r1 = -w0 * (z - sq)
        let r2 = -w0 * (z + sq)
        let c1 = (v0 - r2 * a) / (r1 - r2)
        let c2 = a - c1
        let e1 = exp(r1 * t)
        let e2 = exp(r2 * t)
        return (target + c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2)
    }
}
