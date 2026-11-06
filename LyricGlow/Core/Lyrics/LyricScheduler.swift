import Foundation

struct LyricScheduler: Sendable {
    let lyrics: Lyrics

    init(_ lyrics: Lyrics) {
        self.lyrics = lyrics
    }

        func activeLineIndex(at t: Double) -> Int? {
        var low = 0, high = lyrics.lines.count - 1, answer = -1
        while low <= high {
            let mid = (low + high) / 2
            if lyrics.lines[mid].start <= t {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return answer >= 0 ? answer : nil
    }

        func wordProgress(at t: Double) -> (lineIndex: Int, progress: [Double])? {
        guard let index = activeLineIndex(at: t) else { return nil }
        let progress = lyrics.lines[index].words.map { word in
            guard word.end > word.start else {
                return t >= word.end ? 1.0 : 0.0
            }
            return min(max((t - word.start) / (word.end - word.start), 0), 1)
        }
        return (index, progress)
    }
}
