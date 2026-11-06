import Foundation

enum LRCParser {
    static func parse(_ content: String) -> Lyrics? {
        var title: String?
        var artist: String?
        var offset: Double = 0
        var rawLines: [(start: Double, text: String)] = []

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let value = LyricPatterns.meta("ti", in: line) { title = value; continue }
            if let value = LyricPatterns.meta("ar", in: line) { artist = value; continue }
            if let value = LyricPatterns.meta("offset", in: line) {
                offset = (Double(value) ?? 0) / 1000
                continue
            }

            let stamps = timestamps(in: line)
            let text = strippedTags(line).trimmingCharacters(in: .whitespaces)
            guard !stamps.isEmpty, !text.isEmpty else { continue }
            for stamp in stamps {
                rawLines.append((stamp + offset, text))
            }
        }

        guard !rawLines.isEmpty else { return nil }
        rawLines.sort { $0.start < $1.start }
        var lines: [LyricLine] = []
        for (i, item) in rawLines.enumerated() {
            let nextStart = i + 1 < rawLines.count ? rawLines[i + 1].start : item.start + 5
            let end = max(nextStart - 0.05, item.start + 0.2)
            let words = interpolate(text: item.text, start: item.start, end: end)
            lines.append(LyricLine(id: i, words: words, isWordTimed: false))
        }
        return Lyrics(lines: lines, title: title, artist: artist)
    }

    private static func timestamps(in line: String) -> [Double] {
        var result: [Double] = []
        for match in line.matches(of: LyricPatterns.lineStamp) {
            if let t = LyricTime.parse(String(match.output.1)) {
                result.append(t)
            }
        }
        return result
    }

    private static func strippedTags(_ line: String) -> String {
        var remainder = Substring(line)
        while let match = remainder.prefixMatch(of: LyricPatterns.anyTag) {
            remainder = remainder[match.range.upperBound...]
        }
        return String(remainder)
    }

        nonisolated static func interpolate(text: String, start: Double, end: Double) -> [LyricWord] {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else {
            return [LyricWord(text: text, start: start, end: end)]
        }
        let weights = tokens.map(visualWeight)
        let total = max(weights.reduce(0, +), 1)
        let span = max(end - start, 0.2)

        var cursor = start
        var words: [LyricWord] = []
        for (token, weight) in zip(tokens, weights) {
            let duration = span * Double(weight) / Double(total)
            words.append(LyricWord(text: token, start: cursor, end: cursor + duration))
            cursor += duration
        }
        return words
    }

        nonisolated static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var latinBuffer = ""

        func flushLatin() {
            if !latinBuffer.isEmpty {
                tokens.append(latinBuffer)
                latinBuffer = ""
            }
        }

        for scalar in text.unicodeScalars {
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                if isCJK(scalar) {
                    flushLatin()
                    tokens.append(String(scalar))
                } else {
                    latinBuffer.unicodeScalars.append(scalar)
                }
            } else {
                flushLatin()
                if scalar.properties.isWhitespace {
                    if var last = tokens.last {
                        last.unicodeScalars.append(scalar)
                        tokens[tokens.count - 1] = last
                    }
                } else {
                    tokens.append(String(scalar))
                }
            }
        }
        flushLatin()
        return tokens
    }

    nonisolated private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isIdeographic
            || (0x3040...0x30FF).contains(scalar.value)
    }

        nonisolated private static func visualWeight(_ token: String) -> Int {
        var weight = 0
        for scalar in token.unicodeScalars {
            if isCJK(scalar) {
                weight += 2
            } else if scalar.properties.isWhitespace {
                weight += 1
            } else {
                weight += 1
            }
        }
        return max(weight, 1)
    }
}
