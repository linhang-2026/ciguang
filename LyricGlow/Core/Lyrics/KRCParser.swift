import Foundation

enum KRCParser {
        private static let krcTuple = #/<(\d+),(\d+),\d+>/#

    static func parse(_ content: String) -> Lyrics? {
        var title: String?
        var artist: String?
        var offset: Double = 0
        struct ParsedLine {
            var start: Double
            var words: [LyricWord]
        }
        var result: [ParsedLine] = []

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let value = LyricPatterns.meta("ti", in: line) { title = value; continue }
            if let value = LyricPatterns.meta("ar", in: line) { artist = value; continue }
            if let value = LyricPatterns.meta("offset", in: line) {
                offset = (Double(value) ?? 0) / 1000
                continue
            }

                        guard let m = line.prefixMatch(of: LyricPatterns.lineStampMs),
                  let startMs = Double(String(m.output.1))
            else { continue }
            let body = line[m.range.upperBound...]
            let lineStart = startMs / 1000 + offset

            var words: [LyricWord] = []
            var marks: [(start: Double, end: Double, range: Range<Substring.Index>)] = []
            for match in body.matches(of: krcTuple) {
                guard let off = Double(String(match.output.1)),
                      let dur = Double(String(match.output.2))
                else { continue }
                let start = lineStart + off / 1000
                marks.append((start, start + dur / 1000, match.range))
            }
            guard !marks.isEmpty else { continue }

                                    for (i, mark) in marks.enumerated() {
                let textEnd = i + 1 < marks.count ? marks[i + 1].range.lowerBound : body.endIndex
                let text = String(body[mark.range.upperBound..<textEnd])
                guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                words.append(LyricWord(text: text, start: mark.start, end: mark.end))
            }
            guard !words.isEmpty else { continue }
            result.append(ParsedLine(start: lineStart, words: words))
        }

        guard !result.isEmpty else { return nil }
        result.sort { $0.start < $1.start }
        let lines = result.enumerated().map { i, item in
            LyricLine(id: i, words: item.words, isWordTimed: true)
        }
        var lyrics = Lyrics(lines: lines, title: title, artist: artist)
        lyrics.fixWordEnds()
        return lyrics
    }
}
