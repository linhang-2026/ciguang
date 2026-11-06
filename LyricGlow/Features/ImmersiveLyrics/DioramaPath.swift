import simd

let DIORAMA_STEP_DISTANCE = 8.0
let DIORAMA_MAX_YAW = 0.5
let DIORAMA_MAX_PITCH = 0.32
let DIORAMA_HERO_DISTANCE = 5.2
let DIORAMA_CAMERA_LIFT = 0.5
let DIORAMA_SAFE_FRAME_FRACTION = 0.92
let DIORAMA_SWAY_AMP = 0.4
let DIORAMA_LIFT_AMP = 0.4
let DIORAMA_DIST_AMP = 0.5
let DIORAMA_SNAP_DISTANCE = 24.0
let DIORAMA_TEXT_OFFSET_R = 1.8
let DIORAMA_TEXT_OFFSET_U = 1.2
let DIORAMA_TEXT_ROLL = 0.2
let DIORAMA_TEXT_YAW = 0.16
let DIORAMA_TEXT_LOOK = 1.1
let DIORAMA_SHAPE_FADE_IN_START = 20.0
let DIORAMA_SHAPE_FADE_IN_END = 27.0
let DIORAMA_SHAPE_DISSOLVE_START = 3.0
let DIORAMA_SHAPE_DISSOLVE_END = 1.2

func dclamp01(_ v: Double) -> Double { min(1, max(0, v)) }
func dclamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }
func dsmoothstep01(_ t: Double) -> Double { let c = dclamp01(t); return c * c * (3 - 2 * c) }
func dmix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

func seededUnit(_ seed: Double) -> Double {
    let x = sin(seed * 12.9898) * 43758.5453
    return x - floor(x)
}

func dHashSeed(_ seed: String?) -> Double {
    guard let seed, !seed.isEmpty else { return 1 }
    var hash = 0.0
    for ch in seed.unicodeScalars {
        hash = (hash * 31 + Double(ch.value)) .truncatingRemainder(dividingBy: 100000)
    }
    return hash == 0 ? 1 : hash
}

func smoothDamp(_ current: Double, _ target: Double, _ velocity: Double,
                _ smoothTime: Double, _ deltaSeconds: Double) -> (value: Double, velocity: Double) {
    let t = max(0.0001, smoothTime)
    let omega = 2 / t
    let x = omega * deltaSeconds
    let exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
    let change = current - target
    let temp = (velocity + omega * change) * deltaSeconds
    let newVelocity = (velocity - omega * temp) * exp
    let value = target + (change + temp) * exp
    return (value, newVelocity)
}

func frameHalfWidth(_ distance: Double, _ verticalFovDeg: Double, _ aspect: Double) -> Double {
    distance * tan((verticalFovDeg * .pi / 180) / 2) * aspect
}

enum DioramaSubMode: String {
    case calm, normal, chaotic

    var preset: (move: Double, drift: Double, smooth: Double, audio: Double, weave: Double) {
        switch self {
        case .normal: return (1, 0.62, 0.42, 1, 1)
        case .calm: return (0.6, 0.4, 0.56, 0.5, 0.5)
        case .chaotic: return (1.35, 0.85, 0.33, 1.35, 1.35)
        }
    }
}

struct DioramaMotionParams {
    var moveScale: Double
    var driftScale: Double
    var smoothTime: Double
    var audioLevel: Double
    var weaveScale: Double
    var subMode: DioramaSubMode

        static let stageDefault = DioramaMotionParams(
        moveScale: 1, driftScale: 0.62, smoothTime: 0.42, audioLevel: 1, weaveScale: 1, subMode: .normal
    )
}

struct DioramaFrame: Sendable {
    var position: SIMD3<Double>
    var forward: SIMD3<Double>
    var right: SIMD3<Double>
    var up: SIMD3<Double>

    static let `default` = DioramaFrame(
        position: .zero, forward: SIMD3(0, 0, -1), right: SIMD3(1, 0, 0), up: SIMD3(0, 1, 0)
    )
}

