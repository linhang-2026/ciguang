import Metal
import simd

let DIORAMA_UNSUNG_UNIT_OPACITY = 0.5
let DIORAMA_UNIT_GLOW_MAX_OPACITY = 0.9
let DIORAMA_SOUL_MAX_OPACITY = 0.6
let DIORAMA_SOUL_ACTIVE_LIFT_EM = 0.06
let DIORAMA_SOUL_DETACH_LIFT_EM = 0.5
let DIORAMA_SOUL_ACTIVE_SWELL = 0.1
let DIORAMA_SOUL_DETACH_SWELL = 0.3
let DIORAMA_SOUL_HANDOFF_SECONDS = 0.5
let DIORAMA_GRADIENT_HOLD_SECONDS = 0.35
let DIORAMA_GRADIENT_TRAIL_SECONDS = 1.8

let DIORAMA_GLOW_INTENSITY = 1.0
let DIORAMA_SOUL_INTENSITY = 1.0
let DIORAMA_GRADIENT_INTENSITY = 1.0
let DIORAMA_SOUL_ACTIVE_ENABLED = true

@inline(__always)
func dEnvelopeStep(_ current: Double, _ target: Double, _ attack: Double, _ release: Double, _ delta: Double) -> Double {
    current + (target - current) * (1 - exp(-(target > current ? attack : release) * delta))
}

struct DioramaGraphemeTiming {
    let char: String
    let startTime: Double
    let endTime: Double
    var wordIndex: Int?
}

enum DioramaGraphemes {

        private static func evenTimings(_ graphemes: [String], _ startTime: Double, _ endTime: Double,
                                    _ wordIndex: Int?) -> [DioramaGraphemeTiming] {
        guard !graphemes.isEmpty else { return [] }
        let duration = max(endTime - startTime, 0)
        let unit = duration / Double(graphemes.count)
        return graphemes.enumerated().map { i, g in
            DioramaGraphemeTiming(
                char: g,
                startTime: startTime + unit * Double(i),
                endTime: i == graphemes.count - 1 ? endTime : startTime + unit * Double(i + 1),
                wordIndex: wordIndex
            )
        }
    }

            private static func wordTimings(_ word: LyricWord, _ wordIndex: Int) -> [DioramaGraphemeTiming] {
        evenTimings(splitGraphemes(word.text), word.start, word.end, wordIndex)
    }

        static func splitGraphemes(_ text: String) -> [String] {
        text.map(String.init)
    }

        private static func findSequence(_ source: [String], _ target: [String], _ from: Int) -> Int {
        guard !target.isEmpty else { return from }
        var index = from
        while index <= source.count - target.count {
            var matched = true
            for t in 0..<target.count where source[index + t] != target[t] {
                matched = false
                break
            }
            if matched { return index }
            index += 1
        }
        return -1
    }

            static func lineTimeline(_ line: LyricLine) -> [DioramaGraphemeTiming] {
        let lineGraphemes = splitGraphemes(line.plainText)
        guard !lineGraphemes.isEmpty else { return [] }
        if line.words.isEmpty {
            return evenTimings(lineGraphemes, line.start, line.end, nil)
        }

        var timeline = [DioramaGraphemeTiming?](repeating: nil, count: lineGraphemes.count)
        var cursor = 0
        var lastResolvedTime = line.start
        for (wordIndex, word) in line.words.enumerated() {
            let wordGraphemes = splitGraphemes(word.text)
            guard !wordGraphemes.isEmpty else { continue }
            let matchedStart = findSequence(lineGraphemes, wordGraphemes, cursor)
            let start = matchedStart >= 0 ? matchedStart : cursor
            let end = min(start + wordGraphemes.count, lineGraphemes.count)
            for gap in cursor..<start {
                timeline[gap] = DioramaGraphemeTiming(
                    char: lineGraphemes[gap], startTime: word.start, endTime: word.start, wordIndex: nil
                )
            }
            let timings = wordTimings(word, wordIndex)
            for local in 0..<(end - start) where local < timings.count {
                timeline[start + local] = DioramaGraphemeTiming(
                    char: lineGraphemes[start + local],
                    startTime: timings[local].startTime,
                    endTime: timings[local].endTime,
                    wordIndex: wordIndex
                )
                lastResolvedTime = max(lastResolvedTime, timings[local].endTime)
            }
            cursor = max(cursor, end)
        }
        for i in lineGraphemes.indices where timeline[i] == nil {
            timeline[i] = DioramaGraphemeTiming(
                char: lineGraphemes[i], startTime: lastResolvedTime, endTime: lastResolvedTime, wordIndex: nil
            )
        }
        return timeline.compactMap { $0 }
    }
}

private func isCJKDioramaGrapheme(_ g: String) -> Bool {
    for scalar in g.unicodeScalars {
        switch scalar.value {
        case 0x2E80...0x9FFF,
             0x3040...0x30FF,
             0xF900...0xFAFF,
             0xFF66...0xFF9F,
             0x2022, 0x00B7,
             0x25A0...0x25FF:
            return true
        default:
            continue
        }
    }
    return false
}

