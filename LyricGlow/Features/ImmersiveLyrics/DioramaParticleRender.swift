import Foundation
import Metal
import simd

let DIORAMA_PARTICLE_CORRIDOR_RADIUS = 7.4

struct DioramaParticleCorridorSpan {
    var start: SIMD3<Double>
    var end: SIMD3<Double>
    var startRight: SIMD3<Double>
    var endRight: SIMD3<Double>
    var startUp: SIMD3<Double>
    var endUp: SIMD3<Double>
        var pathStart: Double
}

private func resolveRingSegments(_ pointsPerSpan: Int) -> Int {
    max(12, min(256, Int((Double(pointsPerSpan) * 2.4).squareRoot().rounded())))
}

struct DioramaParticlePointData {
        static let floatsPerPoint = 18
    var packed: [Float] = []
    var pointCount = 0
    var spacing: Double = 1

    @discardableResult
    mutating func append(position: SIMD3<Float>, normal: SIMD3<Float>, anchor: SIMD3<Float>,
                         scale: SIMD3<Float>, phase: Float, style: SIMD3<Float>, wave: SIMD2<Float>) {
        packed.append(contentsOf: [position.x, position.y, position.z])
        packed.append(contentsOf: [normal.x, normal.y, normal.z])
        packed.append(contentsOf: [anchor.x, anchor.y, anchor.z])
        packed.append(contentsOf: [scale.x, scale.y, scale.z])
        packed.append(phase)
        packed.append(contentsOf: [style.x, style.y, style.z])
        packed.append(contentsOf: [wave.x, wave.y])
        pointCount += 1
    }
}

private func normalizeVecD(_ v: SIMD3<Double>) -> SIMD3<Double> {
    let length = simd_length(v)
    return length > 0 ? v / length : SIMD3(0, 0, 1)
}

func buildDioramaCorridorSpans(_ frames: [DioramaFrame], _ center: Int) -> [DioramaParticleCorridorSpan] {
    guard !frames.isEmpty else { return [] }
    let first = 0
    let last = frames.count - 1
    func frameAt(_ index: Int) -> DioramaFrame {
        let clamped = min(max(index, first), last)
        return extendDioramaFrame(frames[clamped], index - clamped)
    }
    var spans: [DioramaParticleCorridorSpan] = []
    spans.reserveCapacity(DIORAMA_CORRIDOR_LINES_BEHIND + DIORAMA_CORRIDOR_LINES_AHEAD + 1)
    for i in (center - DIORAMA_CORRIDOR_LINES_BEHIND)...(center + DIORAMA_CORRIDOR_LINES_AHEAD) {
        let start = frameAt(i)
        let end = frameAt(i + 1)
        spans.append(DioramaParticleCorridorSpan(
            start: start.position, end: end.position,
            startRight: start.right, endRight: end.right,
            startUp: start.up, endUp: end.up,
            pathStart: Double(i)))
    }
    return spans
}

func buildDioramaCorridorPointData(_ spans: [DioramaParticleCorridorSpan],
                                   _ density: Double) -> DioramaParticlePointData {
    let radius = DIORAMA_PARTICLE_CORRIDOR_RADIUS
    let pointsPerSpan = Int(normalizeDensity(min(density, DIORAMA_MAX_CORRIDOR_POINTS_PER_SPAN)))
    let ringSegments = resolveRingSegments(pointsPerSpan)
    let rings = max(1, pointsPerSpan / ringSegments)
    let perSpan = ringSegments * rings
            let spanUnits = DIORAMA_STEP_DISTANCE / radius
    let spacing = max(spanUnits / Double(max(1, rings)), (Double.pi * 2) / Double(ringSegments))
    var data = DioramaParticlePointData()
    data.spacing = spacing
    data.packed.reserveCapacity(spans.count * perSpan * DioramaParticlePointData.floatsPerPoint)

    for span in spans {
        for ring in 0..<rings {
                        let t = rings > 1 ? Double(ring) / Double(rings - 1) : 0.5
            let cx = span.start.x + (span.end.x - span.start.x) * t
            let cy = span.start.y + (span.end.y - span.start.y) * t
            let cz = span.start.z + (span.end.z - span.start.z) * t
            let right = normalizeVecD(span.startRight + (span.endRight - span.startRight) * t)
            let up = normalizeVecD(span.startUp + (span.endUp - span.startUp) * t)
                        let longitudinal = span.pathStart + t
            for segment in 0..<ringSegments {
                let angle = Double(segment) / Double(ringSegments) * Double.pi * 2
                let cosA = cos(angle)
                let sinA = sin(angle)
                let radial = normalizeVecD(right * cosA + up * sinA)
                                data.append(
                    position: SIMD3(Float(radial.x * radius), Float(radial.y * radius), Float(radial.z * radius)),
                    normal: SIMD3(Float(radial.x), Float(radial.y), Float(radial.z)),
                    anchor: SIMD3(Float(cx), Float(cy), Float(cz)),
                    scale: SIMD3(1, 1, Float(radius)),
                    phase: Float(longitudinal * 1.7),
                    style: SIMD3(3, Float((Int(span.pathStart.rounded()) + ring) % 2), 0),
                    wave: SIMD2(Float(longitudinal * spanUnits), Float(angle)))
            }
        }
    }
    return data
}

let dioramaParticleShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct DioramaParticlePoint {
    packed_float3 position;
    packed_float3 normal;
    packed_float3 anchor;
    packed_float3 scale;
    float phase;
    packed_float3 style;
    packed_float2 wave;
};

struct DioramaParticleUniforms {
    float4x4 viewProj;
    float4 camPos;
    float4 rippleSource[9];
    float4 rippleShape[9];
    float4 primaryColor;
    float4 accentColor;
    float4 secondaryColor;
    float4 p0;
    float4 p1;
    float4 p2;
    float4 p3;
    float4 p4;
};

struct VOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float3 color;
    float alpha;
    float reaction;
};

float hermite(float v) { return v * v * (3.0 - 2.0 * v); }
float hash11(float n) { return fract(sin(n) * 43758.5453123); }

float resolveLife(float dist) {
    float farT = clamp((27.0 - dist) / (27.0 - 20.0), 0.0, 1.0);
    float nearT = clamp((dist - 1.2) / (3.0 - 1.2), 0.0, 1.0);
    return hermite(farT) * hermite(nearT);
}

float ripplePacket(float r, float age, float4 shape, float waveNumberMax) {
    float dr = r - age * shape.y;
    float k = min(shape.w, waveNumberMax);
    float packet = exp(-(dr * dr) / (shape.z * shape.z)) * sin(dr * k);

    return shape.x * packet * exp(-age * 1.15) * exp(-r * 0.35);
}

float atan2Impl(float y, float x) {
    if (x > 0.0) return atan(y / x);
    if (x < 0.0) return y >= 0.0 ? atan(y / x) + M_PI_F : atan(y / x) - M_PI_F;
    return y > 0.0 ? M_PI_2_F : (y < 0.0 ? -M_PI_2_F : 0.0);
}

float2 corridorSurfaceDelta(float2 w, float2 origin) {
    float dAngle = w.y - origin.y;
    return float2(w.x - origin.x, atan2Impl(sin(dAngle), cos(dAngle)));
}

float corridorRipples(float2 w, DioramaParticleUniforms u) {
    float total = 0.0;
    for (int i = 0; i < 9; i++) {
        float4 source = u.rippleSource[i];
        float4 shape = u.rippleShape[i];
        float age = u.p0.x - source.w;
        if (shape.x <= 0.0 || age < 0.0) continue;
        total += ripplePacket(length(corridorSurfaceDelta(w, source.xy)), age, shape, u.p1.x);
    }
    return total;
}

float corridorIdle(float2 w, DioramaParticleUniforms u) {
    float t = u.p0.x * u.p1.w;
    float region = 0.6 + 0.4 * sin(w.x * 0.42 - t * 0.33);
    float ripple = 0.62 * sin(w.x * 1.25 - t * 1.15)
                 + 0.30 * sin(w.x * 0.8 + w.y * 2.0 - t * 0.8)
                 + 0.08 * sin(w.y * 3.0 + t * 0.5);
    return region * ripple;
}

float corridorDetail(float2 w, DioramaParticleUniforms u) {
    float k = u.p1.x * 0.7;
    float n = max(1.0, floor(k));
    return sin(w.x * k + u.p0.x * 3.1) * sin(w.y * n - u.p0.x * 2.4);
}

