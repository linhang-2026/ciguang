import Accelerate
import AVFoundation
import Foundation

final class AudioSpectrumAnalyzer: @unchecked Sendable {

    struct Bands: Sendable {
        var power: Double = 0
        var bass: Double = 0
        var lowMid: Double = 0
        var mid: Double = 0
        var vocal: Double = 0
        var treble: Double = 0
                var hasSignal: Bool = false
    }

    private let lock = NSLock()
    private var bands = Bands()
        private var smoothedBins = [Float](repeating: 0, count: AudioSpectrumAnalyzer.binCount)
    private let fftSetup: OpaquePointer
    private let window: [Float]

    private static let fftSize = 2048
    private static let binCount = fftSize / 2
        private static let minDb: Float = -100
    private static let maxDb: Float = -30
    private static let smoothing: Float = 0.8

    init() {
        let n = Self.fftSize
                window = (0..<n).map { i in
            let k = Float(i) / Float(n - 1)
            return 0.42 - 0.5 * cos(2 * .pi * k) + 0.08 * cos(4 * .pi * k)
        }
        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(n))), FFTRadix(kFFTRadix2))!
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

        func attach(engine: AVAudioEngine) {
        let mixer = engine.mainMixerNode
        mixer.removeTap(onBus: 0)
        mixer.installTap(onBus: 0, bufferSize: AVAudioFrameCount(Self.fftSize), format: nil) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }
    }

    func snapshot() -> Bands {
        lock.lock(); defer { lock.unlock() }
        return bands
    }

    private func process(buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let n = Self.fftSize

                var mono = [Float](repeating: 0, count: n)
        let channels = Int(buffer.format.channelCount)
        if let ptr = buffer.floatChannelData {
            let usable = min(frames, n)
            for ch in 0..<channels {
                vDSP_vadd(mono, 1, ptr[ch], 1, &mono, 1, vDSP_Length(usable))
            }
            if channels > 1 {
                var scale = 1 / Float(channels)
                vDSP_vsmul(mono, 1, &scale, &mono, 1, vDSP_Length(usable))
            }
        }

                var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(mono, 1, window, 1, &windowed, 1, vDSP_Length(n))

                var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)
        let log2n = vDSP_Length(log2(Float(n)))
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { mp in
                    mp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                var scale = Float(1.0 / Float(n))
                vDSP_vsmul(rp.baseAddress!, 1, &scale, rp.baseAddress!, 1, vDSP_Length(n / 2))
                vDSP_vsmul(ip.baseAddress!, 1, &scale, ip.baseAddress!, 1, vDSP_Length(n / 2))
            }
        }

                let sr = buffer.format.sampleRate
        let binHz = sr / Double(n)
        var rawBins = [Double](repeating: 0, count: Self.binCount)
        var hasSignal = false
        for i in 0..<Self.binCount {
                        let re = real[i]
            let im = i == 0 ? 0 : imag[i]
            let mag = sqrt(re * re + im * im)
            let db: Float = 20 * log10(max(mag, 1e-10))
            var v = 255 * (db - Self.minDb) / (Self.maxDb - Self.minDb)
            v = min(max(v, 0), 255)
            smoothedBins[i] = Self.smoothing * smoothedBins[i] + (1 - Self.smoothing) * v
            rawBins[i] = Double(smoothedBins[i])
            if rawBins[i] > 2 { hasSignal = true }
        }

        func energy(_ minHz: Double, _ maxHz: Double) -> Double {
            let start = Int(minHz / binHz)
            let end = Int(maxHz / binHz)
            guard end >= start, start < Self.binCount else { return 0 }
            let lo = max(start, 0), hi = min(end, Self.binCount - 1)
            var sum: Double = 0
            for i in lo...hi { sum += rawBins[i] }
            return sum / Double(hi - lo + 1)
        }

        let bass = energy(20, 150)
        let lowMid = energy(150, 400)
        let mid = energy(400, 1200)
        let vocal = energy(1000, 3500)
        let treble = energy(3500, 12000)

                func boost(_ v: Double, _ b: Double) -> Double { pow(v / 255, b) * 255 }

        let out = Bands(
            power: boost((bass + lowMid) / 2, 3),
            bass: boost(bass, 1.8),
            lowMid: boost(lowMid, 2),
            mid: boost(mid, 2),
            vocal: boost(vocal, 1.5),
            treble: boost(treble, 2),
            hasSignal: hasSignal
        )
        lock.lock()
        bands = out
        lock.unlock()
    }
}
