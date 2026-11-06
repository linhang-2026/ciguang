import simd

private let alignShotCeiling: [DioramaShotKind: Double] = [
    .hold: 0.9, .pushIn: 0.85, .track: 0.85, .swell: 0.8, .float: 0.78, .glide: 0.72,
    .crane: 0.7, .pullBack: 0.7, .arc: 0.62, .pendulum: 0.6, .orbit: 0.55, .spiral: 0.5, .flyby: 0.5,
]
private let ALIGN_LEAD_IN = 0.6
private let ALIGN_SETTLE = 0.35
private let ALIGN_RELEASE = 1.0
private let ALIGN_RATE = 1.2
private let ALIGN_TURN_RATE = 2.6
private let FRAME_KEEP_FRACTION = 0.7
private let LANDSCAPE_REF_ASPECT = 1.78
private let ORIENT_FOLLOW_RATE = 4.2

final class DioramaCamera {
        private var pos = SIMD3<Double>(0, 0.6, 9)
    private var posVel = SIMD3<Double>.zero
    private var look = SIMD3<Double>(0, 0, -10)
    private var lookVel = SIMD3<Double>.zero
        private var alignWeight = 0.0
        private var alignQuat = simd_quatd(vector: SIMD4(0, 0, 0, 1))
    private var alignInit = false
        private var orientQuat = simd_quatd(vector: SIMD4(0, 0, 0, 1))
    private var orientInit = false

        var activeLineWidth: Double = 0

        private(set) var camPos = SIMD3<Double>(0, 0.6, 9)
    private(set) var camQuat = simd_quatd(vector: SIMD4(0, 0, 0, 1))

            static func wordProgress(of line: LyricLine, at now: Double) -> Double {
        let timeline = line.words
        if timeline.isEmpty { return 0 }
        let renderEnd = dioramaRenderEnd(line)
        if now >= renderEnd { return 1 }
        if now <= line.start { return 0 }
        var revealed = 0.0
        for (i, w) in timeline.enumerated() {
            if now >= w.end {
                revealed = Double(i + 1)
            } else if now >= w.start {
                let span = max(w.end - w.start, 0.001)
                revealed = Double(i) + dclamp01((now - w.start) / span)
                break
            } else {
                break
            }
        }
        return revealed / Double(timeline.count)
    }

