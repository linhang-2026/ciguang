import CoreText
import CryptoKit
import SwiftUI
import UIKit

struct FumeRenderLine {
        let text: String
        let start: Int
    let end: Int
        let left: CGFloat
        let top: CGFloat
        let width: CGFloat
        let advances: [CGFloat]
}

struct FumeWordSlice {
    let text: String
    let word: LyricWord
}

struct FumeBlock: Identifiable {
        let id: Int
    let line: LyricLine
    let variant: Variant
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let fontPx: CGFloat
    let lineHeight: CGFloat
    let renderLines: [FumeRenderLine]
        let wordSlices: [[FumeWordSlice]]

    enum Variant { case hero, body }

    var center: CGPoint { CGPoint(x: x + width / 2, y: y + height / 2) }
    var isHero: Bool { variant == .hero }
}

struct FumeArticle {
    let blocks: [FumeBlock]
        let blockBySourceLine: [Int: FumeBlock]
        let chronologicalBlocks: [FumeBlock]
    let width: CGFloat
    let height: CGFloat
    let paperBounds: CGRect
}

enum FumeArticleLayout {

        static func layout(lines: [LyricLine], viewport: CGSize) -> FumeArticle? {
        guard viewport.width > 0, viewport.height > 0, !lines.isEmpty else { return nil }

        let paperWidth = min(max(max(viewport.width * 1.95, viewport.width + 520), 920), 2400)
        let viewportHeight = max(viewport.height, 240)
        let maxColumns = paperWidth >= 1120 ? 4 : paperWidth >= 760 ? 3 : paperWidth >= 500 ? 2 : 1
        let targetHeight = viewportHeight * 2.45

        var best: (columns: Int, gap: CGFloat, densityScale: CGFloat, score: CGFloat)?
        var columns = maxColumns
        while columns >= 1 {
            let gap = min(max((paperWidth * (columns >= 4 ? 0.0065 : columns == 3 ? 0.0085 : 0.0115)).rounded(), 6), 14)
            var low: CGFloat = 0.82
            var high: CGFloat = 1.42
            for _ in 0..<8 {
                let densityScale = (low + high) / 2
                let attempt = attemptLayout(
                    lines: lines, viewport: viewport, paperWidth: paperWidth,
                    columns: columns, gap: gap, densityScale: densityScale,
                    renderDetails: false
                )
                guard let attempt else { break }
                let height = attempt.height
                var score = abs(height - targetHeight)
                if height > targetHeight { score += (height - targetHeight) * 0.14 }
                if best == nil || score < best!.score {
                    best = (columns, gap, densityScale, score)
                }
                if height < targetHeight { low = densityScale } else { high = densityScale }
            }
            columns -= 1
        }

        guard let best,
              let finalAttempt = attemptLayout(
                lines: lines, viewport: viewport, paperWidth: paperWidth,
                columns: best.columns, gap: best.gap, densityScale: best.densityScale,
                renderDetails: true
              ) else { return nil }

        let blocks = finalAttempt.blocks
        var bySource: [Int: FumeBlock] = [:]
        for block in blocks { bySource[block.id] = block }
        let chronological = blocks.sorted { $0.id < $1.id }
        return FumeArticle(
            blocks: blocks,
            blockBySourceLine: bySource,
            chronologicalBlocks: chronological,
            width: finalAttempt.width,
            height: finalAttempt.height,
            paperBounds: finalAttempt.paperBounds
        )
    }

    private struct AttemptResult {
        var blocks: [FumeBlock]
        var width: CGFloat
        var height: CGFloat
        var paperBounds: CGRect
    }

