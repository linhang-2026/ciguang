import simd

let DIORAMA_LINES_AHEAD = 3
let DIORAMA_LINES_BEHIND = 2
let DIORAMA_NEIGHBOR_RASTER_BUDGET = 2
let DIORAMA_LINE_FONT_SIZE = 0.62
let DIORAMA_TARGET_FRAME_WIDTH_FRACTION = 0.72
let DIORAMA_MIN_FIT_SCALE = 0.28
let DIORAMA_FOG_NEAR = 12.0
let DIORAMA_FOG_FAR = 30.0
let DIORAMA_TEXT_DISSOLVE_START = 2.0
let DIORAMA_TEXT_DISSOLVE_END = 0.9
let DIORAMA_TEXT_FADE_IN_START = 32.0
let DIORAMA_TEXT_FADE_IN_END = 40.0
let DIORAMA_COLOR_DAMP_RATE = 1.2
let DIORAMA_ACTIVE_LINE_OPACITY = 0.92

func resolveNeighborLineOpacity(_ offset: Int) -> Double {
    switch offset {
    case -1: return 0.3
    case -2: return 0.1
    case 1: return 0.34
    case 2: return 0.16
    case 3: return 0.06
    default: return 0
    }
}

func resolveTextLife(_ distanceToCamera: Double) -> Double {
    let farT = dclamp01((DIORAMA_TEXT_FADE_IN_END - distanceToCamera)
        / (DIORAMA_TEXT_FADE_IN_END - DIORAMA_TEXT_FADE_IN_START))
    let nearT = dclamp01((distanceToCamera - DIORAMA_TEXT_DISSOLVE_END)
        / (DIORAMA_TEXT_DISSOLVE_START - DIORAMA_TEXT_DISSOLVE_END))
    return dsmoothstep01(farT) * dsmoothstep01(nearT)
}

func resolveFrameFitScale(_ renderedWidth: Double, _ distance: Double,
                          _ verticalFovDeg: Double, _ aspect: Double) -> Double {
    if renderedWidth <= 0 || distance <= 0 { return 1 }
    let frameWidth = 2 * distance * tan((verticalFovDeg * .pi / 180) / 2) * aspect
    let targetWidth = frameWidth * DIORAMA_TARGET_FRAME_WIDTH_FRACTION
    return min(1, max(DIORAMA_MIN_FIT_SCALE, targetWidth / renderedWidth))
}

func quatFromRotationMatrix(_ raw: simd_double3x3) -> simd_quatd {
    let m = raw.transpose
    let tr = m[0, 0] + m[1, 1] + m[2, 2]
    var x = 0.0, y = 0.0, z = 0.0, w = 0.0
    if tr > 0 {
        let s = sqrt(tr + 1.0) * 2
        w = 0.25 * s
        x = (m[2, 1] - m[1, 2]) / s
        y = (m[0, 2] - m[2, 0]) / s
        z = (m[1, 0] - m[0, 1]) / s
    } else if m[0, 0] > m[1, 1] && m[0, 0] > m[2, 2] {
        let s = sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        w = (m[2, 1] - m[1, 2]) / s
        x = 0.25 * s
        y = (m[0, 1] + m[1, 0]) / s
        z = (m[0, 2] + m[2, 0]) / s
    } else if m[1, 1] > m[2, 2] {
        let s = sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        w = (m[0, 2] - m[2, 0]) / s
        x = (m[0, 1] + m[1, 0]) / s
        y = 0.25 * s
        z = (m[1, 2] + m[2, 1]) / s
    } else {
        let s = sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        w = (m[1, 0] - m[0, 1]) / s
        x = (m[0, 2] + m[2, 0]) / s
        y = (m[1, 2] + m[2, 1]) / s
        z = 0.25 * s
    }
    return simd_normalize(simd_quatd(vector: SIMD4(x, y, z, w)))
}

func frameQuaternion(_ frame: DioramaFrame, roll: Double = 0, yaw: Double = 0) -> simd_quatd {
    let basis = simd_double3x3(columns: (
        simd_normalize(frame.right),
        simd_normalize(frame.up),
        simd_normalize(-frame.forward)
    ))
    var q = quatFromRotationMatrix(basis)
        if yaw != 0 { q = q * simd_quatd(angle: yaw, axis: SIMD3(0, 1, 0)) }
    if roll != 0 { q = q * simd_quatd(angle: roll, axis: SIMD3(0, 0, 1)) }
    return q
}

struct DioramaVisibleLine {
    let index: Int
    let line: LyricLine
    let placement: DioramaTextPlacement
    let position: SIMD3<Double>
    let quaternion: simd_quatd
    let text: String
}

func dioramaMountedIndices(_ globalIndex: Int, total: Int) -> [Int] {
    guard total > 0 else { return [] }
    let start = max(globalIndex - DIORAMA_LINES_BEHIND, 0)
    let end = min(globalIndex + DIORAMA_LINES_AHEAD, total - 1)
    return start <= end ? Array(start...end) : []
}

func buildDioramaVisibleLines(frames: [DioramaFrame], lines: [LyricLine], mountedIndices: [Int],
                              globalIndex: Int, seed: String?, weaveScale: Double) -> [DioramaVisibleLine] {
    var result: [DioramaVisibleLine] = []
    for i in mountedIndices {
        guard i >= 0, i < lines.count, i < frames.count else { continue }
        let line = lines[i]
        let text = line.plainText
        guard !text.isEmpty else { continue }
        let frame = frames[i]
        let placement = getDioramaTextPlacement(i, seed: seed, weave: weaveScale)
        let position = frame.position + frame.right * placement.offsetR + frame.up * placement.offsetU
        result.append(DioramaVisibleLine(
            index: i, line: line, placement: placement,
            position: position,
            quaternion: frameQuaternion(frame, roll: placement.roll, yaw: placement.yaw),
            text: text
        ))
    }
    return result
}

@inline(__always)
func dioramaRenderEnd(_ line: LyricLine?) -> Double {
    line?.end ?? -.infinity
}