struct DioramaLyricUnit {
    let text: String
    let charStart: Int
    let charEnd: Int
    let startTime: Double
    let endTime: Double
}

func splitDioramaLyricUnits(_ line: LyricLine, _ timeline: [DioramaGraphemeTiming]) -> [DioramaLyricUnit] {
    guard !timeline.isEmpty else { return [] }
    let graphemes = timeline.map(\.char)
        var charOffsets: [Int] = []
    var acc = 0
    for g in graphemes { charOffsets.append(acc); acc += g.utf16.count }

    var units: [DioramaLyricUnit] = []
    func pushUnit(_ from: Int, _ to: Int) {
        let text = graphemes[from..<to].joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        units.append(DioramaLyricUnit(
            text: text,
            charStart: charOffsets[from],
            charEnd: charOffsets[to - 1] + graphemes[to - 1].utf16.count,
            startTime: timeline[from].startTime,
            endTime: timeline[to - 1].endTime
        ))
    }

    var i = 0
    while i < timeline.count {
        let g = graphemes[i]
        if g.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { i += 1; continue }
        if isCJKDioramaGrapheme(g) {
            pushUnit(i, i + 1)
            i += 1
            continue
        }
                                let wordIndex = timeline[i].wordIndex
        var j = i + 1
        while j < timeline.count,
              timeline[j].wordIndex == wordIndex,
              !graphemes[j].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isCJKDioramaGrapheme(graphemes[j]) {
            j += 1
        }
        pushUnit(i, j)
        i = j
    }
    return units
}

struct DioramaPlacedUnit {
    let raster: DioramaTextRaster.DioramaUnitRaster
    let centerX: Double
    let width: Double
    let height: Double
}

func layoutDioramaActiveUnits(_ line: LyricLine, _ units: [DioramaLyricUnit],
                              device: MTLDevice) -> (units: [DioramaPlacedUnit], lineWidth: Double)? {
    let full = line.plainText
    guard !full.isEmpty, !units.isEmpty else { return nil }
    let worldPerPx = DIORAMA_LINE_FONT_SIZE / DIORAMA_RASTER_FONT_PX
    let totalPx = DioramaTextRaster.measure(full, fontPx: DIORAMA_RASTER_FONT_PX)

    var placed: [DioramaPlacedUnit] = []
    placed.reserveCapacity(units.count)
    for unit in units {
                let prefix = String(decoding: full.utf16.prefix(unit.charStart), as: UTF16.self)
        guard let raster = DioramaTextRaster.rasterUnit(unit.text, device: device) else { continue }
        let prefixPx = DioramaTextRaster.measure(prefix, fontPx: DIORAMA_RASTER_FONT_PX)
        placed.append(DioramaPlacedUnit(
            raster: raster,
            centerX: (-totalPx / 2 + prefixPx + raster.advancePx / 2) * worldPerPx,
            width: raster.canvasWidthPx * worldPerPx,
            height: raster.canvasHeightPx * worldPerPx
        ))
    }
    guard !placed.isEmpty else { return nil }
    return (placed, totalPx * worldPerPx)
}

struct DioramaUnitFrameValues {
    var baseOpacity = 0.0
    var fill: SIMD4<Float> = SIMD4(0.5, 0.5, 0.5, 1)
    var glowOpacity = 0.0
    var glowVisible = false
    var soulOpacity = 0.0
    var soulLiftY = 0.0
    var soulSwell = 1.0
    var soulVisible = false
}

struct DioramaActiveUnitState {
    private var prevLineID: Int = -1
    private var prevGlobalIndex: Int = -1
    private var lightVals: [Double] = []
    private var soulVals: [Double] = []
    private var powerEnv: Double = 0
    private var frameOut: [DioramaUnitFrameValues] = []

            private mutating func resetIfNeeded(lineID: Int, globalIndex: Int, unitCount: Int) {
        guard prevLineID != lineID || prevGlobalIndex != globalIndex || lightVals.count != unitCount else { return }
        prevLineID = lineID
        prevGlobalIndex = globalIndex
        lightVals = [Double](repeating: 0, count: unitCount)
        soulVals = [Double](repeating: 0, count: unitCount)
    }

