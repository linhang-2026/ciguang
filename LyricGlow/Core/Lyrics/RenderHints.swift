import Foundation

enum RenderHints {

    static func timingClass(rawDuration: Double) -> String {
        if rawDuration < 0.10 { return "micro" }
        if rawDuration < 0.18 { return "short" }
        return "normal"
    }

        static func renderEndTime(line: LyricLine) -> Double {
        let start = line.start
        let end = line.end
        let rawDuration = max(end - start, 0)
        let timingClass = timingClass(rawDuration: rawDuration)

        if timingClass == "micro" {
            return max(end, start + 0.067)
        }

        let lastWordEnd = line.words.last?.end ?? end
        let enter: Double, exit: Double, hold: Double
        if timingClass == "short" {
            enter = min(max(rawDuration * 0.45, 0.045), 0.06)
            exit = min(max(rawDuration * 0.22, 0.03), 0.04)
            hold = 0.03
        } else {
            enter = min(0.42, max(0.22, max(rawDuration, 0.12) * 0.34))
            exit = min(0.32, max(0.18, max(rawDuration, 0.12) * 0.18))
            hold = 0.06
        }

        let linePassStart = max(lastWordEnd, start) + hold
        let exitStart: Double
        if timingClass == "short" {
            exitStart = max(start + enter + 0.01, linePassStart, end - exit)
        } else {
            exitStart = max(linePassStart, end - exit)
        }
        return max(end, exitStart + exit)
    }
}
