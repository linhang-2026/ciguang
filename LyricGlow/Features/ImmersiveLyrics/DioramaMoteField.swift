import Foundation
import simd

let DIORAMA_MOTE_LINES_BEHIND = 2
let DIORAMA_MOTE_LINES_AHEAD = 5
let DIORAMA_MOTE_WINDOW_LINES = DIORAMA_MOTE_LINES_BEHIND + DIORAMA_MOTE_LINES_AHEAD + 1

let DIORAMA_MOTE_CIRCUMFERENCE_MIN = 4
let DIORAMA_MOTE_CIRCUMFERENCE_MAX = 48
let DIORAMA_MOTE_RADIAL_MIN = 1
let DIORAMA_MOTE_RADIAL_MAX = 4
let DIORAMA_MOTE_DEFAULT_CIRCUMFERENCE = 28
let DIORAMA_MOTE_DEFAULT_RADIAL = 2

func resolveDioramaMoteCircumference(_ requested: Int) -> Int {
    min(DIORAMA_MOTE_CIRCUMFERENCE_MAX,
        max(DIORAMA_MOTE_CIRCUMFERENCE_MIN, requested))
}

func resolveDioramaMoteRadial(_ requested: Int) -> Int {
    return min(DIORAMA_MOTE_RADIAL_MAX, max(DIORAMA_MOTE_RADIAL_MIN, requested))
}

func dioramaMoteSlot(_ line: Int) -> Int {
    ((line % DIORAMA_MOTE_WINDOW_LINES) + DIORAMA_MOTE_WINDOW_LINES) % DIORAMA_MOTE_WINDOW_LINES
}

private let MOTE_INNER_RADIUS = 2.4
private let MOTE_RADIAL_SPAN = 5.2
private let MOTE_VERTICAL_SQUASH = 0.64

private func radicalInverse(_ index: Int, _ base: Double) -> Double {
    var result = 0.0
    var fraction = 1 / base
    var i = index
    while i > 0 {
        result += Double(i % Int(base)) * fraction
        i /= Int(base)
        fraction /= base
    }
    return result
}

func extendDioramaFrame(_ frame: DioramaFrame, _ steps: Int) -> DioramaFrame {
    guard steps != 0 else { return frame }
    return DioramaFrame(
        position: frame.position + frame.forward * DIORAMA_STEP_DISTANCE * Double(steps),
        forward: frame.forward, right: frame.right, up: frame.up)
}

func writeDioramaMoteLine(_ out: UnsafeMutablePointer<Float>, _ frame: DioramaFrame,
                          _ line: Int, _ circumference: Int, _ radial: Int,
                          _ seed: String?) {
    let base = dHashSeed(seed)
    let goldenAngle = Double.pi * (3 - sqrt(5.0))
    let twoPi = Double.pi * 2
    let phase = seededUnit(base + 991) * twoPi
    let total = circumference * radial
    var write = dioramaMoteSlot(line) * total * 3
    for ri in 0..<radial {
        for ci in 0..<circumference {
            let p = ri * circumference + ci
            let s = base + Double(line) * 131 + Double(p) * 17
            let stratum = (Double(ri) + 0.35 + seededUnit(s + 4) * 0.3) / Double(radial)
            let radius = MOTE_INNER_RADIUS + sqrt(stratum) * MOTE_RADIAL_SPAN
            let angle = phase + Double(line + ri) * goldenAngle
                + Double(ci) / Double(circumference) * twoPi
                + (seededUnit(s + 3) - 0.5) * (twoPi / Double(circumference))
            let depth = (radicalInverse(p + 1, 2) + (seededUnit(s + 2) - 0.5) / Double(total) - 0.5)
                * DIORAMA_STEP_DISTANCE
            let point = composeLocal(
                frame,
                cos(angle) * radius,
                sin(angle) * radius * MOTE_VERTICAL_SQUASH,
                depth)
            out[write] = Float(point.x)
            out[write + 1] = Float(point.y)
            out[write + 2] = Float(point.z)
            write += 3
        }
    }
}

func recycleDioramaMoteWindow(_ written: inout [Int],
                              _ motePositions: UnsafeMutablePointer<Float>,
                              _ frames: [DioramaFrame], _ globalIndex: Int, _ total: Int,
                              _ circumference: Int, _ radial: Int, _ seed: String?) -> Bool {
    let lastLine = max(0, total - 1)
    var dirty = false
    for line in (globalIndex - DIORAMA_MOTE_LINES_BEHIND)...(globalIndex + DIORAMA_MOTE_LINES_AHEAD) {
        let slot = dioramaMoteSlot(line)
        if slot < written.count, written[slot] == line { continue }
        let anchorLine = min(max(line, 0), lastLine)
        let frame = extendDioramaFrame(getFrame(frames, anchorLine), line - anchorLine)
        writeDioramaMoteLine(motePositions, frame, line, circumference, radial, seed)
        if slot >= written.count { written.append(contentsOf: Array(repeating: -1, count: slot - written.count + 1)) }
        written[slot] = line
        dirty = true
    }
    return dirty
}