vertex VOut diorama_particle_vertex(uint vid [[vertex_id]],
                                    constant DioramaParticleUniforms &u [[buffer(0)]],
                                    constant DioramaParticlePoint *points [[buffer(1)]]) {
    DioramaParticlePoint in = points[vid];
    float localRadius = in.scale[2];

    float3 basePos = float3(in.position);

    basePos.y *= in.scale[1];

    float2 w = in.wave;
    float audio = corridorRipples(w, u);
    float idle = corridorIdle(w, u);

    float detail = u.p1.y * smoothstep(0.06, 0.45, abs(audio));
    audio += corridorDetail(w, u) * detail * 0.3;

    float swell = clamp(audio + idle, -1.6, 1.6) * u.p0.z;
    float3 normalDir = normalize(float3(in.normal));
    float3 displaced = basePos + normalDir * (swell * localRadius);

    float d = clamp(abs(clamp(audio, -1.6, 1.6) * u.p0.z) / max(u.p0.w, 0.0001), 0.0, 1.0);

    displaced.z += sin(u.p0.x * 0.6 + in.phase) * 0.12 * u.p1.z * localRadius;

    float scatter = 1.0 - u.p2.x;
    if (scatter > 0.001) {
        float r1 = hash11(in.phase * 12.9898 + w.x * 78.233);
        float r2 = hash11(in.phase * 39.346 + w.y * 11.135 + 3.7);
        float r3 = hash11(r1 * 91.7 + r2 * 47.3);
        float3 spread = normalize(normalDir * 0.75 + float3(r1 - 0.5, r2 - 0.5, r3 - 0.5) * 1.6);
        displaced += spread * (scatter * scatter * u.p2.y * (0.55 + r3 * 0.9));
    }

    displaced *= in.scale[0] * u.p2.z;
    float3 worldPosition = float3(in.anchor) + displaced;

    float life = resolveLife(distance(worldPosition, u.camPos.xyz));
    float4 mv = u.viewProj * float4(worldPosition, 1.0);

    VOut out;

    float glowScale = mix(1.0, 1.9 + u.p3.w * 1.3, u.p4.x);
    float sizeWorld = (u.p3.y + (pow(d, 3.0) + detail * 0.35) * u.p3.z) * glowScale;
    float projected = sizeWorld * u.p3.x * u.viewProj[1][1] * 0.5 / max(-mv.z, 0.1);
    out.pointSize = clamp(projected, mix(1.4, 2.0, u.p4.x), mix(26.0, 64.0, u.p4.x));
    out.position = mv;

    float3 basePosF = float3(in.position);
    float gradientPhase = (
        dot(basePosF, float3(0.2, 0.16, 0.13))
        + in.phase * 0.05
        + in.style[1] * 0.5
        + u.p0.x * 0.02
        + u.p2.w * 0.3
    ) * 6.283;
    float3 wgt = max(float3(0.0), 0.5 + 0.5 * cos(gradientPhase - float3(0.0, 2.094, 4.188)));
    wgt *= wgt;
    wgt /= max(wgt.x + wgt.y + wgt.z, 0.001);
    float3 baseColor = u.primaryColor.rgb * wgt.x + u.accentColor.rgb * wgt.y + u.secondaryColor.rgb * wgt.z;
    float3 hotColor = mix(u.accentColor.rgb, u.secondaryColor.rgb, smoothstep(0.2, 0.9, u.p2.w));
    float hot = min(1.0, smoothstep(0.1, 0.75, d) * 0.75 + detail * 0.3);
    out.color = mix(baseColor, hotColor, hot) * (0.92 + d * 0.5);

    float formed = smoothstep(0.0, 0.45, u.p2.x);
    out.alpha = formed * (u.p4.x > 0.5
        ? life * smoothstep(0.1, 0.8, d) * 1.15
        : life * min(1.0, 0.72 + d * 0.28));
    out.reaction = d;
    return out;
}

float3 dioramaLinearToSRGB(float3 linear) {
    float3 safe = max(linear, float3(0.0));

    return select(
        safe * 12.92,
        pow(safe, float3(0.41666)) * 1.055 - float3(0.055),
        bool3(safe.x > 0.0031308, safe.y > 0.0031308, safe.z > 0.0031308)
    );
}

