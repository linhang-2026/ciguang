import Testing
@testable import LyricGlow

struct LyricParserTests {

    @Test func 行级LRC多时间戳与Offset() async throws {
        let lrc = """
        [ti:测试歌名]
        [ar:测试歌手]
        [offset:500]
        [00:10.00][01:20.00]重复的一行
        [00:15.50]第二行歌词
        """
        let lyrics = try #require(LRCParser.parse(lrc))

        #expect(lyrics.title == "测试歌名")
        #expect(lyrics.artist == "测试歌手")
        #expect(lyrics.lines.count == 3)

                #expect(lyrics.lines[0].start == 10.5)
        #expect(lyrics.lines[1].start == 16.0)
        #expect(lyrics.lines[2].start == 80.5)
        #expect(lyrics.lines[0].plainText == "重复的一行")
        #expect(lyrics.lines[0].isWordTimed == false)

                let first = lyrics.lines[0]
        #expect(first.words.first?.start == 10.5)
        #expect((first.words.last?.end ?? 0) <= 16.0 + 0.001)
        #expect(first.words.map(\.text).joined() == "重复的一行")
    }

    @Test func 增强LRC逐字时间戳() async throws {
        let content = """
        [00:10.00]<00:10.00>你<00:10.50>好<00:11.00>世界
        [00:12.00]下一行
        """
        let lyrics = try #require(EnhancedLRCParser.parse(content))
        #expect(lyrics.lines.count == 2)

        let line0 = lyrics.lines[0]
        #expect(line0.isWordTimed)
        #expect(line0.words.count == 3)
        #expect(line0.words[0].text == "你")
        #expect(line0.words[0].start == 10.0)
        #expect(line0.words[0].end == 10.5)
        #expect(line0.words[1].text == "好")
        #expect(line0.words[1].start == 10.5)
        #expect(line0.words[2].text == "世界")
                #expect(line0.words[2].end == 12.0)
    }

    @Test func QRC元组逐字() async throws {
        let content = "[00:05.00]你(00:05.00,00:05.50)好(00:05.50,00:06.00)"
        let lyrics = try #require(QRCParser.parse(content))
        let line = lyrics.lines[0]
        #expect(line.isWordTimed)
        #expect(line.words.count == 2)
        #expect(line.words[0].text == "你")
        #expect(line.words[0].start == 5.0)
        #expect(line.words[0].end == 5.5)
        #expect(line.words[1].text == "好")
        #expect(line.words[1].end == 6.0)
    }

    @Test func YRC毫秒时长变体与头信息() async throws {
        let content = """
        [n:by_lrcAI]
        [t-time:0,19.460]
        [00:05.000]你(00:05.000,500)好(00:05.500,500)
        """
        let lyrics = try #require(YRCParser.parse(content))
        let line = lyrics.lines[0]
        #expect(line.words.count == 2)
        #expect(line.words[0].end == 5.5)
        #expect(line.words[1].end == 6.0)
    }

    @Test func 嗅探自动分发() async throws {
                let lrc = try #require(LyricMatcher.parse("[00:01.00]行内容"))
        #expect(lrc.lines[0].isWordTimed == false)

                let enhanced = try #require(LyricMatcher.parse("[00:01.00]<00:01.00>字"))
        #expect(enhanced.lines[0].isWordTimed)

                let qrc = try #require(
            LyricMatcher.parse("[00:05.00]你(00:05.00,00:05.50)好(00:05.50,00:06.00)")
        )
        #expect(qrc.lines[0].isWordTimed)

                #expect(LyricMatcher.parse("完全不是歌词") == nil)
    }

    @Test func 分词与插值权重() {
                let tokens = LRCParser.tokenize("你好hello 世界")
        #expect(tokens == ["你", "好", "hello ", "世", "界"])

        let words = LRCParser.interpolate(text: "你好", start: 0, end: 2)
        #expect(words.count == 2)
        #expect(abs(words[0].start) < 0.001)
        #expect(abs(words[0].end - 1.0) < 0.001)
        #expect(abs(words[1].end - 2.0) < 0.001)
    }
}
