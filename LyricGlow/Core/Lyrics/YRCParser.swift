import Foundation

enum YRCParser {
    static func parse(_ content: String) -> Lyrics? {
        QRCParser.parseTupleFormat(content)
    }
}
