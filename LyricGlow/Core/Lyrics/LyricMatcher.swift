import Foundation

enum LyricMatcher {
        private static let tupleHint = try! Regex(#"\(\d{1,2}:\d{1,2}(?:[.:]\d{1,3})?,[\d:.]+"#)

        static func parse(_ content: String) -> Lyrics? {
                if content.contains("<tt") || content.contains("<TT") {
            return TTMLParser.parse(content)
        }
                let hasMsLine = content.firstMatch(of: #/\[\d+,\d+\]/#) != nil
        let hasMsTuple = content.firstMatch(of: #/\(\d+,\d+,\d+\)/#) != nil
                let hasMsTuple2 = content.firstMatch(of: #/\(\d+,\d+\)/#) != nil
        if hasMsLine, hasMsTuple || hasMsTuple2 {
            return YRCParser.parse(content)
        }
                if hasMsLine, content.firstMatch(of: #/<\d+,\d+,\d+>/#) != nil {
            return KRCParser.parse(content)
        }
                let hasLineStamp = content.firstMatch(
            of: #/\[\d{1,2}:\d{1,2}(?:[.:]\d{1,3})?\]/#
        ) != nil
        let hasTuple = content.firstMatch(of: Self.tupleHint) != nil
        if hasLineStamp, hasTuple {
            return content.contains("[n:") ? YRCParser.parse(content) : QRCParser.parse(content)
        }
                if content.firstMatch(of: #/<\d{1,2}:\d{1,2}/#) != nil {
            return EnhancedLRCParser.parse(content)
        }
                if content.firstMatch(of: #/\[\d{1,2}:\d{1,2}[.:]\d{1,3}\]/#) != nil
            || content.firstMatch(of: #/\[\d{1,2}:\d{1,2}\]/#) != nil {
            return LRCParser.parse(content)
        }
        return nil
    }

        static func findLocalLyrics(for audioURL: URL) -> Lyrics? {
        let base = audioURL.deletingPathExtension()
        for ext in ["lrc", "LRC", "txt"] {
            let url = base.appendingPathExtension(ext)
            guard FileManager.default.fileExists(atPath: url.path),
                  let content = try? String(contentsOf: url, encoding: .utf8),
                  let lyrics = parse(content) else { continue }
            return lyrics
        }
        return nil
    }

            @discardableResult
    static func saveLyrics(_ content: String, for audioURL: URL, overwrite: Bool = false) -> Bool {
        let lrcURL = audioURL.deletingPathExtension().appendingPathExtension("lrc")
        if !overwrite, FileManager.default.fileExists(atPath: lrcURL.path) { return false }
        do {
            try content.write(to: lrcURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

        static func removeLyrics(for audioURL: URL) {
        for ext in ["lrc", "LRC", "txt"] {
            let url = audioURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