fragment float4 diorama_particle_fragment(VOut in [[stage_in]],
                                          float2 pointCoord [[point_coord]],
                                          constant DioramaParticleUniforms &u [[buffer(0)]]) {
    float2 point = pointCoord - float2(0.5);
    float radius = length(point);

    if (u.p4.x > 0.5) {

        float halo = pow(clamp(1.0 - radius * 2.0, 0.0, 1.0), 1.7);
        float alpha = min(0.5, halo * in.alpha * u.p3.w * 0.4);
        if (alpha < 0.003) discard_fragment();
        return float4(dioramaLinearToSRGB(in.color * (1.0 + u.p3.w * 0.25)), alpha);
    }

    float core = 1.0 - smoothstep(0.14, 0.48, radius);
    float alpha = core * in.alpha;
    if (alpha < 0.01) discard_fragment();
    float emission = 0.95 + in.reaction * 0.22;
    return float4(dioramaLinearToSRGB(in.color * emission), alpha);
}
"""

let dioramaMoteShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct DioramaMoteUniforms {
    float4x4 viewProj;
    float4 camPos;
    float4 params;
    float4 color;
};

struct MoteVOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float alpha;
};

vertex MoteVOut diorama_mote_vertex(uint vid [[vertex_id]],
                                    constant DioramaMoteUniforms &u [[buffer(0)]],
                                    constant packed_float3 *positions [[buffer(1)]]) {
    float3 world = float3(positions[vid]);
    float4 mv = u.viewProj * float4(world, 1.0);
    MoteVOut out;

    float projected = u.params.x * u.params.z * 0.5 / max(-mv.z, 0.1);
    out.pointSize = clamp(projected, 1.0, 8.0);
    out.position = mv;
    out.alpha = u.params.y;
    return out;
}

fragment float4 diorama_mote_fragment(MoteVOut in [[stage_in]],
                                      float2 pointCoord [[point_coord]],
                                      constant DioramaMoteUniforms &u [[buffer(0)]]) {
    float radius = length(pointCoord - float2(0.5));
    float core = 1.0 - smoothstep(0.2, 0.5, radius);
    float alpha = core * in.alpha;
    if (alpha < 0.01) discard_fragment();

    float3 safe = max(u.color.rgb, float3(0.0));
    float3 rgb = select(safe * 12.92,
                        pow(safe, float3(0.41666)) * 1.055 - float3(0.055),
                        bool3(safe.x > 0.0031308, safe.y > 0.0031308, safe.z > 0.0031308));
    return float4(rgb, alpha);
}
"""

private let DIORAMA_CALM_EMISSION = 0.92 * 0.95
private let DIORAMA_CONTRAST_LAYER_ALPHA = 0.72

func dioramaSRGBFromLinear(_ v: Float) -> Float {
    let safe = max(v, 0)
    return safe <= 0.0031308 ? safe * 12.92 : pow(safe, 1.0 / 2.4) * 1.055 - 0.055
}

func dioramaLinearFromSRGB(_ v: Float) -> Float {
    let safe = max(v, 0)
    return safe <= 0.04045 ? safe / 12.92 : pow((safe + 0.055) / 1.055, 2.4)
}

func dioramaLinearFromSRGB(_ c: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3(dioramaLinearFromSRGB(c.x), dioramaLinearFromSRGB(c.y), dioramaLinearFromSRGB(c.z))
}

private func dioramaRelativeLuminance(_ c: SIMD3<Float>) -> Double {
    0.2126 * Double(c.x) + 0.7152 * Double(c.y) + 0.0722 * Double(c.z)
}

private func dioramaContrastRatio(_ fg: SIMD3<Float>, _ bg: SIMD3<Float>) -> Double {
    let f = dioramaRelativeLuminance(fg)
    let b = dioramaRelativeLuminance(bg)
    return (max(f, b) + 0.05) / (min(f, b) + 0.05)
}