private let worldUpD = SIMD3<Double>(0, 1, 0)

func buildDioramaPath(_ count: Int, seed: String?) -> [DioramaFrame] {
    let base = dHashSeed(seed)
    let n = max(count, 1)

        var positions: [SIMD3<Double>] = []
    positions.reserveCapacity(n + 1)
    var pos = SIMD3<Double>.zero
    for i in 0...n {
        positions.append(pos)
        let yaw = DIORAMA_MAX_YAW
            * (sin(Double(i) * 0.23 + base * 0.017) * 0.62 + sin(Double(i) * 0.11 + base * 0.041 + 1.3) * 0.38)
        let pitch = DIORAMA_MAX_PITCH * sin(Double(i) * 0.17 + base * 0.029 + 0.7)
        let cp = cos(pitch)
        let dir = SIMD3<Double>(sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)
        pos = pos + dir * DIORAMA_STEP_DISTANCE
    }

    var frames: [DioramaFrame] = []
    frames.reserveCapacity(n)
    for i in 0..<n {
        let forward = normalize(positions[i + 1] - positions[i])
        let right = normalize(cross(forward, worldUpD))
        let up = normalize(cross(right, forward))
        frames.append(DioramaFrame(position: positions[i], forward: forward, right: right, up: up))
    }
    return frames
}

func getFrame(_ frames: [DioramaFrame], _ index: Int) -> DioramaFrame {
    guard !frames.isEmpty else { return .default }
    return frames[min(max(index, 0), frames.count - 1)]
}

func composeLocal(_ frame: DioramaFrame, _ right: Double, _ up: Double, _ depth: Double) -> SIMD3<Double> {
    frame.position + frame.right * right + frame.up * up + frame.forward * depth
}

func resolveReadHeadTruck(_ wordProgress: Double, _ trackWidth: Double, _ visibleHalfWidth: Double) -> Double {
    if trackWidth <= 0 { return 0 }
    let wordOffset = (dclamp01(wordProgress) - 0.5) * trackWidth
    let allowed = max(abs(visibleHalfWidth - trackWidth / 2), 0.001)
    return allowed * tanh(wordOffset / allowed)
}

struct DioramaTextPlacement: Sendable {
    var offsetR: Double
    var offsetU: Double
    var scale: Double
    var roll: Double
    var yaw: Double
    var lookR: Double
}

func getDioramaTextPlacement(_ lineIndex: Int, seed: String?, weave: Double = 1) -> DioramaTextPlacement {
    let base = dHashSeed(seed)
    let i = Double(max(lineIndex, 0))
    let jitterR = (seededUnit(base + i * 11 + 2) - 0.5) * 0.6
    let jitterU = (seededUnit(base + i * 11 + 4) - 0.5) * 0.6
    let wanderR = sin(i * 0.47 + base * 0.019) * 0.7 + jitterR
    let wanderU = sin(i * 0.29 + base * 0.027 + 0.9) * 0.7 + jitterU
    return DioramaTextPlacement(
        offsetR: wanderR * DIORAMA_TEXT_OFFSET_R * weave,
        offsetU: wanderU * DIORAMA_TEXT_OFFSET_U * weave,
        scale: 0.82 + seededUnit(base + i * 11 + 5) * 0.46,
        roll: (seededUnit(base + i * 11 + 6) - 0.5) * 2 * DIORAMA_TEXT_ROLL * weave,
        yaw: (seededUnit(base + i * 11 + 7) - 0.5) * 2 * DIORAMA_TEXT_YAW * weave,
        lookR: (seededUnit(base + i * 11 + 8) - 0.5) * 2 * DIORAMA_TEXT_LOOK * weave
    )
}

enum DioramaShotKind: String, CaseIterable {
    case pushIn, pullBack, orbit, track, crane, hold, swell, spiral, pendulum, flyby, arc, float, glide
}

