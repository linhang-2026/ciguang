import Foundation

struct LyricWord: Hashable, Sendable {
    var text: String
    var start: Double
    var end: Double
}

struct LyricLine: Hashable, Identifiable, Sendable {
    var id: Int
    var words: [LyricWord]
        var isWordTimed: Bool

    var start: Double { words.first?.start ?? 0 }
    var end: Double { words.last?.end ?? start }
    var plainText: String { words.map(\.text).joined() }
}

struct Lyrics: Sendable, Equatable {
    var lines: [LyricLine]
    var title: String?
    var artist: String?

        var isWordTimed: Bool {
        lines.contains { $0.isWordTimed }
    }

        mutating func fixWordEnds() {
        for li in lines.indices {
            for wi in lines[li].words.indices {
                let word = lines[li].words[wi]
                guard word.end <= word.start else { continue }
                if wi + 1 < lines[li].words.count {
                    lines[li].words[wi].end = lines[li].words[wi + 1].start
                } else if li + 1 < lines.count {
                    lines[li].words[wi].end = max(lines[li + 1].start, word.start + 0.05)
                } else {
                    lines[li].words[wi].end = word.start + 4
                }
                if lines[li].words[wi].end <= word.start {
                    lines[li].words[wi].end = word.start + 0.2
                }
            }
        }
    }
}

enum LyricTime {
    static func parse(_ raw: String) -> Double? {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]) else { return nil }
        let value = minutes * 60 + seconds
        return value.isFinite ? value : nil
    }
}

enum LyricPatterns {
        static let lineStamp = #/\[(\d{1,2}:\d{1,2}(?:[.:]\d{1,3})?)\]/#
        static let lineStampMs = #/\[(\d+),(\d+)\]/#
        static let wordStamp = #/<(\d{1,2}:\d{1,2}(?:[.:]\d{1,3})?)>/#
        static let tuple = #/\((\d{1,2}:\d{1,2}(?:[.:]\d{1,3})?),(\d{1,2}:\d{1,2}(?:[.:]\d{1,3})?|\d{1,6})\)/#
        static let tupleMs = #/\((\d+),(\d+),\d+\)/#
        static let tupleMs2 = #/\((\d+),(\d+)\)/#
        static let anyTag = #/\[[^\]]*\]/#

        static func meta(_ tag: String, in line: String) -> String? {
        let metaRegex = #/\[([a-zA-Z]+):([^\[\]]*)\]/#
        guard let match = line.prefixMatch(of: metaRegex),
              String(match.output.1).lowercased() == tag.lowercased() else { return nil }
        let value = String(match.output.2).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