private func dioramaAsDisplayed(_ color: SIMD3<Float>, _ background: SIMD3<Float>) -> SIMD3<Float> {
    let src = SIMD3<Float>(dioramaSRGBFromLinear(color.x * Float(DIORAMA_CALM_EMISSION)),
                           dioramaSRGBFromLinear(color.y * Float(DIORAMA_CALM_EMISSION)),
                           dioramaSRGBFromLinear(color.z * Float(DIORAMA_CALM_EMISSION)))
    let dst = SIMD3<Float>(dioramaSRGBFromLinear(background.x),
                           dioramaSRGBFromLinear(background.y),
                           dioramaSRGBFromLinear(background.z))
    let a = Float(DIORAMA_CONTRAST_LAYER_ALPHA)
    let blended = SIMD3<Float>(src.x * a + dst.x * (1 - a),
                               src.y * a + dst.y * (1 - a),
                               src.z * a + dst.z * (1 - a))
    return dioramaLinearFromSRGB(blended)
}

private func dioramaDisplayedContrastRatio(_ color: SIMD3<Float>, _ background: SIMD3<Float>) -> Double {
    dioramaContrastRatio(dioramaAsDisplayed(color, background), background)
}

private func dioramaAdaptColor(_ color: SIMD3<Float>, _ background: SIMD3<Float>,
                               _ minimumContrast: Double) -> SIMD3<Float> {
    if dioramaDisplayedContrastRatio(color, background) >= minimumContrast { return color }
    let lightTarget = SIMD3<Float>(1, 1, 1)
    let darkTarget = SIMD3<Float>(repeating: dioramaLinearFromSRGB(5.0 / 255.0))
        let target = dioramaDisplayedContrastRatio(lightTarget, background)
        >= dioramaDisplayedContrastRatio(darkTarget, background) ? lightTarget : darkTarget
    var low = 0.0
    var high = 1.0
    for _ in 0..<10 {
        let amount = Float((low + high) * 0.5)
        let candidate = simd_mix(color, target, SIMD3<Float>(repeating: amount))
        if dioramaDisplayedContrastRatio(candidate, background) >= minimumContrast {
            high = Double(amount)
        } else {
            low = Double(amount)
        }
    }
    return simd_mix(color, target, SIMD3<Float>(repeating: Float(high)))
}

func resolveDioramaParticleContrastColors(
    _ colors: (primary: SIMD3<Float>, accent: SIMD3<Float>, secondary: SIMD3<Float>),
    _ background: SIMD3<Float>
) -> (primary: SIMD3<Float>, accent: SIMD3<Float>, secondary: SIMD3<Float>) {
    (dioramaAdaptColor(colors.primary, background, 4.6),
     dioramaAdaptColor(colors.accent, background, 4.1),
     dioramaAdaptColor(colors.secondary, background, 4.6))
}

struct DioramaParticleUniformsGPU {
    var viewProj: simd_float4x4 = matrix_identity_float4x4
    var camPos: SIMD4<Float> = .zero
    var rippleSource = [SIMD4<Float>](repeating: .zero, count: 9)
    var rippleShape = [SIMD4<Float>](repeating: .zero, count: 9)
    var primaryColor: SIMD4<Float> = .one
    var accentColor: SIMD4<Float> = .one
    var secondaryColor: SIMD4<Float> = .one
    var p0: SIMD4<Float> = .zero
    var p1: SIMD4<Float> = .zero
    var p2: SIMD4<Float> = .zero
    var p3: SIMD4<Float> = .zero
    var p4: SIMD4<Float> = .zero

                func packed() -> [Float32] {
        var out = [Float32]()
        out.reserveCapacity(124)
        for c in [viewProj.columns.0, viewProj.columns.1, viewProj.columns.2, viewProj.columns.3] {
            out.append(contentsOf: [c.x, c.y, c.z, c.w])
        }
        out.append(contentsOf: [camPos.x, camPos.y, camPos.z, camPos.w])
        for v in rippleSource { out.append(contentsOf: [v.x, v.y, v.z, v.w]) }
        for v in rippleShape { out.append(contentsOf: [v.x, v.y, v.z, v.w]) }
        for v in [primaryColor, accentColor, secondaryColor] {
            out.append(contentsOf: [v.x, v.y, v.z, v.w])
        }
        for v in [p0, p1, p2, p3, p4] { out.append(contentsOf: [v.x, v.y, v.z, v.w]) }
        return out
    }
}

struct DioramaMoteUniformsGPU {
    var viewProj: simd_float4x4 = matrix_identity_float4x4
    var camPos: SIMD4<Float> = .zero
    var params: SIMD4<Float> = .zero
    var color: SIMD4<Float> = .one
}