        func step(now: Double, delta: Double, frame: DioramaFrame, line: LyricLine?, lineIndex: Int,
              seed: String?, motion: DioramaMotionParams, fovDeg: Double, aspect: Double) {
                let latScale = min(1, aspect / LANDSCAPE_REF_ASPECT)
                let wordProg = line.map { Self.wordProgress(of: $0, at: now) } ?? 0
        var progress = 0.0
        if let line {
            let renderEnd = dioramaRenderEnd(line)
            let span = renderEnd - line.start
            progress = span > 0 ? dclamp01((now - line.start) / span) : (now >= line.start ? 1 : 0)
        }
        let settle = line.map { resolveHoldSettle(now - dioramaRenderEnd($0)) } ?? 1

        let visibleHalf = frameHalfWidth(DIORAMA_HERO_DISTANCE, fovDeg, aspect) * DIORAMA_SAFE_FRAME_FRACTION

                let placement = getDioramaTextPlacement(lineIndex, seed: seed, weave: motion.weaveScale)
                                                let followFloor = 1.2 * (1 - latScale)
        let effectiveVisible = max(visibleHalf, activeLineWidth / 2 + followFloor)
        let truck = resolveReadHeadTruck(wordProg, activeLineWidth, effectiveVisible) * settle
        let headR = placement.offsetR + truck
        let headU = placement.offsetU
        let R = frame.right, U = frame.up, F = frame.forward
        let base = frame.position + R * headR + U * headU

                let shotKind = getDioramaShot(lineIndex, seed: seed)
        let shot = resolveShotOffset(shotKind, DioramaShotContext(
            progress: progress, wordProgress: wordProg,
            hero: DIORAMA_HERO_DISTANCE, lift: DIORAMA_CAMERA_LIFT,
            seed: seed, lineIndex: lineIndex,
            moveScale: motion.moveScale * settle
        ))
        let drift = resolveCameraDrift(now, seed, motion.driftScale)
        let offRight = shot.right + drift.swayX * latScale
        let offUp = shot.up + drift.swayY + drift.lift
        let offBack = shot.back + drift.dist
        let pose = base + R * offRight + U * offUp - F * offBack

                let snapped = distance(pose, pos) > DIORAMA_SNAP_DISTANCE
        if snapped {
            pos = pose
            posVel = .zero
        } else {
            let sx = smoothDamp(pos.x, pose.x, posVel.x, motion.smoothTime, delta)
            let sy = smoothDamp(pos.y, pose.y, posVel.y, motion.smoothTime, delta)
            let sz = smoothDamp(pos.z, pose.z, posVel.z, motion.smoothTime, delta)
            pos = SIMD3(sx.value, sy.value, sz.value)
            posVel = SIMD3(sx.velocity, sy.velocity, sz.velocity)
        }
        camPos = pos

                let lookOff = placement.lookR * latScale * settle
        let lookTarget = base + R * lookOff
        if snapped || distance(lookTarget, look) > DIORAMA_SNAP_DISTANCE {
            look = lookTarget
            lookVel = .zero
        } else {
            let lx = smoothDamp(look.x, lookTarget.x, lookVel.x, motion.smoothTime, delta)
            let ly = smoothDamp(look.y, lookTarget.y, lookVel.y, motion.smoothTime, delta)
            let lz = smoothDamp(look.z, lookTarget.z, lookVel.z, motion.smoothTime, delta)
            look = SIMD3(lx.value, ly.value, lz.value)
            lookVel = SIMD3(lx.velocity, ly.velocity, lz.velocity)
        }

                        let lookQuat: simd_quatd
        do {
            let zAxis = simd_normalize(pos - look)
            let xAxis = simd_normalize(simd_cross(SIMD3<Double>(0, 1, 0), zAxis))
            let yAxis = simd_cross(zAxis, xAxis)
            lookQuat = quatFromRotationMatrix(simd_double3x3(columns: (xAxis, yAxis, zAxis)))
        }

                let alignTarget = frameQuaternion(frame, roll: placement.roll, yaw: placement.yaw)
        if snapped || !alignInit {
            alignQuat = alignTarget
            alignInit = true
        } else {
            alignQuat = simd_slerp(alignQuat, alignTarget, 1 - exp(-ALIGN_TURN_RATE * delta))
        }

                var readTarget = 0.0
        if let line {
            let renderEnd = dioramaRenderEnd(line)
            let rampIn = dsmoothstep01((now - (line.start - ALIGN_LEAD_IN)) / (ALIGN_LEAD_IN + ALIGN_SETTLE))
            let rampOut = 1 - dsmoothstep01((now - renderEnd) / ALIGN_RELEASE)
            readTarget = min(rampIn, rampOut) * (alignShotCeiling[shotKind] ?? 0.7)
        }
        alignWeight += (readTarget - alignWeight) * (1 - exp(-ALIGN_RATE * delta))

                var target = simd_slerp(lookQuat, alignQuat, alignWeight)

                                                let viewDir = simd_normalize(look - pos)
        let camForward = target.act(SIMD3<Double>(0, 0, -1))
        let cosA = dclamp01(dot(simd_normalize(camForward), viewDir))
        let offAxisAngle = acos(cosA)
        let halfV = fovDeg * .pi / 180 / 2
        let halfH = atan(tan(halfV) * aspect)
        let keepNDC = tan(halfV * FRAME_KEEP_FRACTION) / (tan(halfV) * LANDSCAPE_REF_ASPECT)
        let maxOffAxis = min(halfV * FRAME_KEEP_FRACTION, atan(tan(halfH) * keepNDC))
        if offAxisAngle > maxOffAxis && offAxisAngle > 0.001 {
            target = simd_slerp(target, lookQuat, 1 - maxOffAxis / offAxisAngle)
        }

                if snapped || !orientInit {
            orientQuat = target
            orientInit = true
        } else {
            orientQuat = simd_slerp(orientQuat, target, 1 - exp(-ORIENT_FOLLOW_RATE * delta))
        }
        camQuat = orientQuat
    }

        func reset() {
        pos = SIMD3(0, 0.6, 9)
        posVel = .zero
        look = SIMD3(0, 0, -10)
        lookVel = .zero
        alignWeight = 0
        alignQuat = simd_quatd(vector: SIMD4(0, 0, 0, 1))
        orientQuat = simd_quatd(vector: SIMD4(0, 0, 0, 1))
        alignInit = false
        orientInit = false
        activeLineWidth = 0
    }
}
