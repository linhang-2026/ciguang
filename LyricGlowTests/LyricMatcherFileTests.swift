import Foundation
import Testing
@testable import LyricGlow

struct LyricMatcherFileTests {
    @Test func 同名lrc被匹配() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyrictest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let audio = dir.appendingPathComponent("song.m4a")
        let lyric = dir.appendingPathComponent("song.lrc")
        try "占位音频".write(to: audio, atomically: true, encoding: .utf8)
        try "[00:01.00]第一行歌词".write(to: lyric, atomically: true, encoding: .utf8)

        let lyrics = try #require(LyricMatcher.findLocalLyrics(for: audio))
        #expect(lyrics.lines.first?.plainText == "第一行歌词")
    }

    @Test func 无同名歌词返回nil() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyrictest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let audio = dir.appendingPathComponent("lonely.m4a")
        try "占位音频".write(to: audio, atomically: true, encoding: .utf8)

        #expect(LyricMatcher.findLocalLyrics(for: audio) == nil)
    }
}
