import Foundation

let DIORAMA_PARTICLE_DENSITY_MIN = 96.0
let DIORAMA_PARTICLE_DENSITY_MAX = 1536.0
let DIORAMA_PARTICLE_DENSITY_STEP = 24.0
let DIORAMA_MAX_CORRIDOR_POINTS_PER_SPAN = 2048.0
let DIORAMA_PARTICLE_AUDIO_SCALE_MAX = 1.44

func normalizeDensity(_ density: Double) -> Double {
    let clamped = min(DIORAMA_PARTICLE_DENSITY_MAX, max(DIORAMA_PARTICLE_DENSITY_MIN, density))
    return max(DIORAMA_PARTICLE_DENSITY_MIN,
               (clamped / DIORAMA_PARTICLE_DENSITY_STEP).rounded(.down) * DIORAMA_PARTICLE_DENSITY_STEP)
}

func resolveWaveNumberMax(_ spacing: Double) -> Double {
    (Double.pi * 2) / max(1e-4, spacing * 4)
}

func stepDioramaEnvelope(_ current: Double, _ target: Double,
                         _ attack: Double, _ release: Double, _ delta: Double) -> Double {
    current + (target - current) * (1 - exp(-(target > current ? attack : release) * delta))
}

struct DioramaBandTracker {
    var fast = 0.0
    var floor = 0.0
    var peak = 0.0
        var armed = false
    var primed = false
}

private let FAST_ATTACK = 22.0
private let FAST_RELEASE = 7.0
private let FLOOR_RISE = 2.5
private let FLOOR_FALL = 4.0
private let PEAK_RISE = 9.0
private let PEAK_FALL = 0.28
private let MIN_RANGE = 0.12
private let MIN_PEAK = 0.22
private let TRIGGER_HIGH = 0.42
private let TRIGGER_LOW = 0.2

struct DioramaBandSignal {
        var transient: Double
        var sustained: Double
        var onset: Bool
}

func stepDioramaBandTracker(_ state: inout DioramaBandTracker,
                            _ level: Double, _ delta: Double) -> DioramaBandSignal {
    let safe = dclamp01(level)
    if !state.primed {
                state.fast = safe
        state.floor = safe
        state.peak = safe
        state.primed = true
    } else {
        state.fast = stepDioramaEnvelope(state.fast, safe, FAST_ATTACK, FAST_RELEASE, delta)
        state.floor = stepDioramaEnvelope(state.floor, safe, FLOOR_RISE, FLOOR_FALL, delta)
        state.peak = stepDioramaEnvelope(state.peak, safe, PEAK_RISE, PEAK_FALL, delta)
    }
    let range = max(MIN_RANGE, state.peak - state.floor)
    let transient = dclamp01((state.fast - state.floor) / range)
    let sustained = dclamp01(state.fast / max(MIN_PEAK, state.peak))
    var onset = false
    if !state.armed && transient >= TRIGGER_HIGH {
        state.armed = true
        onset = true
    } else if state.armed && transient <= TRIGGER_LOW {
        state.armed = false
    }
    return DioramaBandSignal(transient: transient, sustained: sustained, onset: onset)
}

struct DioramaRippleBand {
    var strength: Double
    var speed: Double
    var width: Double
    var wavenumber: Double
}

let RIPPLE_BANDS: [DioramaRippleBand] = [
    .init(strength: 1.45, speed: 0.9, width: 0.66, wavenumber: 3.4),
    .init(strength: 0.9, speed: 1.6, width: 0.36, wavenumber: 5.5),
    .init(strength: 0.5, speed: 2.5, width: 0.22, wavenumber: 9),
]

let RIPPLE_SLOTS_PER_BAND = 3
let DIORAMA_RIPPLE_COUNT = RIPPLE_BANDS.count * RIPPLE_SLOTS_PER_BAND

struct DioramaRipplePool {
        var sources: [SIMD4<Float>] = Array(repeating: .zero, count: DIORAMA_RIPPLE_COUNT)
        var shapes: [SIMD4<Float>] = Array(repeating: .zero, count: DIORAMA_RIPPLE_COUNT)
        var cursor: [Int] = Array(repeating: 0, count: RIPPLE_BANDS.count)
        var spawned = 0

    mutating func reset() {
        self = DioramaRipplePool()
    }
}

let DIORAMA_CORRIDOR_UNITS_PER_LINE = DIORAMA_STEP_DISTANCE / DIORAMA_PARTICLE_CORRIDOR_RADIUS

