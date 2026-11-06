import Foundation

@MainActor enum TTMLParser {
    static func parse(_ content: String) -> Lyrics? {
        let delegate = TTMLDelegate()
        let parser = XMLParser(data: Data(content.utf8))
        parser.delegate = delegate
        guard parser.parse(), !delegate.lines.isEmpty else { return nil }

        delegate.lines.sort { $0.start < $1.start }
        var lyrics = Lyrics(lines: delegate.lines, title: nil, artist: nil)
        lyrics.fixWordEnds()
        return lyrics
    }

        static func seconds(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if text.hasSuffix("ms") {
            guard let v = Double(text.dropLast(2)) else { return nil }
            return v / 1000
        }
        if text.hasSuffix("s") {
            return Double(text.dropLast())
        }
        if text.contains(":") {
            var total = 0.0
            for part in text.split(separator: ":") {
                guard let v = Double(part) else { return nil }
                total = total * 60 + v
            }
            return total
        }
        return Double(text)
    }

    private static func isWesternJoinable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        var hasLatin = false
        for scalar in trimmed.unicodeScalars {
            if isCJK(scalar) { return false }
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                hasLatin = true
            }
        }
        return hasLatin
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isIdeographic
            || (0x3040...0x30FF).contains(scalar.value)
            || (0xAC00...0xD7AF).contains(scalar.value)
    }

        static func mergeSyllables(_ syllables: [LyricWord]) -> [LyricWord] {
        var words: [LyricWord] = []
        for syllable in syllables {
            if var last = words.last,
               !last.text.hasSuffix(" "),
               isWesternJoinable(last.text),
               isWesternJoinable(syllable.text) {
                last.text += syllable.text
                last.end = max(last.end, syllable.end)
                words[words.count - 1] = last
            } else {
                words.append(syllable)
            }
        }
        return words
    }
}

@MainActor
private final class TTMLDelegate: NSObject, XMLParserDelegate {
    struct RawLine {
        var start: Double
        var end: Double
        var agent: String?
        var syllables: [LyricWord] = []
        var plainText = ""
        var timed = false
    }

    var lines: [LyricLine] = []
    private var currentLine: RawLine?
    private var currentSyllable: (text: String, start: Double?, end: Double?)?
    private var pendingLines: [RawLine] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = qName ?? elementName
        switch name {
        case "p":
            guard let begin = attributeDict["begin"] ?? attributeDict["tbegin"],
                  let start = TTMLParser.seconds(begin) else { return }
            let end = (attributeDict["end"] ?? attributeDict["tend"]).flatMap(TTMLParser.seconds) ?? start
            currentLine = RawLine(
                start: start,
                end: max(end, start),
                agent: attributeDict["ttm:agent"]
            )
        case "span" where currentLine != nil:
            let begin = attributeDict["begin"] ?? attributeDict["tbegin"]
            let end = attributeDict["end"] ?? attributeDict["tend"]
            currentSyllable = (
                "",
                begin.flatMap(TTMLParser.seconds),
                end.flatMap(TTMLParser.seconds)
            )
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentSyllable != nil {
            currentSyllable?.text += string
            currentLine?.plainText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = qName ?? elementName
        switch name {
        case "span":
            guard var syllable = currentSyllable else { return }
            currentSyllable = nil
            let text = syllable.text
            guard !text.isEmpty else { return }
                        if syllable.start == nil {
                syllable.start = currentLine?.syllables.last?.end ?? currentLine?.start
                syllable.end = syllable.end ?? syllable.start
            }
            if syllable.start != nil {
                currentLine?.timed = true
            }
            currentLine?.syllables.append(
                LyricWord(text: text, start: syllable.start ?? 0, end: syllable.end ?? syllable.start ?? 0)
            )
        case "p":
            guard let line = currentLine else { return }
            currentLine = nil
            let text = line.plainText.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return }
            pendingLines.append(line)
        default:
            break
        }
    }

            func parserDidEndDocument(_ parser: XMLParser) {
        var mainLines: [RawLine] = []
        for line in pendingLines {
            let isHarmony = line.agent != nil
                && mainLines.contains {
                    $0.agent != line.agent
                        && line.start < $0.end
                        && line.end > $0.start
                }
            if !isHarmony {
                mainLines.append(line)
            }
        }

        lines = mainLines.enumerated().map { index, raw in
            if raw.timed {
                return LyricLine(
                    id: index,
                    words: TTMLParser.mergeSyllables(raw.syllables),
                    isWordTimed: true
                )
            }
                        return LyricLine(
                id: index,
                words: LRCParser.interpolate(text: raw.plainText, start: raw.start, end: raw.end),
                isWordTimed: false
            )
        }
    }
}
