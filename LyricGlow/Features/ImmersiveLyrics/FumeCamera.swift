import CoreGraphics
import Foundation

struct FumeCamera {
    static let scaleMin: CGFloat = 0.22
    static let scaleMax: CGFloat = 2.24

    var x: CGFloat = 0
    var y: CGFloat = 0
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var focusX: CGFloat = 0
    var focusY: CGFloat = 0
    var scale: CGFloat = 1
    var vScale: CGFloat = 0
    var focusScale: CGFloat = 1

    private var initialized = false
    private var retargetSource: Int = .min
    private var retargetStartedAt: Double = 0
    private var retargetDuration: Double = 0.18
    private var fromX: CGFloat = 0
    private var fromY: CGFloat = 0
    private var fromScale: CGFloat = 1
    private var bridgeDirect = false

        mutating func sync(to article: FumeArticle) {
        if !initialized {
            x = article.width * 0.5
            y = article.height * 0.5
            focusX = x
            focusY = y
            scale = 1.18
            focusScale = 1.18
            vx = 0
            vy = 0
            vScale = 0
            retargetSource = .min
            initialized = true
        } else {
            x = min(max(x, 0), article.width)
            y = min(max(y, 0), article.height)
            focusX = min(max(focusX, 0), article.width)
            focusY = min(max(focusY, 0), article.height)
            scale = min(max(scale, Self.scaleMin), Self.scaleMax)
            focusScale = min(max(focusScale, Self.scaleMin), Self.scaleMax)
        }
    }

            mutating func snap(article: FumeArticle, time: Double, viewport: CGSize) {
        guard let focusBlock = Self.resolveFocusBlock(article: article, lineIndex: nil, time: time) else { return }
        let progress = Self.printedGraphemeProgress(block: focusBlock, time: time)
        let point = Self.smoothFocusPoint(block: focusBlock, printedProgress: progress)
        let targetScale = Self.scaleFor(block: focusBlock, viewport: viewport)
        x = point.x
        y = point.y
        focusX = x
        focusY = y
        scale = targetScale
        focusScale = targetScale
        vx = 0
        vy = 0
        vScale = 0
        retargetSource = focusBlock.id
                retargetStartedAt = time - 0.09
        retargetDuration = 0.09
        fromX = x
        fromY = y
        fromScale = scale
        bridgeDirect = false
    }