final class DioramaParticleFieldRenderer {
    private let device: MTLDevice
    private(set) var corridorPipeline: MTLRenderPipelineState?
    private(set) var corridorGlowPipeline: MTLRenderPipelineState?
    private(set) var motePipeline: MTLRenderPipelineState?
    private var particleBuffer: MTLBuffer?
    private var moteBuffer: MTLBuffer?
    private var motePositions: [Float]
    private var moteWritten: [Int] = []
    private var uniform = DioramaParticleUniformsGPU()
    private var moteUniform = DioramaMoteUniformsGPU()
    private let moteCircumference: Int
    private let moteRadial: Int
    private let moteTotal: Int

        private var trackers = (0..<3).map { _ in DioramaBandTracker() }
    private var pool = DioramaRipplePool()
    private var elastic = DioramaParticleElasticState()
    private var flowTime = 0.0
    private var previousPlaybackTime: Double?
    private var corridorCenter = Int.min
    private var corridorPointCount = 0
    private var waveNumberMax = 8.0
    private var trebleEnv = 0.0
    private var powerEnv = 0.0

        private let density = 576.0
    private let glowIntensity = 0.65
    private let audioLevel = 1.0

        private var lerpedPrimary: SIMD3<Float>? = nil
    private var lerpedAccent: SIMD3<Float>? = nil
    private var lerpedSecondary: SIMD3<Float>? = nil
    private var targetPrimary: SIMD3<Float> = .one
    private var targetAccent: SIMD3<Float> = .one
    private var targetSecondary: SIMD3<Float> = .one

    init?(device: MTLDevice) {
        self.device = device
        moteCircumference = resolveDioramaMoteCircumference(DIORAMA_MOTE_DEFAULT_CIRCUMFERENCE)
        moteRadial = resolveDioramaMoteRadial(DIORAMA_MOTE_DEFAULT_RADIAL)
        moteTotal = moteCircumference * moteRadial
        motePositions = Array(repeating: 0, count: DIORAMA_MOTE_WINDOW_LINES * moteTotal * 3)
        do {
            let lib = try device.makeLibrary(source: dioramaParticleShaderSource, options: nil)
            let vtx = lib.makeFunction(name: "diorama_particle_vertex")
            let frag = lib.makeFunction(name: "diorama_particle_fragment")
            guard let vtx, let frag else { return nil }

            func pipeline(_ glowPass: Bool, _ additive: Bool) -> MTLRenderPipelineState? {
                let desc = MTLRenderPipelineDescriptor()
                desc.vertexFunction = vtx
                desc.fragmentFunction = frag
                desc.colorAttachments[0].pixelFormat = .bgra8Unorm
                desc.colorAttachments[0].isBlendingEnabled = true
                                                desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                desc.colorAttachments[0].sourceAlphaBlendFactor = additive ? .sourceAlpha : .one
                desc.colorAttachments[0].destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
                desc.colorAttachments[0].destinationAlphaBlendFactor = additive ? .one : .oneMinusSourceAlpha
                return try? device.makeRenderPipelineState(descriptor: desc)
            }
            corridorPipeline = pipeline(false, false)
            corridorGlowPipeline = pipeline(true, true)

            let moteLib = try device.makeLibrary(source: dioramaMoteShaderSource, options: nil)
            let moteDesc = MTLRenderPipelineDescriptor()
            moteDesc.vertexFunction = moteLib.makeFunction(name: "diorama_mote_vertex")
            moteDesc.fragmentFunction = moteLib.makeFunction(name: "diorama_mote_fragment")
            moteDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            moteDesc.colorAttachments[0].isBlendingEnabled = true
                        moteDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            moteDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
            moteDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            moteDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            motePipeline = try? device.makeRenderPipelineState(descriptor: moteDesc)

            moteBuffer = device.makeBuffer(bytes: motePositions,
                                           length: motePositions.count * MemoryLayout<Float>.size)
            guard corridorPipeline != nil, corridorGlowPipeline != nil, motePipeline != nil, moteBuffer != nil else {
                return nil
            }
        } catch {
            return nil
        }
    }

        func resetForNewScene(seed: String) {
        trackers = (0..<3).map { _ in DioramaBandTracker() }
        pool.reset()
        elastic = DioramaParticleElasticState()
        previousPlaybackTime = nil
        flowTime = 0
        corridorCenter = Int.min
        moteWritten = []
                _ = seed
    }