    private static func attemptLayout(
        lines: [LyricLine],
        viewport: CGSize,
        paperWidth: CGFloat,
        columns: Int,
        gap: CGFloat,
        densityScale: CGFloat,
        renderDetails: Bool
    ) -> AttemptResult? {
        let horizontalMargin = max(viewport.width * 0.86, 280)
        let verticalMargin = max(viewport.height * 0.82, 220)
        let columnWidth = (paperWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let seedKey = "lyricglow:\(columns):\(Int(paperWidth))"

                let filtered = lines.enumerated()
            .filter { !$0.element.plainText.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { lhs, rhs in
                seeded("\(seedKey):\(lhs.offset):\(lhs.element.plainText)")
                    < seeded("\(seedKey):\(rhs.offset):\(rhs.element.plainText)")
            }
        guard !filtered.isEmpty else { return nil }

        let total = filtered.count
        let forcedHero = fallbackHeroBlockIndex(filtered.map(\.element), total: total)
        var columnHeights = [CGFloat](repeating: verticalMargin, count: columns)
        var bodyTieCursor = 0
        var heroTieCursor = 0
        var blocks: [FumeBlock] = []
        blocks.reserveCapacity(total)

        for (blockIndex, entry) in filtered.enumerated() {
            let line = entry.element
            let sourceIndex = entry.offset
            let variant: FumeBlock.Variant = blockIndex == forcedHero
                ? .hero
                : naturalVariant(line: line, index: blockIndex, total: total)
            let isHero = variant == .hero

            let heroSpan = isHero ? min(columns, columns <= 1 ? 1 : 2) : 1
            let heroSpanWidth = heroSpan > 1
                ? columnWidth * CGFloat(heroSpan) + gap * CGFloat(heroSpan - 1)
                : paperWidth
            let blockWidth: CGFloat = isHero
                ? (heroSpan == 1
                    ? paperWidth
                    : columns == 2
                        ? columnWidth * 1.5 + gap * 0.5
                        : heroSpanWidth)
                : columnWidth
            let innerWidth = max(blockWidth, 120)

                        let graphemeCount = max(line.plainText.count, 1)
            let density = CGFloat(graphemeCount) + CGFloat(line.words.count) * 1.4
            let divisor = isHero ? max(density.squareRoot() * 1.5, 4.5) : max(density.squareRoot() * 2.25, 7)
            let scaled = innerWidth / divisor * densityScale
            let fontPx = isHero ? min(max(scaled, 24), 54) : min(max(scaled, 14), 28)
            let lineHeight = (fontPx * (isHero ? 1.02 : 1.06)).rounded()

            let renderLines = measureRenderLines(
                text: line.plainText,
                fontPx: fontPx,
                isHero: isHero,
                innerWidth: innerWidth,
                blockWidth: blockWidth,
                lineHeight: lineHeight
            )
            let blockHeight = CGFloat(renderLines.count) * lineHeight
            let blockGap = isHero ? max((lineHeight * 0.2).rounded(), 6) : max((lineHeight * 0.08).rounded(), 2)

            var x: CGFloat = 0
            var y: CGFloat = 0
            if isHero {
                if heroSpan == 1 {
                    y = columnHeights.max() ?? verticalMargin
                    x = horizontalMargin
                    columnHeights[0] = y + blockHeight + blockGap
                } else {
                    var bestHeight = CGFloat.infinity
                    var candidateStarts: [Int] = []
                    var start = 0
                    while start + heroSpan <= columns {
                        let covered = (start..<(start + heroSpan)).map { columnHeights[$0] }.max() ?? 0
                        if covered < bestHeight {
                            bestHeight = covered
                            candidateStarts = [start]
                        } else if covered == bestHeight {
                            candidateStarts.append(start)
                        }
                        start += 1
                    }
                    let targetStart = candidateStarts.isEmpty
                        ? 0
                        : candidateStarts[heroTieCursor % candidateStarts.count]
                    heroTieCursor += 1
                    y = bestHeight
                    x = horizontalMargin
                        + CGFloat(targetStart) * (columnWidth + gap)
                        + max((heroSpanWidth - blockWidth) * 0.5, 0)
                    for c in targetStart..<(targetStart + heroSpan) {
                        columnHeights[c] = y + blockHeight + blockGap
                    }
                }
            } else {
                var minHeight = columnHeights[0]
                var candidates = [0]
                for c in 1..<columns {
                    let h = columnHeights[c]
                    if h < minHeight {
                        minHeight = h
                        candidates = [c]
                    } else if h == minHeight {
                        candidates.append(c)
                    }
                }
                let targetColumn = candidates[bodyTieCursor % candidates.count]
                bodyTieCursor += 1
                x = horizontalMargin + CGFloat(targetColumn) * (columnWidth + gap)
                y = columnHeights[targetColumn]
                columnHeights[targetColumn] = y + blockHeight + blockGap
            }

            if renderDetails {
                blocks.append(FumeBlock(
                    id: sourceIndex,
                    line: line,
                    variant: variant,
                    x: x,
                    y: y,
                    width: blockWidth,
                    height: blockHeight,
                    fontPx: fontPx,
                    lineHeight: lineHeight,
                    renderLines: renderLines,
                    wordSlices: sliceWords(line: line, renderLines: renderLines)
                ))
            }
        }

        let articleHeight = max(columnHeights.max() ?? verticalMargin, 0) + verticalMargin
        return AttemptResult(
            blocks: blocks,
            width: paperWidth + horizontalMargin * 2,
            height: articleHeight,
            paperBounds: CGRect(
                x: horizontalMargin,
                y: verticalMargin,
                width: paperWidth,
                height: max(articleHeight - verticalMargin, verticalMargin) - verticalMargin
            )
        )
    }

    private static func naturalVariant(line: LyricLine, index: Int, total: Int) -> FumeBlock.Variant {
        let g = line.plainText.count
        guard g > 0 else { return .body }
        let shortEnough = g >= 4 && g <= 28
        let centered = abs(Double(index) - Double(total) / 2) / Double(max(total, 1))
        let random = seeded("\(line.plainText):\(index)")
        return shortEnough && centered < 0.72 && ((index + 1) % 6 == 0 || random > 0.965) ? .hero : .body
    }

        private static func fallbackHeroBlockIndex(_ lines: [LyricLine], total: Int) -> Int {
        let hasNatural = lines.enumerated().contains { naturalVariant(line: $0.element, index: $0.offset, total: total) == .hero }
        if hasNatural { return -1 }

        var bestIndex = -1
        var bestScore = -Double.infinity
        for (index, line) in lines.enumerated() {
            let g = line.plainText.count
            guard g > 0 else { continue }
            let comfortable = g >= 4 && g <= 28
            let acceptable = g <= 36
            guard comfortable || acceptable else { continue }
            let centered = abs(Double(index) - Double(total) / 2) / Double(max(total, 1))
            let lengthScore: Double = (g >= 6 && g <= 22) ? 1 : (g <= 28 ? 0.72 : 0.36)
            let jitter = seeded("\(line.plainText):\(index):fallback-hero") * 0.04
            let score = (1 - centered) * 0.62 + lengthScore * 0.34 + jitter
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        if bestIndex >= 0 { return bestIndex }
        return lines.enumerated()
            .filter { $0.element.plainText.count > 0 }
            .min { $0.element.plainText.count < $1.element.plainText.count }?.offset ?? -1
    }

        static func uiFont(_ fontPx: CGFloat, hero: Bool) -> UIFont {
        let base = UIFont.systemFont(ofSize: fontPx, weight: hero ? .semibold : .regular)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: fontPx)
    }

    static func swiftUIFont(_ fontPx: CGFloat, hero: Bool) -> Font {
        Font(uiFont(fontPx, hero: hero))
    }

    private static func measureRenderLines(
        text: String,
        fontPx: CGFloat,
        isHero: Bool,
        innerWidth: CGFloat,
        blockWidth: CGFloat,
        lineHeight: CGFloat
    ) -> [FumeRenderLine] {
        let font = uiFont(fontPx, hero: isHero)
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: innerWidth, height: 100_000), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
        guard let ctLines = CTFrameGetLines(frame) as? [CTLine], !ctLines.isEmpty else {
            return [FumeRenderLine(text: "", start: 0, end: 0, left: 0, top: 0, width: 0, advances: [0])]
        }

                let characters = Array(text)
        var utf16Offsets = [Int](repeating: 0, count: characters.count + 1)
        for (i, ch) in characters.enumerated() {
            utf16Offsets[i + 1] = utf16Offsets[i] + ch.utf16.count
        }
        let graphemeCount = characters.count

        func graphemeIndex(forUTF16 utf16: Int) -> Int {
                        var low = 0, high = graphemeCount
            while low < high {
                let mid = (low + high) / 2
                if utf16Offsets[mid] < utf16 { low = mid + 1 } else { high = mid }
            }
            return low
        }

        var renderLines: [FumeRenderLine] = []
        renderLines.reserveCapacity(ctLines.count)

        for (lineIndex, ctLine) in ctLines.enumerated() {
            let range = CTLineGetStringRange(ctLine)
            let gStart = graphemeIndex(forUTF16: range.location)
            var gEnd = graphemeIndex(forUTF16: range.location + range.length)
                        while gEnd > gStart && characters[gEnd - 1].isWhitespace {
                gEnd -= 1
            }

            var advances = [CGFloat](repeating: 0, count: max(gEnd - gStart, 0) + 1)
            for i in 0..<advances.count {
                let g = min(gStart + i, graphemeCount)
                advances[i] = CTLineGetOffsetForStringIndex(ctLine, utf16Offsets[g], nil)
            }
            let measuredWidth = advances.last ?? 0

            let lineText = gEnd > gStart ? String(characters[gStart..<gEnd]) : ""
            let left: CGFloat = isHero ? max((blockWidth - measuredWidth) * 0.08, 0) : 0
            renderLines.append(FumeRenderLine(
                text: lineText,
                start: gStart,
                end: gEnd,
                left: left,
                top: CGFloat(lineIndex) * lineHeight,
                width: min(measuredWidth, blockWidth),
                advances: advances
            ))
        }
        return renderLines
    }

        private static func sliceWords(line: LyricLine, renderLines: [FumeRenderLine]) -> [[FumeWordSlice]] {
        let characters = Array(line.plainText)
                var wordRanges: [(word: LyricWord, start: Int, end: Int)] = []
        var cursor = 0
        for word in line.words {
            let count = Array(word.text).count
            wordRanges.append((word, cursor, cursor + count))
            cursor += count
        }

        return renderLines.map { renderLine in
            var slices: [FumeWordSlice] = []
            for (word, ws, we) in wordRanges {
                let s = max(ws, renderLine.start)
                let e = min(we, renderLine.end)
                guard s < e else { continue }
                slices.append(FumeWordSlice(text: String(characters[s..<e]), word: word))
            }
            return slices
        }
    }

    static func seeded(_ key: String) -> Double {
        let digest = Insecure.SHA1.hash(data: Data(key.utf8))
        let v = digest.withUnsafeBytes { $0.load(as: UInt64.self) }
        return Double(v % 100_000) / 100_000
    }

        static func seededF(_ key: String) -> CGFloat {
        CGFloat(seeded(key))
    }
}
