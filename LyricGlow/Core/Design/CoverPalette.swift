import UIKit

enum CoverPalette {

    struct RGB {
        var r: Double
        var g: Double
        var b: Double

        var float4: SIMD4<Float> {
            SIMD4(Float(r / 255), Float(g / 255), Float(b / 255), 1)
        }
    }

    private struct Weighted {
        var r: Double
        var g: Double
        var b: Double
        var weight: Double
    }

    private struct Bucket {
        var colors: [Weighted]
        var weight: Double
    }

    private static let quantShift = 4
    private static let minAlpha = 128

        static func representativeColors(from data: Data?, count: Int = 6) -> [RGB] {
        guard count > 0, let data, let image = UIImage(data: data), let cg = image.cgImage else {
            return []
        }

                let size = 50
        guard let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let px = ctx.data else { return [] }
        let pixels = px.bindMemory(to: UInt8.self, capacity: size * size * 4)

                var histogram: [Int: Weighted] = [:]
        for i in 0..<(size * size) {
            let off = i * 4
            let a = Int(pixels[off + 3])
            if a < minAlpha { continue }
            let r = Int(pixels[off])
            let g = Int(pixels[off + 1])
            let b = Int(pixels[off + 2])
            let key = ((r >> quantShift) << 8) | ((g >> quantShift) << 4) | (b >> quantShift)
            if var e = histogram[key] {
                e.r += Double(r); e.g += Double(g); e.b += Double(b); e.weight += 1
                histogram[key] = e
            } else {
                histogram[key] = Weighted(r: Double(r), g: Double(g), b: Double(b), weight: 1)
            }
        }

        let colors = histogram.values.map { c in
            Weighted(r: (c.r / c.weight).rounded(), g: (c.g / c.weight).rounded(), b: (c.b / c.weight).rounded(), weight: c.weight)
        }
        guard !colors.isEmpty else { return [] }

        func channelRange(_ cs: [Weighted], _ keyPath: KeyPath<Weighted, Double>) -> Double {
            var lo = Double.greatestFiniteMagnitude
            var hi = -Double.greatestFiniteMagnitude
            for c in cs {
                lo = min(lo, c[keyPath: keyPath])
                hi = max(hi, c[keyPath: keyPath])
            }
            return hi - lo
        }

        func splitBucket(_ bucket: Bucket) -> (Bucket, Bucket)? {
            guard bucket.colors.count >= 2 else { return nil }
            let ranges = (
                r: channelRange(bucket.colors, \.r),
                g: channelRange(bucket.colors, \.g),
                b: channelRange(bucket.colors, \.b)
            )
                        let channel: KeyPath<Weighted, Double> = {
                var best = \Weighted.r
                var bestRange = ranges.r
                if ranges.g > bestRange { best = \Weighted.g; bestRange = ranges.g }
                if ranges.b > bestRange { best = \Weighted.b }
                return best
            }()
            let sorted = bucket.colors.sorted { $0[keyPath: channel] < $1[keyPath: channel] }
            let midpoint = bucket.weight / 2
            var accumulated: Double = 0
            var splitIndex = 1
            for i in 0..<(sorted.count - 1) {
                accumulated += sorted[i].weight
                splitIndex = i + 1
                if accumulated >= midpoint { break }
            }
            let left = Array(sorted[0..<splitIndex])
            let right = Array(sorted[splitIndex...])
            return (
                Bucket(colors: left, weight: left.reduce(0) { $0 + $1.weight }),
                Bucket(colors: right, weight: right.reduce(0) { $0 + $1.weight })
            )
        }

        var buckets = [Bucket(colors: colors, weight: colors.reduce(0) { $0 + $1.weight })]
        while buckets.count < min(count, colors.count) {
            var bucketIndex = -1
            var bestScore = -1.0
            for (i, bucket) in buckets.enumerated() {
                guard bucket.colors.count >= 2 else { continue }
                let widest = max(channelRange(bucket.colors, \.r),
                                 channelRange(bucket.colors, \.g),
                                 channelRange(bucket.colors, \.b))
                let score = widest * sqrt(bucket.weight)
                if score > bestScore {
                    bestScore = score
                    bucketIndex = i
                }
            }
            guard bucketIndex >= 0, let split = splitBucket(buckets[bucketIndex]) else { break }
            buckets.replaceSubrange(bucketIndex...bucketIndex, with: [split.0, split.1])
        }

        func average(_ bucket: Bucket) -> Weighted {
            var r = 0.0, g = 0.0, b = 0.0
            for c in bucket.colors {
                r += c.r * c.weight
                g += c.g * c.weight
                b += c.b * c.weight
            }
            return Weighted(r: (r / bucket.weight).rounded(),
                            g: (g / bucket.weight).rounded(),
                            b: (b / bucket.weight).rounded(),
                            weight: bucket.weight)
        }

        return buckets
            .map(average)
            .sorted { $0.weight > $1.weight }
            .map { RGB(r: $0.r, g: $0.g, b: $0.b) }
    }
}