                        func update(delta: Double, wallTime: Double, playbackTime: Double, globalIndex: Int,
                bass255: Double, lowMid255: Double, mid255: Double, treble255: Double, power255: Double,
                frameViewProj: simd_float4x4, camPos: SIMD3<Double>, drawableHeight: Float,
                themeTargets: (primary: SIMD3<Float>, accent: SIMD3<Float>, secondary: SIMD3<Float>),
                backgroundColor: SIMD3<Float>,
                moteColor: SIMD3<Float>) {
        let delta = min(delta, 0.1)
                        let bassTarget = min(1, bass255 / 255)
        let midTarget = min(1, (lowMid255 * 0.5 + mid255 * 0.5) / 255)
        let trebleTarget = min(1, treble255 / 255)
        let bassSignal = stepDioramaBandTracker(&trackers[0], bassTarget, delta)
        let midSignal = stepDioramaBandTracker(&trackers[1], midTarget, delta)
        let trebleSignal = stepDioramaBandTracker(&trackers[2], trebleTarget, delta)
        let response = resolveDioramaParticleAudioResponse(bassSignal, midSignal)
        let gain = max(0, audioLevel)

                        let playbackDelta = previousPlaybackTime.map { playbackTime - $0 } ?? 0
        let discontinuity = previousPlaybackTime == nil || playbackDelta < -0.05 || playbackDelta > 0.5
        if discontinuity {
            flowTime = playbackTime * 0.28
            pool.reset()
        } else if playbackDelta > 0 {
            flowTime += playbackDelta * response.flowSpeed
        }
        previousPlaybackTime = playbackTime

                let readHeadAlong = Double(globalIndex) * DIORAMA_CORRIDOR_UNITS_PER_LINE
        if gain > 0.001 {
            if bassSignal.onset {
                spawnDioramaRipple(&pool, 0, bassSignal.transient, flowTime, true, readHeadAlong)
            }
            if midSignal.onset {
                spawnDioramaRipple(&pool, 1, midSignal.transient, flowTime, true, readHeadAlong)
            }
            if trebleSignal.onset {
                spawnDioramaRipple(&pool, 2, trebleSignal.transient, flowTime, true, readHeadAlong)
            }
        }

                let elasticPulse = stepDioramaParticleElasticResponse(
            &elastic, resolveDioramaPulseTarget(response.clusterPulse, gain, true), delta)

                if corridorCenter != globalIndex, let framesRef = cachedFrames {
            corridorCenter = globalIndex
            let spans = buildDioramaCorridorSpans(framesRef, globalIndex)
            let data = buildDioramaCorridorPointData(spans, density)
            corridorPointCount = data.pointCount
            waveNumberMax = resolveWaveNumberMax(data.spacing)
            particleBuffer = device.makeBuffer(
                bytes: data.packed, length: data.packed.count * MemoryLayout<Float>.size,
                options: .storageModeShared)
        }

                if let framesRef = cachedFrames {
            motePositions.withUnsafeMutableBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                _ = recycleDioramaMoteWindow(&moteWritten, base, framesRef, globalIndex,
                                             framesRef.count, moteCircumference, moteRadial, cachedSeed)
            }
            if let buffer = moteBuffer {
                                motePositions.withUnsafeBytes { raw in
                    memcpy(buffer.contents(), raw.baseAddress!, raw.count)
                }
            }
        }

                        let colorAmount = 1 - exp(-1.2 * delta)
        let adapted = resolveDioramaParticleContrastColors(themeTargets, backgroundColor)
        targetPrimary = adapted.primary
        targetAccent = adapted.accent
        targetSecondary = adapted.secondary
        if lerpedPrimary == nil {
            lerpedPrimary = themeTargets.primary
            lerpedAccent = themeTargets.accent
            lerpedSecondary = themeTargets.secondary
        } else {
            let amount = SIMD3<Float>(repeating: Float(colorAmount))
            lerpedPrimary = simd_mix(lerpedPrimary!, targetPrimary, amount)
            lerpedAccent = simd_mix(lerpedAccent!, targetAccent, amount)
            lerpedSecondary = simd_mix(lerpedSecondary!, targetSecondary, amount)
        }

