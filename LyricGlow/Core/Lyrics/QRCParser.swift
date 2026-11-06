import Foundation

enum QRCParser {
    struct ParsedLine {
        var start: Double
        var words: [LyricWord]
        var timed: Bool
                var rawText: String?
    }

    static func parse(_ content: String) -> Lyrics? {
        parseTupleFormat(content)
    }

        static func parseTupleFormat(_ content: String) -> Lyrics? {
        var title: String?
        var artist: String?
        var offset: Double = 0
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
            if LyricPatterns.meta("n", in: line) != nil { continue }
            if LyricPatterns.meta("t-time", in: line) != nil { continue }

                        var lineStart: Double?
            var body: Substring = line[line.startIndex...]
            if let m = line.prefixMatch(of: LyricPatterns.lineStamp),
               let t = LyricTime.parse(String(m.output.1)) {
                lineStart = t
                body = line[m.range.upperBound...]
            } else if let m = line.prefixMatch(of: LyricPatterns.lineStampMs),
                      let startMs = Double(String(m.output.1)) {
                lineStart = startMs / 1000
                body = line[m.range.upperBound...]
            }
            guard let lineStart else { continue }

                        var marks: [(start: Double, end: Double, range: Range<Substring.Index>)] = []
            for match in body.matches(of: LyricPatterns.tuple) {
                guard let start = LyricTime.parse(String(match.output.1)) else { continue }
                let second = String(match.output.2)
                var end = start
                if second.contains(":") {
                    end = LyricTime.parse(second) ?? start
                } else if let ms = Double(second) {
                    end = start + ms / 1000
                }
                marks.append((start + offset, end + offset, match.range))
            }
            for match in body.matches(of: LyricPatterns.tupleMs) {
                guard let startMs = Double(String(match.output.1)),
                      let durMs = Double(String(match.output.2)) else { continue }
                marks.append(
                    (startMs / 1000 + offset, (startMs + durMs) / 1000 + offset, match.range)
                )
            }
                        for match in body.matches(of: LyricPatterns.tupleMs2) {
                guard let startMs = Double(String(match.output.1)),
                      let durMs = Double(String(match.output.2)) else { continue }
                marks.append(
                    (startMs / 1000 + offset, (startMs + durMs) / 1000 + offset, match.range)
                )
            }
                        marks.sort { $0.range.lowerBound < $1.range.lowerBound }

            if marks.isEmpty {
                let text = String(body).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                let s = lineStart + offset
                                result.append(ParsedLine(start: s, words: [], timed: false, rawText: text))
            } else {
                                let leadingText = String(body[body.startIndex..<marks[0].range.lowerBound])
                let tupleAfterWord = !leadingText.trimmingCharacters(in: .whitespaces).isEmpty
                var words: [LyricWord] = []
                for (i, mark) in marks.enumerated() {
                    let text: String
                    if tupleAfterWord {
                                                let textStart = i == 0 ? body.startIndex : marks[i - 1].range.upperBound
                        text = String(body[textStart..<mark.range.lowerBound])
                    } else {
                                                let textEnd = i + 1 < marks.count ? marks[i + 1].range.lowerBound : body.endIndex
                        text = String(body[mark.range.upperBound..<textEnd])
                    }
                    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                    words.append(LyricWord(text: text, start: mark.start, end: mark.end))
                }
                guard !words.isEmpty else { continue }
                result.append(ParsedLine(start: lineStart + offset, words: words, timed: true, rawText: nil))
            }
        }

        guard !result.isEmpty else { return nil }
        result.sort { $0.start < $1.start }
        let lines = result.enumerated().map { i, item -> LyricLine in
                                    let words: [LyricWord]
            if let raw = item.rawText {
                let nextStart = i + 1 < result.count ? result[i + 1].start : item.start + 4
                words = LRCParser.interpolate(text: raw, start: item.start, end: max(nextStart, item.start + 0.2))
            } else {
                words = item.words
            }
            return LyricLine(id: i, words: words, isWordTimed: item.timed)
        }
        var lyrics = Lyrics(lines: lines, title: title, artist: artist)
        lyrics.fixWordEnds()
        return lyrics
    }
}