        mutating func step(
        article: FumeArticle,
        time: Double,
        now: Double,
        dt: Double,
        lineIndex: Int?,
        viewport: CGSize
    ) {
        guard dt > 0 else { return }
        let minViewport = max(min(viewport.width, viewport.height), 1)

        var targetX = article.width * 0.5
        var targetY = article.height * 0.5
        var targetScale: CGFloat = 1.18
        var entryPoint: CGPoint?

        if let focusBlock = Self.resolveFocusBlock(article: article, lineIndex: lineIndex, time: time) {
            let progress = Self.printedGraphemeProgress(block: focusBlock, time: time)
            let point = Self.smoothFocusPoint(block: focusBlock, printedProgress: progress)
            entryPoint = Self.entryFocusPoint(block: focusBlock)
            targetX = point.x
            targetY = point.y
            targetScale = Self.scaleFor(block: focusBlock, viewport: viewport)

            if retargetSource != focusBlock.id {
                retargetSource = focusBlock.id
                retargetStartedAt = time
                retargetDuration = 0.09
                fromX = x
                fromY = y
                fromScale = scale

                                let bridgeScale = max(scale, targetScale, 0.001)
                let screenDistance = hypot((targetX - fromX) * bridgeScale, (targetY - fromY) * bridgeScale)
                bridgeDirect = screenDistance >= minViewport * 0.42
            }
        } else if retargetSource != -1 {
            retargetSource = -1
            retargetStartedAt = time
            retargetDuration = min(max(0.18, 0.05), 0.4)
            fromX = x
            fromY = y
            fromScale = scale
            bridgeDirect = false
        }

        let elapsed = max(time - retargetStartedAt, 0)
        let phase = min(max(elapsed / max(retargetDuration, 0.001), 0), 1)
        let boost = 1 - Self.easeOutCubic(phase)
        let entryBias = pow(boost, 0.58)

        if let entryPoint {
            targetX = Self.mix(targetX, entryPoint.x, entryBias)
            targetY = Self.mix(targetY, entryPoint.y, entryBias)
        }

                let floatPhase = (now / 7.0) * .pi * 2
        let floatX = sin(floatPhase * 0.74 + 0.8) * 18 * 0.34
        let floatY = sin(floatPhase) * 18 + sin(floatPhase * 0.5 + 1.1) * 18 * 0.22
        let floatDivisor = max(targetScale, 0.001)
        targetX -= floatX / floatDivisor
        targetY -= floatY / floatDivisor
        targetScale = min(max(
            targetScale * (1 + sin(floatPhase + 0.9) * 0.011),
            Self.scaleMin
        ), Self.scaleMax)

        let cameraDistance = hypot(targetX - x, targetY - y)

        if bridgeDirect && phase < 1 {
            let b = Self.easeInOutCubic(phase)
            let bridgedX = Self.mix(fromX, targetX, b)
            let bridgedY = Self.mix(fromY, targetY, b)
            let bridgedScale = Self.mix(fromScale, targetScale, b)
            let catchUp = CGFloat(1 - exp(-dt * Self.mix(10.5, 17.5, 1 - phase)))
            focusX = bridgedX
            focusY = bridgedY
            focusScale = bridgedScale
            x += (bridgedX - x) * catchUp
            y += (bridgedY - y) * catchUp
            scale += (bridgedScale - scale) * catchUp
            scale = min(max(scale, Self.scaleMin), Self.scaleMax)
            vx *= 0.72
            vy *= 0.72
            vScale *= 0.68
        } else {
            let boostedCatchUpRate = min(max(4.8 / max(retargetDuration, 0.05), 20), 54)
            let targetCatchUp = CGFloat(1 - exp(-dt * Self.mix(11.2, boostedCatchUpRate, boost)))
            focusX += (targetX - focusX) * targetCatchUp
            focusY += (targetY - focusY) * targetCatchUp
            focusScale += (targetScale - focusScale) * CGFloat(1 - exp(-dt * Self.mix(5.4, 12.8, boost)))

            let springStrength = Self.mix(208, min(max(15.8 / max(retargetDuration * retargetDuration, 0.0064), 260), 780), boost)
            let damping = Self.mix(24, min(max(springStrength.squareRoot() * 1.36, 24), 40), boost)
            let dtf = CGFloat(dt)
            let accelX = (focusX - x) * springStrength - vx * damping
            let accelY = (focusY - y) * springStrength - vy * damping
            vx += accelX * dtf
            vy += accelY * dtf
            let maxVelocity = Self.mix(1320, min(max(cameraDistance / max(CGFloat(retargetDuration) * 0.28, 0.028), 2600), 8800), boost)
            vx = min(max(vx, -maxVelocity), maxVelocity)
            vy = min(max(vy, -maxVelocity), maxVelocity)
            x += vx * dtf
            y += vy * dtf

            let scaleSpringStrength = Self.mix(54, 108, boost)
            let scaleDamping = Self.mix(13.5, 21, boost)
            let accelScale = (focusScale - scale) * scaleSpringStrength - vScale * scaleDamping
            vScale += accelScale * dtf
            vScale = min(max(vScale, -1.6), 1.6)
            scale += vScale * dtf
            scale = min(max(scale, Self.scaleMin), Self.scaleMax)
        }
    }

        static func scaleFor(block: FumeBlock, viewport: CGSize) -> CGFloat {
        let minViewportSide = max(min(viewport.width, viewport.height), 1)
        let targetLineHeight = min(max(minViewportSide * 0.115, 64), 124)
        return min(max(targetLineHeight / max(block.lineHeight, 1), 0.88), 2.2)
    }

        static func resolveFocusBlock(article: FumeArticle, lineIndex: Int?, time: Double) -> FumeBlock? {
        if let lineIndex, let block = article.blockBySourceLine[lineIndex] {
            return block
        }
        for block in article.chronologicalBlocks.reversed() {
            if printedGraphemeProgress(block: block, time: time) > 0 {
                return block
            }
        }
        return article.chronologicalBlocks.first
    }

