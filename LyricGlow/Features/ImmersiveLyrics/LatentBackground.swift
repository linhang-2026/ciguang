import MetalKit
import SwiftUI

private let latentShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VOut {
    float4 position [[position]];
    float2 uv;
};

vertex VOut latent_vertex_nsc(uint vid [[vertex_id]]) {
    float2 pos = float2(float(vid & 1) * 2.0 - 1.0, float(vid >> 1) * 2.0 - 1.0);
    VOut out;
    out.position = float4(pos, 0, 1);
    out.uv = pos * 0.5;
    return out;
}

vertex VOut latent_vertex_uv01(uint vid [[vertex_id]]) {
    float2 pos = float2(float(vid & 1) * 2.0 - 1.0, float(vid >> 1) * 2.0 - 1.0);
    VOut out;
    out.position = float4(pos, 0, 1);
    out.uv = pos * 0.5 + 0.5;
    return out;
}

struct MeshUniforms {
    float2 res;
    float time;
    float colorsCount;
    float distortion;
    float swirl;
    float grainMixer;
    float grainOverlay;
    float4 colors[10];
};

float2 rot(float2 uv, float th) {
    float s = sin(th), c = cos(th);
    return float2(c * uv.x - s * uv.y, s * uv.x + c * uv.y);
}