private func easeInOut(_ p: Double) -> Double { dsmoothstep01(p) }

private func getShotDir(_ lineIndex: Int, _ seed: String?) -> Double {
    seededUnit(dHashSeed(seed) + Double(lineIndex) * 7 + 3) < 0.5 ? -1 : 1
}

private func baseShotWeights() -> [DioramaShotKind: Double] {
    var w: [DioramaShotKind: Double] = [
        .pushIn: 1, .pullBack: 1, .orbit: 1, .track: 1, .crane: 1, .hold: 1, .swell: 0.85,
        .spiral: 0.9, .pendulum: 1, .flyby: 0.9, .arc: 1, .float: 0.9, .glide: 1,
    ]
        w[.track, default: 0] += 1.1
    w[.crane, default: 0] += 0.9
    w[.hold, default: 0] += 0.9
    w[.pendulum, default: 0] += 0.8
    w[.float, default: 0] += 0.8
    w[.glide, default: 0] += 0.6
    w[.arc, default: 0] += 0.4
        for k in DioramaShotKind.allCases { w[k] = max(0.05, w[k] ?? 0) }
    return w
}

private func weightedPickShot(_ weights: [DioramaShotKind: Double], _ u: Double) -> DioramaShotKind {
    let total = DioramaShotKind.allCases.reduce(0.0) { $0 + (weights[$1] ?? 0) }
    var acc = dclamp01(u) * total
    for k in DioramaShotKind.allCases {
        acc -= weights[k] ?? 0
        if acc <= 0 { return k }
    }
    return .hold
}

private func basePickShot(_ lineIndex: Int, _ seed: String?) -> DioramaShotKind {
    if lineIndex < 0 { return .hold }
    let u = seededUnit(dHashSeed(seed) + Double(lineIndex) * 101 + 7)
    return weightedPickShot(baseShotWeights(), u)
}

func getDioramaShot(_ lineIndex: Int, seed: String?) -> DioramaShotKind {
    let pick = basePickShot(lineIndex, seed)
    let prev1 = lineIndex > 0 ? basePickShot(lineIndex - 1, seed) : nil
    let prev2 = lineIndex > 1 ? basePickShot(lineIndex - 2, seed) : nil
    if pick == prev1 || pick == prev2 {
        let others = DioramaShotKind.allCases.filter { $0 != pick && $0 != prev1 && $0 != prev2 }
        let pool = others.isEmpty ? DioramaShotKind.allCases.filter { $0 != pick } : others
        let alt = seededUnit(dHashSeed(seed) + Double(lineIndex) * 53 + 19)
        return pool[Int(dclamp01(alt) * Double(pool.count)) % pool.count]
    }
    return pick
}

struct DioramaShotOffset {
    var right: Double
    var up: Double
    var back: Double
}

struct DioramaShotContext {
    var progress: Double
    var wordProgress: Double
    var hero: Double
    var lift: Double
    var seed: String?
    var lineIndex: Int
    var moveScale: Double
}

