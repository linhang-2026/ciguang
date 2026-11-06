import Foundation

enum EnhancedLRCParser {
    struct RawLine {
        var start: Double
        var words: [(text: String, start: Double)]
        var timed: Bool
    }

    static func parse(_ content: String) -> Lyrics? {
        var title: String?
        var artist: String?
        var offset: Double = 0
        var rawLines: [RawLine] = []

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let value = LyricPatterns.meta("ti", in: line) { title = value; continue }
            if let value = LyricPatterns.meta("ar", in: line) { artist = value; continue }
            if let value = LyricPatterns.meta("offset", in: line) {
                offset = (Double(value) ?? 0) / 1000
                continue
            }

            guard let lineMatch = line.prefixMatch(of: LyricPatterns.lineStamp),
                  let lineStart = LyricTime.parse(String(lineMatch.output.1)) else { continue }
            let body = line[lineMatch.range.upperBound...]

                        var marks: [(time: Double, range: Range<Substring.Index>)] = []
            for match in body.matches(of: LyricPatterns.wordStamp) {
                if let t = LyricTime.parse(String(match.output.1)) {
                    marks.append((t + offset, match.range))
                }
            }

            if marks.isEmpty {
                let text = String(body).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                rawLines.append(RawLine(start: lineStart + offset,
                                        words: [(text, lineStart + offset)],
                                        timed: false))
            } else {
                var words: [(text: String, start: Double)] = []
                for (i, mark) in marks.enumerated() {
                    let textEnd = i + 1 < marks.count ? marks[i + 1].range.lowerBound : body.endIndex
                    let text = String(body[mark.range.upperBound..<textEnd])
                    guard !text.isEmpty else { continue }
                    words.append((text, mark.time))
                }
                guard !words.isEmpty else { continue }
                rawLines.append(RawLine(start: lineStart + offset, words: words, timed: true))
            }
        }

        guard !rawLines.isEmpty else { return nil }
        rawLines.sort { $0.start < $1.start }

        var lines: [LyricLine] = []
        for (i, raw) in rawLines.enumerated() {
            let words = raw.words.map { LyricWord(text: $0.text, start: $0.start, end: $0.start) }
            lines.append(LyricLine(id: i, words: words, isWordTimed: raw.timed))
        }
        var lyrics = Lyrics(lines: lines, title: title, artist: artist)
        lyrics.fixWordEnds()
        return lyrics
    }
}
