import Testing
@testable import LyricGlow

struct LyricSchedulerTests {

    private func fixture() -> Lyrics {
        Lyrics(lines: [
            LyricLine(id: 0, words: [
                LyricWord(text: "你", start: 0, end: 1),
                LyricWord(text: "好", start: 1, end: 2),
            ], isWordTimed: true),
            LyricLine(id: 1, words: [
                LyricWord(text: "世界", start: 3, end: 4.5),
            ], isWordTimed: true),
        ], title: nil, artist: nil)
    }

    @Test func 首行前无活动行() {
        let scheduler = LyricScheduler(fixture())
        #expect(scheduler.activeLineIndex(at: -0.5) == nil)
        #expect(scheduler.wordProgress(at: -0.5) == nil)
    }

    @Test func 行定位() {
        let scheduler = LyricScheduler(fixture())
        #expect(scheduler.activeLineIndex(at: 0) == 0)
        #expect(scheduler.activeLineIndex(at: 1.5) == 0)
        #expect(scheduler.activeLineIndex(at: 2.9) == 0)
        #expect(scheduler.activeLineIndex(at: 3) == 1)
                #expect(scheduler.activeLineIndex(at: 100) == 1)
    }

    @Test func 字内进度() async throws {
        let scheduler = LyricScheduler(fixture())

        let p0 = try #require(scheduler.wordProgress(at: 0.5))
        #expect(p0.lineIndex == 0)
        #expect(abs(p0.progress[0] - 0.5) < 0.001)
        #expect(p0.progress[1] == 0)

        let p1 = try #require(scheduler.wordProgress(at: 1.5))
        #expect(p1.progress[0] == 1)
        #expect(abs(p1.progress[1] - 0.5) < 0.001)

                let p2 = try #require(scheduler.wordProgress(at: 3.75))
        #expect(p2.lineIndex == 1)
        #expect(abs(p2.progress[0] - 0.5) < 0.001)
    }

    @Test func seek回跳纯函数无副作用() {
        let scheduler = LyricScheduler(fixture())
        #expect(scheduler.activeLineIndex(at: 3.2) == 1)
        #expect(scheduler.activeLineIndex(at: 0.2) == 0)
                #expect(scheduler.activeLineIndex(at: 3.2) == 1)
    }
}