        static func printedGraphemeProgress(block: FumeBlock, time: Double) -> Double {
        let words = block.line.words
        guard !words.isEmpty else { return 0 }
        var accumulated = 0.0
        for word in words {
            let count = Double(Array(word.text).count)
            if time < word.start {
                return accumulated
            }
            if time <= word.end {
                let p = word.end > word.start ? (time - word.start) / (word.end - word.start) : 1
                return accumulated + count * min(max(p, 0), 1)
            }
            accumulated += count
        }
        return accumulated
    }

        static func smoothFocusPoint(block: FumeBlock, printedProgress: Double) -> CGPoint {
        guard !block.renderLines.isEmpty else { return block.center }
        let total = Double(block.renderLines.last?.end ?? 0)
        let offset = min(max(printedProgress, 0), total)

        func lineIndex(for offset: Double) -> Int {
            for (i, line) in block.renderLines.enumerated() where offset <= Double(line.end) {
                return i
            }
            return block.renderLines.count - 1
        }

        func pointOnLine(_ index: Int, offset: Double) -> CGPoint {
            let line = block.renderLines[min(max(index, 0), block.renderLines.count - 1)]
            let clamped = min(max(offset, Double(line.start)), Double(line.end))
            let base = Int(clamped.rounded(.down))
            let frac = CGFloat(clamped - Double(base))
            let local = min(max(base - line.start, 0), max(line.end - line.start, 0))
            let baseWidth = line.advances[min(local, line.advances.count - 1)]
            let glyphAdvance = local < line.end - line.start
                ? line.advances[min(local + 1, line.advances.count - 1)] - line.advances[local]
                : 0
            let minX = block.x + line.left
            let maxX = minX + line.width
            return CGPoint(
                x: min(max(minX + baseWidth + glyphAdvance * frac, minX), maxX),
                y: block.y + line.top + block.lineHeight * 0.5
            )
        }

        let index = lineIndex(for: offset)
        var point = pointOnLine(index, offset: offset)
        let current = block.renderLines[index]
        let blendWindow = 0.7

        if index > 0 && offset < Double(current.start) + blendWindow {
            let previous = block.renderLines[index - 1]
            let blend = easeInOutCubic(min(max(1 - (offset - Double(previous.end)) / blendWindow, 0), 1))
            let previousPoint = pointOnLine(index - 1, offset: Double(previous.end))
            point = CGPoint(x: mix(point.x, previousPoint.x, blend), y: mix(point.y, previousPoint.y, blend))
        } else if index < block.renderLines.count - 1 && offset > Double(current.end) - blendWindow {
            let next = block.renderLines[index + 1]
            let blend = easeInOutCubic(min(max((offset - (Double(current.end) - blendWindow)) / blendWindow, 0), 1))
            let nextPoint = pointOnLine(index + 1, offset: Double(next.start))
            point = CGPoint(x: mix(point.x, nextPoint.x, blend), y: mix(point.y, nextPoint.y, blend))
        }
        return point
    }

        static func entryFocusPoint(block: FumeBlock) -> CGPoint {
        guard let first = block.renderLines.first else { return block.center }
        return CGPoint(x: block.x + first.left, y: block.y + first.top + block.lineHeight * 0.5)
    }

    struct BackgroundView {
        var cameraX: CGFloat
        var cameraY: CGFloat
        var scale: CGFloat
        var centerX: CGFloat
        var centerY: CGFloat
    }

        func backgroundView(worldSize: CGSize, viewport: CGSize) -> BackgroundView {
        let centerX = worldSize.width * 0.5
        let centerY = worldSize.height * 0.5
        let verticalOffset = min(max(viewport.height * 0.22 / max(scale, 0.001), 48), 180)
        return BackgroundView(
            cameraX: Self.mix(centerX, x, 0.9),
            cameraY: Self.mix(centerY, y, 0.74) - verticalOffset,
            scale: min(max(scale * 0.94, Self.scaleMin), Self.scaleMax),
            centerX: centerX,
            centerY: centerY
        )
    }

    private static func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private static func easeOutCubic(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    private static func easeInOutCubic(_ t: Double) -> Double {
        let c = min(max(t, 0), 1)
        return c < 0.5 ? 4 * c * c * c : 1 - pow(-2 * c + 2, 3) / 2
    }
}