float hash21(float2 p) {
    p = fract(p * float2(0.3183099, 0.3678794)) + 0.1;
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

float valueNoise(float2 st) {
    float2 i = floor(st);
    float2 f = fract(st);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    float x1 = mix(a, b, u.x);
    float x2 = mix(c, d, u.x);
    return mix(x1, x2, u.y);
}

float2 getPosition(int i, float t) {
    float a = float(i) * 0.37;
    float b = 0.6 + fract(float(i) / 3.0) * 0.9;
    float c = 0.8 + fract(float(i + 1) / 4.0);

    float x = sin(t * b + a);
    float y = cos(t * c + a * 1.5);

    return 0.5 + 0.5 * float2(x, y);
}

fragment float4 latent_mesh_fragment(VOut in [[stage_in]],
                                     constant MeshUniforms &u [[buffer(0)]]) {

    float2 uv = in.uv * (u.res / min(u.res.x, u.res.y));
    uv += 0.5;
    float2 grainUV = uv * 1000.0;

    float grain = valueNoise(grainUV);
    float mixerGrain = 0.4 * u.grainMixer * (grain - 0.5);

    const float firstFrameOffset = 41.5;
    float t = 0.5 * (u.time + firstFrameOffset);

    float radius = smoothstep(0.0, 1.0, length(uv - 0.5));
    float center = 1.0 - radius;
    for (float i = 1.0; i <= 2.0; i++) {
        uv.x += u.distortion * center / i * sin(t + i * 0.4 * smoothstep(0.0, 1.0, uv.y)) * cos(0.2 * t + i * 2.4 * smoothstep(0.0, 1.0, uv.y));
        uv.y += u.distortion * center / i * cos(t + i * 2.0 * smoothstep(0.0, 1.0, uv.x));
    }

    float2 uvRotated = uv - 0.5;
    float angle = 3.0 * u.swirl * radius;
    uvRotated = rot(uvRotated, -angle);
    uvRotated += 0.5;

    float3 color = float3(0.0);
    float opacity = 0.0;
    float totalWeight = 0.0;

    for (int i = 0; i < 10; i++) {
        if (i >= int(u.colorsCount)) break;

        float2 pos = getPosition(i, t) + mixerGrain;
        float3 colorFraction = u.colors[i].rgb * u.colors[i].a;
        float opacityFraction = u.colors[i].a;

        float dist = length(uvRotated - pos);
        dist = pow(dist, 3.5);
        float weight = 1.0 / (dist + 1e-3);
        color += colorFraction * weight;
        opacity += opacityFraction * weight;
        totalWeight += weight;
    }

    color /= max(1e-4, totalWeight);
    opacity /= max(1e-4, totalWeight);

    float grainOverlay = valueNoise(rot(grainUV, 1.0) + float2(3.0));
    grainOverlay = mix(grainOverlay, valueNoise(rot(grainUV, 2.0) + float2(-1.0)), 0.5);
    grainOverlay = pow(grainOverlay, 1.3);

    float grainOverlayV = grainOverlay * 2.0 - 1.0;
    float3 grainOverlayColor = float3(step(0.0, grainOverlayV));
    float grainOverlayStrength = u.grainOverlay * abs(grainOverlayV);
    grainOverlayStrength = pow(grainOverlayStrength, 0.8);
    color = mix(color, grainOverlayColor, 0.35 * grainOverlayStrength);

    opacity += 0.5 * grainOverlayStrength;
    opacity = clamp(opacity, 0.0, 1.0);

    return float4(color, opacity);
}

struct DitherUniforms {
    float2 res;
    float time;
    float pixelRatio;
    float pxSize;
    float4 colorBack;
    float4 colorFront;
};

constant int bayer4x4[16] = {
    0, 8, 2, 10,
    12, 4, 14, 6,
    3, 11, 1, 9,
    15, 7, 13, 5
};

fragment float4 latent_dither_fragment(VOut in [[stage_in]],
                                       constant DitherUniforms &u [[buffer(0)]]) {
    float t = 0.5 * u.time;

    float2 fragCoord = float2(in.position.x, u.res.y - in.position.y);
    float pxSize = u.pxSize * u.pixelRatio;
    float2 pxSizeUV = fragCoord - 0.5 * u.res;
    pxSizeUV /= pxSize;
    float2 canvasPixelizedUV = (floor(pxSizeUV) + 0.5) * pxSize;
    float2 normalizedUV = canvasPixelizedUV / u.res;

    float2 shapeUV = normalizedUV * u.res / u.pixelRatio + 0.5;

    shapeUV *= 0.003;
    for (float i = 1.0; i < 6.0; i++) {
        shapeUV.x += 0.6 / i * cos(i * 2.5 * shapeUV.y + t);
        shapeUV.y += 0.6 / i * cos(i * 1.5 * shapeUV.x + t);
    }
    float shape = 0.15 / max(0.001, abs(sin(t - shapeUV.y - shapeUV.x)));
    shape = smoothstep(0.02, 1.0, shape);

    int2 bp = int2(fract(pxSizeUV / 4.0) * 4.0);
    int index = clamp(bp.y * 4 + bp.x, 0, 15);
    float dithering = float(bayer4x4[index]) / 16.0;

    dithering -= 0.5;
    float res = step(0.5, shape + dithering);

    float3 fgColor = u.colorFront.rgb * u.colorFront.a;
    float fgOpacity = u.colorFront.a;
    float3 bgColor = u.colorBack.rgb * u.colorBack.a;
    float bgOpacity = u.colorBack.a;

    float3 color = fgColor * res;
    float opacity = fgOpacity * res;

    color += bgColor * (1.0 - opacity);
    opacity += bgOpacity * (1.0 - opacity);

    return float4(color, opacity);
}

struct CompositeUniforms {
    float2 res;
    float4 bgColor;
    float4 overlayColor;
    float meshScale;
    float meshSaturate;
    float meshBrightness;
    float ditherOpacity;
    float ditherScale;
};

float3 softLight(float3 cb, float3 cs) {
    float3 d;
    for (int i = 0; i < 3; i++) {
        float x = cb[i];
        float dx = (x <= 0.25) ? ((16.0 * x - 12.0) * x + 4.0) * x : sqrt(x);
        d[i] = (cs[i] <= 0.5)
            ? x - (1.0 - 2.0 * cs[i]) * x * (1.0 - x)
            : x + (2.0 * cs[i] - 1.0) * (dx - x);
    }
    return d;
}

fragment float4 latent_composite_fragment(VOut in [[stage_in]],
                                          constant CompositeUniforms &u [[buffer(0)]],
                                          texture2d<float> meshTex [[texture(0)]],
                                          texture2d<float> ditherTex [[texture(1)]],
                                          sampler samp [[sampler(0)]]) {

    float2 uvM = (in.uv - 0.5) / u.meshScale + 0.5;
    float4 m = meshTex.sample(samp, uvM);
    float3 rgb = m.a > 0.0 ? m.rgb / m.a : float3(0.0);
    float lum = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    rgb = lum + (rgb - lum) * u.meshSaturate;
    rgb *= u.meshBrightness;
    float3 meshRGB = rgb * m.a;

    float3 outC = meshRGB + (1.0 - m.a) * u.bgColor.rgb;

    float2 uvD = (in.uv - 0.5) / u.ditherScale + 0.5;
    float4 d = ditherTex.sample(samp, uvD);
    float alphaS = d.a * u.ditherOpacity;
    float3 dsrc = d.a > 0.0 ? d.rgb / d.a : d.rgb;
    outC = mix(outC, softLight(outC, dsrc), alphaS);

    outC = mix(outC, u.overlayColor.rgb, u.overlayColor.a);
    return float4(outC, 1.0);
}
"""

private struct MeshUniformsGPU {
    var res: SIMD2<Float>
    var time: Float
    var colorsCount: Float
    var distortion: Float
    var swirl: Float
    var grainMixer: Float
    var grainOverlay: Float
    var colors: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
                 SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
}

private struct DitherUniformsGPU {
    var res: SIMD2<Float>
    var time: Float
    var pixelRatio: Float
    var pxSize: Float
    var colorBack: SIMD4<Float>
    var colorFront: SIMD4<Float>
}

private struct CompositeUniformsGPU {
    var res: SIMD2<Float>
    var bgColor: SIMD4<Float>
    var overlayColor: SIMD4<Float>
    var meshScale: Float
    var meshSaturate: Float
    var meshBrightness: Float
    var ditherOpacity: Float
    var ditherScale: Float
}

private func colorsTuple(_ colors: [SIMD4<Float>]) ->
    (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
     SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
    let c = (colors + Array(repeating: SIMD4.zero, count: 10)).prefix(10).map { $0 }
    return (c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9])
}

enum LatentBackgroundPreset: String, CaseIterable, Identifiable {
        case cover
        case dusk
        case ocean
        case moss
        case crimson

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cover: return "跟封面"
        case .dusk: return "橘焰"
        case .ocean: return "青潮"
        case .moss: return "绿沉"
        case .crimson: return "赤霁"
        }
    }

        var colors: [SIMD4<Float>]? {
        switch self {
        case .cover:
            return nil
        case .dusk:
            return Self.palette(0xFF7E4D, 0xE8435C, 0xFFB35C, 0x6B3FA0, 0x1F0F2E, 0xFF9E7D)
        case .ocean:
            return Self.palette(0x1B6CA8, 0x17A398, 0x274690, 0x7FD1E8, 0x04121E, 0x2EE6D6)
        case .moss:
            return Self.palette(0x4A7C3F, 0x2C4A32, 0x8FA882, 0x8C6A4A, 0x0E1410, 0xA8D08D)
        case .crimson:
            return Self.palette(0xC03A4A, 0x7A1E30, 0xE8AEB7, 0xD98E4A, 0x1A0A10, 0xE85A5A)
        }
    }

    private static func palette(_ hex: UInt32...) -> [SIMD4<Float>] {
        func rgba(_ v: UInt32) -> SIMD4<Float> {
            SIMD4(Float((v >> 16) & 0xFF) / 255, Float((v >> 8) & 0xFF) / 255, Float(v & 0xFF) / 255, 1)
        }
        return hex.map(rgba)
    }
}

struct LatentBackgroundView: UIViewRepresentable {
    let theme: ThemeColors
    let coverColors: [CoverPalette.RGB]
    var preset: LatentBackgroundPreset = .cover

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = true
        view.isUserInteractionEnabled = false
        view.delegate = context.coordinator
        context.coordinator.setPalette(theme: theme, coverColors: coverColors, preset: preset)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.setPalette(theme: theme, coverColors: coverColors, preset: preset)
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {

        private struct Palette {
            var meshColors: [SIMD4<Float>] = []
            var ditherBack: SIMD4<Float> = .zero
            var ditherFront: SIMD4<Float> = .zero
            var bg: SIMD4<Float> = SIMD4(0, 0, 0, 1)
            var overlay: SIMD4<Float> = SIMD4(0, 0, 0, 0.35)
        }

                private static let maxShaderPixels = 1280.0 * 720.0
        private static let ditheringSpeedBase = 0.1
        private static let ditheringAudioSpeed = 1.2
        private static let ditheringSize = 2.5
        private static let ditheringOpacity = 0.55
        private static let meshSpeedBase = 0.3
        private static let meshAudioSpeed = 2.0
        private static let meshDistortion = 0.8
        private static let meshSwirl = 0.1
        private static let overlayOpacity = 0.35
        private static let pausedSpeedScale = 0.12

        private let device: MTLDevice?
        private let queue: MTLCommandQueue?
        private var meshPipeline: MTLRenderPipelineState?
        private var ditherPipeline: MTLRenderPipelineState?
        private var compositePipeline: MTLRenderPipelineState?
        private var sampler: MTLSamplerState?

        private var palette = Palette()
        private var meshTexture: MTLTexture?
        private var ditherTexture: MTLTexture?
                private var pixelRatio: Float = 1
        private var textureSize = CGSize.zero

                private var smoothedPower: Double = 0
        private var smoothedBass: Double = 0
        private var smoothedMid: Double = 0
        private var smoothedBeatSpeed: Double = 0
        private var previousBeatEnergy: Double = 0
        private var onsetPulse: Double = 0
        private var meshTime: Double = 0
        private var ditherTime: Double = 0
        private var lastFrame: CFTimeInterval?

        override init() {
            device = MTLCreateSystemDefaultDevice()
            queue = device?.makeCommandQueue()
            super.init()
            buildPipelines()
        }

        func setPalette(theme: ThemeColors, coverColors: [CoverPalette.RGB],
                        preset: LatentBackgroundPreset) {
            if let fixed = preset.colors {
                let bg = fixed[4]
                palette = Palette(
                    meshColors: fixed,
                    ditherBack: bg,
                    ditherFront: fixed[0],
                    bg: SIMD4(bg.x, bg.y, bg.z, 1),
                    overlay: SIMD4(bg.x, bg.y, bg.z, Float(Self.overlayOpacity))
                )
                return
            }
            let primary = coverColors.count > 0 ? coverColors[0].float4 : rgba(theme.secondary)
            let secondary = coverColors.count > 1 ? coverColors[1].float4 : rgba(theme.primary)
            let tertiary = coverColors.count > 2 ? coverColors[2].float4 : primary
            let quaternary = coverColors.count > 3 ? coverColors[3].float4 : secondary
            let bg = rgba(theme.background)
            palette = Palette(
                meshColors: [primary, secondary, tertiary, quaternary, bg, rgba(theme.accent)],
                ditherBack: bg,
                ditherFront: primary,
                bg: SIMD4(bg.x, bg.y, bg.z, 1),
                overlay: SIMD4(bg.x, bg.y, bg.z, Float(Self.overlayOpacity))
            )
        }

        private func rgba(_ color: Color) -> SIMD4<Float> {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            if UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) {
                return SIMD4(Float(r), Float(g), Float(b), Float(a))
            }
            return SIMD4(0.5, 0.5, 0.5, 1)
        }

        private func buildPipelines() {
            guard let device else { return }
            do {
                let lib = try device.makeLibrary(source: latentShaderSource, options: nil)
                let vertexNSC = lib.makeFunction(name: "latent_vertex_nsc")!
                let vertexUV = lib.makeFunction(name: "latent_vertex_uv01")!

                func pipeline(_ frag: String, _ vert: MTLFunction, _ pixel: MTLPixelFormat) -> MTLRenderPipelineState? {
                    let desc = MTLRenderPipelineDescriptor()
                    desc.vertexFunction = vert
                    desc.fragmentFunction = lib.makeFunction(name: frag)
                    desc.colorAttachments[0].pixelFormat = pixel
                    desc.colorAttachments[0].isBlendingEnabled = false
                    return try? device.makeRenderPipelineState(descriptor: desc)
                }
                meshPipeline = pipeline("latent_mesh_fragment", vertexNSC, .rgba8Unorm)
                ditherPipeline = pipeline("latent_dither_fragment", vertexNSC, .rgba8Unorm)
                compositePipeline = pipeline("latent_composite_fragment", vertexUV, .bgra8Unorm)

                let s = MTLSamplerDescriptor()
                s.minFilter = .linear
                s.magFilter = .linear
                s.sAddressMode = .clampToEdge
                s.tAddressMode = .clampToEdge
                sampler = device.makeSamplerState(descriptor: s)
            } catch {
                assertionFailure("Latent shader 编译失败: \(error)")
            }
        }

        private func ensureTextures(view: MTKView) {
            guard let device, view.bounds.width > 0, view.bounds.height > 0 else { return }
            let drawable = view.drawableSize
            let dpr = drawable.width / view.bounds.width
                        let cap = min(1, sqrt(Self.maxShaderPixels / (drawable.width * drawable.height)))
            let scale = Float(dpr) * Float(cap)
            let w = max(1, Int(view.bounds.width * CGFloat(scale)))
            let h = max(1, Int(view.bounds.height * CGFloat(scale)))
            if textureSize != CGSize(width: w, height: h) {
                textureSize = CGSize(width: w, height: h)
                pixelRatio = scale
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                    width: w, height: h,
                                                                    mipmapped: false)
                desc.usage = [.shaderRead, .renderTarget]
                desc.storageMode = .private
                meshTexture = device.makeTexture(descriptor: desc)
                ditherTexture = device.makeTexture(descriptor: desc)
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let queue, let drawable = view.currentDrawable,
                  let compositePipeline,
                  view.bounds.width > 0, view.bounds.height > 0
            else { return }
            ensureTextures(view: view)
            guard let meshPipeline, let ditherPipeline, let meshTexture, let ditherTexture, let sampler else { return }

            let now = CACurrentMediaTime()
            let dt = min(max(now - (lastFrame ?? now), 0.001), 0.1)
            lastFrame = now
            let dtScale = min(max(dt / (1.0 / 60.0), 0.5), 2.0)

                        let player = PlayerCenter.shared
            let isPaused = !player.isPlaying
            let bands = player.analysis.snapshot()

            var targetPower = 0.0, targetBass = 0.0, targetMid = 0.0, targetBeatEnergy = 0.0
            if !isPaused {
                let norm = { (v: Double) in min(1, max(0, v / 255)) }
                if bands.hasSignal {
                    targetPower = norm(bands.power)
                    targetBass = norm(bands.bass)
                    targetMid = norm(max(bands.mid, bands.vocal))
                    targetBeatEnergy = broadbandEnergy(bass: bands.bass, lowMid: bands.lowMid,
                                                       mid: bands.mid, vocal: bands.vocal, treble: bands.treble)
                } else {
                                        let breath = (sin(Date().timeIntervalSince1970 / 2000.0) + 1) * 20
                    targetPower = norm(breath)
                    targetBass = norm(breath)
                    targetMid = norm(breath)
                    targetBeatEnergy = broadbandEnergy(bass: breath, lowMid: breath, mid: breath,
                                                       vocal: breath, treble: breath)
                }
            }

            func ease(_ amount: Double) -> Double { 1 - pow(1 - amount, dtScale) }
            smoothedPower += (targetPower - smoothedPower) * ease(0.12)
            smoothedBass += (targetBass - smoothedBass) * ease(0.16)
            smoothedMid += (targetMid - smoothedMid) * ease(0.13)

                        onsetPulse = max(onsetPulse * 0.84, min(1, max(0, (targetBeatEnergy - previousBeatEnergy) * 7)))
            previousBeatEnergy = targetBeatEnergy
            let beatSpeedTarget = min(1, max(0, targetBeatEnergy * 0.42 + onsetPulse * 0.85))
            let beatAmount = beatSpeedTarget > smoothedBeatSpeed ? 0.42 : 0.14
            smoothedBeatSpeed += (beatSpeedTarget - smoothedBeatSpeed) * ease(beatAmount)

                        let ditherSpeed = isPaused
                ? Self.ditheringSpeedBase * Self.pausedSpeedScale
                : min(2, max(0, Self.ditheringSpeedBase + (Self.ditheringAudioSpeed - Self.ditheringSpeedBase) * smoothedBeatSpeed))
            let meshSpeed = isPaused
                ? Self.meshSpeedBase * Self.pausedSpeedScale
                : min(2, max(0, Self.meshSpeedBase + (Self.meshAudioSpeed - Self.meshSpeedBase) * smoothedBeatSpeed))
            ditherTime += dt * ditherSpeed
            meshTime += dt * meshSpeed

                        var meshU = MeshUniformsGPU(
                res: SIMD2(Float(textureSize.width), Float(textureSize.height)),
                time: Float(meshTime),
                colorsCount: Float(palette.meshColors.count),
                distortion: Float(Self.meshDistortion + smoothedPower * 0.62),
                swirl: Float(Self.meshSwirl + smoothedMid * 0.38),
                grainMixer: 0,
                grainOverlay: 0.01,
                colors: colorsTuple(palette.meshColors)
            )
            var ditherU = DitherUniformsGPU(
                res: SIMD2(Float(textureSize.width), Float(textureSize.height)),
                time: Float(ditherTime),
                pixelRatio: pixelRatio,
                pxSize: Float(max(0.5, Self.ditheringSize - smoothedBass * Self.ditheringSize * 0.34)),
                colorBack: palette.ditherBack,
                colorFront: palette.ditherFront
            )
            var compU = CompositeUniformsGPU(
                res: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                bgColor: palette.bg,
                overlayColor: palette.overlay,
                meshScale: Float(1.025 + smoothedPower * 0.018),
                meshSaturate: Float(1.04 + smoothedMid * 0.34),
                meshBrightness: Float(0.94 + smoothedPower * 0.16),
                ditherOpacity: Float(min(1, Self.ditheringOpacity + smoothedBass * 0.25)),
                ditherScale: Float(1.015 + smoothedBass * 0.025)
            )

                        guard let cmd = queue.makeCommandBuffer() else { return }

            renderPass(cmd: cmd, pipeline: meshPipeline, target: meshTexture,
                       bytes: &meshU, length: MemoryLayout<MeshUniformsGPU>.stride)
            renderPass(cmd: cmd, pipeline: ditherPipeline, target: ditherTexture,
                       bytes: &ditherU, length: MemoryLayout<DitherUniformsGPU>.stride)

            if let rpd = view.currentRenderPassDescriptor {
                rpd.colorAttachments[0].clearColor = MTLClearColor(
                    red: Double(palette.bg.x), green: Double(palette.bg.y),
                    blue: Double(palette.bg.z), alpha: 1)
                if let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) {
                    enc.setRenderPipelineState(compositePipeline)
                    enc.setFragmentBytes(&compU, length: MemoryLayout<CompositeUniformsGPU>.stride, index: 0)
                    enc.setFragmentTexture(meshTexture, index: 0)
                    enc.setFragmentTexture(ditherTexture, index: 1)
                    enc.setFragmentSamplerState(sampler, index: 0)
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    enc.endEncoding()
                }
                cmd.present(drawable)
                cmd.commit()
            }
        }

        private func renderPass(cmd: MTLCommandBuffer, pipeline: MTLRenderPipelineState,
                                target: MTLTexture, bytes: UnsafeRawPointer, length: Int) {
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = target
            rpd.colorAttachments[0].loadAction = .dontCare
            rpd.colorAttachments[0].storeAction = .store
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
            enc.setRenderPipelineState(pipeline)
            enc.setFragmentBytes(bytes, length: length, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
        }

                private func broadbandEnergy(bass: Double, lowMid: Double, mid: Double, vocal: Double, treble: Double) -> Double {
            let n = { (v: Double) in min(1, max(0, v / 255)) }
            let e = n(bass) * 0.22 + n(lowMid) * 0.18 + n(mid) * 0.22 + n(vocal) * 0.28 + n(treble) * 0.1
            return pow(e, 0.55)
        }
    }
}