func resolveShotOffset(_ kind: DioramaShotKind, _ ctx: DioramaShotContext) -> DioramaShotOffset {
    let hero = ctx.hero, lift = ctx.lift
    let e = easeInOut(ctx.progress)
    let dir = getShotDir(ctx.lineIndex, ctx.seed)

    var right = 0.0
    var up = lift
    var back = hero

    switch kind {
    case .pushIn:
                back = hero * (1.5 - 0.8 * e)
        up = lift * (1.2 - 0.5 * e) + 0.15
    case .pullBack:
                back = hero * (0.85 + 1.15 * e)
        up = lift + 1.7 * e
    case .orbit:
                let theta = dir * 0.55 * (2 * e - 1)
        right = hero * sin(theta)
        back = hero * cos(theta)
        up = lift + 0.4
    case .track:
                right = dir * hero * 0.34 * sin(.pi * dclamp01(ctx.wordProgress))
        back = hero * 1.06
        up = lift + 0.12
    case .crane:
                let from = dir > 0 ? -1.5 : 2.4
        let to = dir > 0 ? 2.4 : -1.4
        up = dmix(from, to, e)
        back = hero * 1.05
    case .swell:
                let theta = dir * 0.4 * e
        right = hero * sin(theta) * 1.1
        back = hero * (1.0 + 0.35 * e)
        up = lift + 1.2 * e + 0.3
    case .spiral:
                let theta = dir * 0.7 * (2 * e - 1)
        right = hero * sin(theta) * 0.85
        back = hero * (1.05 - 0.1 * e)
        up = lift - 0.8 + 2.4 * e
    case .pendulum:
                right = dir * hero * 0.45 * (2 * e - 1)
        up = lift + 0.9 - 0.9 * sin(.pi * e)
        back = hero * 1.02
    case .flyby:
                right = dir * hero * (0.7 - 1.4 * e)
        back = hero * (0.78 + 0.12 * sin(.pi * e))
        up = lift + 0.05
    case .arc:
                let theta = dir * 0.5 * sin(.pi * e)
        right = hero * sin(theta) * 1.3
        back = hero * (1.05 + 0.12 * (1 - cos(theta)))
        up = lift + 0.5 * sin(.pi * e)
    case .float:
                right = dir * hero * 0.16 * sin(e * .pi * 2)
        up = lift + 0.6 + 0.5 * sin(e * .pi * 2 + 1.0)
        back = hero * (1.05 + 0.06 * sin(e * .pi))
    case .glide:
            right = dir * hero * 0.22 * e
        up = lift + 1.4 * e
        back = hero * (1.15 - 0.25 * e)
    case .hold:
                up = lift + 0.3 * sin(ctx.progress * .pi)
        back = hero
    }

        let m = ctx.moveScale
    return DioramaShotOffset(
        right: right * m,
        up: lift + (up - lift) * m,
        back: hero + (back - hero) * m
    )
}

private let HOLD_SETTLE_DELAY = 3.0
private let HOLD_SETTLE_EASE = 5.0

func resolveHoldSettle(_ secondsHeld: Double) -> Double {
    let t = dclamp01((secondsHeld - HOLD_SETTLE_DELAY) / HOLD_SETTLE_EASE)
    return 1 - dsmoothstep01(t)
}

struct DioramaCameraDrift {
    var swayX: Double
    var swayY: Double
    var lift: Double
    var dist: Double
}

func resolveCameraDrift(_ time: Double, _ seed: String?, _ scale: Double) -> DioramaCameraDrift {
    let ph = dHashSeed(seed) * 0.017
    return DioramaCameraDrift(
        swayX: (sin(time * 0.11 + ph) * 0.6 + sin(time * 0.047 + ph * 1.7) * 0.4) * DIORAMA_SWAY_AMP * scale,
        swayY: sin(time * 0.09 + ph * 0.7) * DIORAMA_SWAY_AMP * 0.5 * scale,
        lift: (sin(time * 0.13 + ph * 1.3) * 0.6 + sin(time * 0.061 + ph * 2.1) * 0.4) * DIORAMA_LIFT_AMP * scale,
        dist: sin(time * 0.05 + ph * 1.1) * DIORAMA_DIST_AMP * scale
    )
}

func resolveShapeLifeOpacity(_ distanceToCamera: Double) -> Double {
    let farT = dclamp01((DIORAMA_SHAPE_FADE_IN_END - distanceToCamera)
        / (DIORAMA_SHAPE_FADE_IN_END - DIORAMA_SHAPE_FADE_IN_START))
    let nearT = dclamp01((distanceToCamera - DIORAMA_SHAPE_DISSOLVE_END)
        / (DIORAMA_SHAPE_DISSOLVE_START - DIORAMA_SHAPE_DISSOLVE_END))
    return dsmoothstep01(farT) * dsmoothstep01(nearT)
}