func spawnDioramaRipple(_ pool: inout DioramaRipplePool, _ bandIndex: Int,
                        _ strength: Double, _ now: Double,
                        _ corridor: Bool, _ readHeadAlong: Double) {
    let seed = dHashSeed("diorama-ripple:\(pool.spawned)")
    let preset = RIPPLE_BANDS[bandIndex]
    let height = seededUnit(seed + 1)
    let spread = seededUnit(seed + 2)
    let pace = seededUnit(seed + 3)
    let cursor = pool.cursor[bandIndex]
    let offset = (bandIndex * RIPPLE_SLOTS_PER_BAND + cursor) * 4

    if corridor {
        pool.sources[offset / 4] = SIMD4(
            Float(readHeadAlong + 0.4 + seededUnit(seed + 4) * 2.2),
            Float(seededUnit(seed + 5) * Double.pi * 2), 0, Float(now))
    } else {
                let up = seededUnit(seed + 4) * 2 - 1
        let around = seededUnit(seed + 5) * Double.pi * 2
        let ring = sqrt(max(0, 1 - up * up))
        pool.sources[offset / 4] = SIMD4(Float(ring * cos(around)), Float(up),
                                         Float(ring * sin(around)), Float(now))
    }
    pool.shapes[offset / 4] = SIMD4(
        Float(preset.strength * strength * (0.7 + height * 0.6)),
        Float(preset.speed * (0.8 + pace * 0.45)),
        Float(preset.width * (0.78 + spread * 0.5)),
        Float(preset.wavenumber))

    pool.cursor[bandIndex] = (cursor + 1) % RIPPLE_SLOTS_PER_BAND
    pool.spawned += 1
}

struct DioramaParticleAudioResponse {
        var flowSpeed: Double
        var clusterPulse: Double
}

private func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
    let amount = min(1, max(0, (value - edge0) / (edge1 - edge0)))
    return amount * amount * (3 - 2 * amount)
}

func resolveDioramaParticleAudioResponse(_ bass: DioramaBandSignal,
                                         _ mid: DioramaBandSignal) -> DioramaParticleAudioResponse {
    DioramaParticleAudioResponse(
        flowSpeed: min(1.55, 0.3 + dclamp01(bass.sustained) * 1.25),
        clusterPulse: min(DIORAMA_PARTICLE_AUDIO_SCALE_MAX,
                          1 + smoothstep(0.1, 0.9, bass.transient) * 0.14
                            + smoothstep(0.15, 0.95, mid.transient) * 0.05))
}

let DIORAMA_CORRIDOR_PULSE_SHARE = 0.12

func resolveDioramaPulseTarget(_ clusterPulse: Double, _ gain: Double, _ isCorridor: Bool) -> Double {
    1 + (clusterPulse - 1) * gain * (isCorridor ? DIORAMA_CORRIDOR_PULSE_SHARE : 1)
}

struct DioramaParticleElasticState {
    var value = 1.0
    var velocity = 0.0
}

func stepDioramaParticleElasticResponse(_ state: inout DioramaParticleElasticState,
                                        _ target: Double, _ delta: Double) -> Double {
    var remaining = min(0.1, max(0, delta))
    let safeTarget = min(DIORAMA_PARTICLE_AUDIO_SCALE_MAX, max(0.9, target))
    while remaining > 0 {
        let step = min(1.0 / 240.0, remaining)
        let acceleration = (safeTarget - state.value) * 150 - state.velocity * 15
        state.velocity += acceleration * step
        state.value += state.velocity * step
        remaining -= step
    }
    state.value = min(DIORAMA_PARTICLE_AUDIO_SCALE_MAX, max(0.9, state.value))
    return state.value
}

let DIORAMA_FORMATION_SETTLE_SECONDS = 0.4
let DIORAMA_CLOUD_SWELL = 0.34
let DIORAMA_CORRIDOR_MAX_SWELL = 0.45
let DIORAMA_CORRIDOR_QUIET_SWELL = 0.1
let DIORAMA_MAX_WAVE = 0.85
let DIORAMA_CLOUD_MAX_SWELL_REACH = DIORAMA_MAX_WAVE * DIORAMA_CLOUD_SWELL
let DIORAMA_CORRIDOR_MAX_SWELL_REACH = DIORAMA_MAX_WAVE * DIORAMA_CORRIDOR_MAX_SWELL
let DIORAMA_CORRIDOR_LINES_BEHIND = 6
let DIORAMA_CORRIDOR_LINES_AHEAD = 7