                let treble01 = min(1, treble255 / 255) * gain
        let power01 = min(1, power255 / 255) * gain
        trebleEnv = stepDioramaEnvelope(trebleEnv, treble01, 14, 3.2, delta)
        powerEnv = stepDioramaEnvelope(powerEnv, power01, 18, 3.5, delta)

                uniform.viewProj = frameViewProj
        uniform.camPos = SIMD4(Float(camPos.x), Float(camPos.y), Float(camPos.z), 0)
        uniform.rippleSource = pool.sources
        uniform.rippleShape = pool.shapes
        uniform.primaryColor = SIMD4(lerpedPrimary!, 1)
        uniform.accentColor = SIMD4(lerpedAccent!, 1)
        uniform.secondaryColor = SIMD4(lerpedSecondary!, 1)
        uniform.p0 = SIMD4(Float(flowTime), 1,
                           Float(gain * min(DIORAMA_CORRIDOR_MAX_SWELL,
                                            DIORAMA_CORRIDOR_QUIET_SWELL
                                            + bassSignal.sustained * 0.18
                                            + midSignal.sustained * 0.08)),
                           Float(DIORAMA_CORRIDOR_MAX_SWELL_REACH))
        uniform.p1 = SIMD4(Float(waveNumberMax),
                           Float(min(1, trebleSignal.sustained * gain)),
                           Float(midSignal.sustained * gain), 1)
        uniform.p2 = SIMD4(1, 6, Float(elasticPulse),
                           Float(min(1, 0.2 + trebleSignal.sustained * 0.8)))
        uniform.p3 = SIMD4(drawableHeight, 0.072, 0.34, Float(glowIntensity))
        uniform.p4 = SIMD4(0, 0, 0, 0)

                        let drift = SIMD3<Float>(sin(Float(wallTime) * 0.17) * 0.12,
                                 sin(Float(wallTime) * 0.11 + 1.7) * 0.09,
                                 cos(Float(wallTime) * 0.13) * 0.12)
        let driftT = simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, 1, 0, 0), SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(drift.x, drift.y, drift.z, 1)
        ))
        moteUniform.viewProj = frameViewProj * driftT
        moteUniform.camPos = uniform.camPos
        moteUniform.params = SIMD4(Float(0.03 * (1 + 0.42 * trebleEnv)),
                                   Float(0.16 + 0.18 * powerEnv), drawableHeight, 0)
        moteUniform.color = SIMD4(moteColor, 1)
    }

        private var cachedFrames: [DioramaFrame]?
    private var cachedSeed: String?
    func cacheScene(frames: [DioramaFrame], seed: String) {
        cachedFrames = frames
        cachedSeed = seed
    }

    func drawMotes(_ encoder: MTLRenderCommandEncoder) {
        guard let pipeline = motePipeline, let buffer = moteBuffer else { return }
        encoder.pushDebugGroup("diorama.motes")
        encoder.setRenderPipelineState(pipeline)
        withUnsafeBytes(of: moteUniform) { raw in
            encoder.setVertexBytes(raw.baseAddress!, length: raw.count, index: 0)
            encoder.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 0)
        }
        encoder.setVertexBuffer(buffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: DIORAMA_MOTE_WINDOW_LINES * moteTotal)
        encoder.popDebugGroup()
    }

    func drawCorridor(_ encoder: MTLRenderCommandEncoder) {
        guard let buffer = particleBuffer, corridorPointCount > 0 else { return }
        encoder.pushDebugGroup("diorama.particles")
        encoder.setVertexBuffer(buffer, offset: 0, index: 1)
                var glowPass = uniform
        glowPass.p4.x = 1
        if let glow = corridorGlowPipeline {
            encoder.setRenderPipelineState(glow)
            let bytes = glowPass.packed()
                                    bytes.withUnsafeBytes { raw in
                encoder.setVertexBytes(raw.baseAddress!, length: raw.count, index: 0)
                encoder.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 0)
            }
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: corridorPointCount)
        }
                if let contrast = corridorPipeline {
            encoder.setRenderPipelineState(contrast)
            let bytes = uniform.packed()
            bytes.withUnsafeBytes { raw in
                encoder.setVertexBytes(raw.baseAddress!, length: raw.count, index: 0)
                encoder.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 0)
            }
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: corridorPointCount)
        }
        encoder.popDebugGroup()
    }
}