            mutating func update(units: [DioramaLyricUnit], lineID: Int, globalIndex: Int,
                         now: Double, delta: Double, life: Double, breath: Double, power01: Double,
                         primary: SIMD4<Float>, accent: SIMD4<Float>) -> [DioramaUnitFrameValues] {
        resetIfNeeded(lineID: lineID, globalIndex: globalIndex, unitCount: units.count)
        if frameOut.count != units.count {
            frameOut = [DioramaUnitFrameValues](repeating: DioramaUnitFrameValues(), count: units.count)
        }
        powerEnv = dEnvelopeStep(powerEnv, power01, 18, 3.5, delta)

                        let tintSeparation = abs(Double(accent.x) - Double(primary.x))
            + abs(Double(accent.y) - Double(primary.y))
            + abs(Double(accent.z) - Double(primary.z))
        var sungTint = accent
        if tintSeparation < 0.4 {
            let deficit = 1 - tintSeparation / 0.4
            let primaryLum = (Double(primary.x) + Double(primary.y) + Double(primary.z)) / 3
            let accentLum = (Double(accent.x) + Double(accent.y) + Double(accent.z)) / 3
            let targetLum = primaryLum > 0.5
                ? accentLum * (1 - 0.5 * deficit)
                : accentLum + (1 - accentLum) * 0.55 * deficit
            let neutral = SIMD4<Float>(Float(targetLum), Float(targetLum), Float(targetLum), 1)
            sungTint = sungTint + (neutral - sungTint) * Float(deficit)
        }
                let gradientStrength = min(1.5, DIORAMA_GRADIENT_INTENSITY)
        let gradHot01 = dclamp01((gradientStrength - 0.1) / 1.4)
        let gradDeep = sungTint * Float(0.8 - 0.18 * gradHot01)

                        let glowStrength = min(1.5, DIORAMA_GLOW_INTENSITY)
        let soulStrength = min(1.5, DIORAMA_SOUL_INTENSITY)

        for i in units.indices {
            let unit = units[i]
            let isCurrent = now >= unit.startTime && now < unit.endTime
            let sung = now >= unit.endTime
            let span = max(unit.endTime - unit.startTime, 0.001)
            let sungMix = sung ? 1.0 : (isCurrent ? dclamp01((now - unit.startTime) / span) : 0)

                        lightVals[i] = dEnvelopeStep(lightVals[i], isCurrent ? 1 : 0, 14, 4.5, delta)

                                    let gradientEnergy = resolveGradientEnergy(now, unit) * gradientStrength

                        frameOut[i].baseOpacity = min(
                1,
                (DIORAMA_UNSUNG_UNIT_OPACITY
                    + (DIORAMA_ACTIVE_LINE_OPACITY - DIORAMA_UNSUNG_UNIT_OPACITY) * sungMix
                    + 0.08 * min(1, gradientEnergy)) * life
            )

                                    let unitTarget = DIORAMA_GRADIENT_INTENSITY > 0 ? gradDeep : sungTint
            let unitProgress = DIORAMA_GRADIENT_INTENSITY > 0 ? gradientEnergy : lightVals[i] * 1.15
            frameOut[i].fill = primary + (unitTarget - primary) * Float(dclamp01(unitProgress))
            frameOut[i].fill.w = 1

                                    let glowLevel = lightVals[i] * life * breath * (0.6 + 0.4 * powerEnv) * glowStrength
            frameOut[i].glowOpacity = min(1, DIORAMA_UNIT_GLOW_MAX_OPACITY * glowLevel)
            frameOut[i].glowVisible = glowLevel > 0.012

                                                soulVals[i] = dEnvelopeStep(soulVals[i], isCurrent ? 1 : 0, 12, 2.2, delta)
            let flightMix = sung ? dsmoothstep01(dclamp01((now - unit.endTime) / DIORAMA_SOUL_HANDOFF_SECONDS)) : 0
            let activeReach = DIORAMA_SOUL_ACTIVE_ENABLED ? soulStrength : 0
            let onGlyph = (1 - flightMix) * activeReach
            let flown = flightMix * soulStrength
            frameOut[i].soulOpacity = min(1, DIORAMA_SOUL_MAX_OPACITY * life * soulVals[i] * (onGlyph + flown))
            frameOut[i].soulLiftY = DIORAMA_LINE_FONT_SIZE
                * (DIORAMA_SOUL_ACTIVE_LIFT_EM * onGlyph + DIORAMA_SOUL_DETACH_LIFT_EM * flown)
            frameOut[i].soulSwell = 1 + DIORAMA_SOUL_ACTIVE_SWELL * onGlyph + DIORAMA_SOUL_DETACH_SWELL * flown
            frameOut[i].soulVisible = frameOut[i].soulOpacity > 0.015
        }
        return frameOut
    }
}

private func resolveGradientEnergy(_ now: Double, _ unit: DioramaLyricUnit) -> Double {
    if now <= unit.startTime { return 0 }
    if now < unit.endTime {
        let span = max(unit.endTime - unit.startTime, 0.001)
        return dsmoothstep01(dclamp01((now - unit.startTime) / span))
    }
    let sinceSung = now - unit.endTime
    if sinceSung <= DIORAMA_GRADIENT_HOLD_SECONDS { return 1 }
    return 1 - dsmoothstep01(dclamp01((sinceSung - DIORAMA_GRADIENT_HOLD_SECONDS) / DIORAMA_GRADIENT_TRAIL_SECONDS))
}
