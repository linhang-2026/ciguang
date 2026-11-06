import MetalKit
import SwiftUI
import simd

private let dioramaShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct DioramaTextUniforms {
    float4x4 viewProj;
    float3 camPos;
    float fogNear;
    float fogFar;
    float4 fogColor;
};

struct DioramaInstanceGPU {
    float3 position;
    float4 quaternion;
    float2 halfSize;
    float opacity;
    float4 color;
};

struct VOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float fog;
};

float3 qrot(float4 q, float3 v) {
    return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}

vertex VOut diorama_text_vertex(uint vid [[vertex_id]],
                                constant DioramaTextUniforms &u [[buffer(0)]],
                                constant DioramaInstanceGPU &in [[buffer(1)]]) {
    float2 corner = float2(float(vid & 1) * 2.0 - 1.0, float(vid >> 1) * 2.0 - 1.0);

    float2 uv = float2(float(vid & 1), float(vid >> 1));
    float3 local = float3(corner.x * in.halfSize.x, corner.y * in.halfSize.y, 0.0);
    float3 world = in.position + qrot(in.quaternion, local);
    VOut out;
    out.position = u.viewProj * float4(world, 1.0);
    out.uv = uv;
    out.color = float4(in.color.rgb, in.opacity);
    float dist = length(world - u.camPos);
    out.fog = clamp((dist - u.fogNear) / (u.fogFar - u.fogNear), 0.0, 1.0);
    return out;
}

fragment float4 diorama_text_fragment(VOut in [[stage_in]],
                                      texture2d<float> tex [[texture(0)]],
                                      sampler samp [[sampler(0)]],
                                      constant DioramaTextUniforms &u [[buffer(0)]]) {
    float4 t = tex.sample(samp, in.uv);
    float a = t.a * in.color.a;
    float3 tinted = in.color.rgb * a;
    tinted = mix(tinted, u.fogColor.rgb * a, in.fog);
    return float4(tinted, a);
}
"""

private struct DioramaTextUniformsGPU {
    var viewProj: simd_float4x4
    var camPos: SIMD3<Float>
    var fogNear: Float
    var fogFar: Float
    var fogColor: SIMD4<Float>
}

private struct DioramaInstanceGPU {
    var position: SIMD3<Float>
    var quaternion: SIMD4<Float>
    var halfSize: SIMD2<Float>
    var opacity: Float
    var color: SIMD4<Float>
}

struct DioramaLyricsView: UIViewRepresentable {
    let scheduler: LyricScheduler
    let theme: ThemeColors
        let sceneKey: String

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
                view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.delegate = context.coordinator
        context.coordinator.applyScene(scheduler: scheduler, theme: theme, sceneKey: sceneKey)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.applyScene(scheduler: scheduler, theme: theme, sceneKey: sceneKey)
                let scale = min(UIScreen.main.scale, 2)
        let target = CGSize(width: uiView.bounds.width * scale, height: uiView.bounds.height * scale)
        if uiView.bounds.width > 0, uiView.drawableSize != target {
            uiView.drawableSize = target
        }
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        private let device: MTLDevice?
        private let queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
                private var additivePipeline: MTLRenderPipelineState?
        private var sampler: MTLSamplerState?

                private var sceneKey = ""
        private var scheduler: LyricScheduler?
        private var lines: [LyricLine] = []
        private var frames: [DioramaFrame] = []
        private var rasterCache: DioramaLineRasterCache?
        private let camera = DioramaCamera()
        private var stickyIndex = 0

                private var unitState = DioramaActiveUnitState()
        private var activeUnitsCache: (lineID: Int, units: [DioramaLyricUnit],
                                       placed: [DioramaPlacedUnit], lineWidth: Double)?

                private var colorTargets: (primary: SIMD4<Float>, accent: SIMD4<Float>,
                                   secondary: SIMD4<Float>, bg: SIMD4<Float>)?
        private var damped: (primary: SIMD4<Float>, accent: SIMD4<Float>,
                             secondary: SIMD4<Float>, bg: SIMD4<Float>)?

        private var lastWall: CFTimeInterval?

                private var particleField: DioramaParticleFieldRenderer?

        override init() {
            device = MTLCreateSystemDefaultDevice()
            queue = device?.makeCommandQueue()
            super.init()
            buildPipelines()
            if let device {
                particleField = DioramaParticleFieldRenderer(device: device)
            }
        }

        func applyScene(scheduler: LyricScheduler, theme: ThemeColors, sceneKey: String) {
            colorTargets = (
                rgba(theme.primary), rgba(theme.accent), rgba(theme.secondary), rgba(theme.background)
            )
            self.scheduler = scheduler
            guard self.sceneKey != sceneKey else { return }
            self.sceneKey = sceneKey
            lines = scheduler.lyrics.lines
                        let seed = sceneKey
            frames = buildDioramaPath(lines.count, seed: seed)
                        particleField?.cacheScene(frames: frames, seed: seed)
            particleField?.resetForNewScene(seed: seed)
            if let device {
                rasterCache = DioramaLineRasterCache(device: device)
            }
            camera.reset()
            stickyIndex = 0
            activeUnitsCache = nil
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
                let lib = try device.makeLibrary(source: dioramaShaderSource, options: nil)
                let desc = MTLRenderPipelineDescriptor()
                desc.vertexFunction = lib.makeFunction(name: "diorama_text_vertex")
                desc.fragmentFunction = lib.makeFunction(name: "diorama_text_fragment")
                desc.colorAttachments[0].pixelFormat = .bgra8Unorm
                desc.colorAttachments[0].isBlendingEnabled = true
                desc.colorAttachments[0].sourceRGBBlendFactor = .one
                desc.colorAttachments[0].sourceAlphaBlendFactor = .one
                desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
                pipeline = try? device.makeRenderPipelineState(descriptor: desc)

                                                let addDesc = MTLRenderPipelineDescriptor()
                addDesc.vertexFunction = lib.makeFunction(name: "diorama_text_vertex")
                addDesc.fragmentFunction = lib.makeFunction(name: "diorama_text_fragment")
                addDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
                addDesc.colorAttachments[0].isBlendingEnabled = true
                addDesc.colorAttachments[0].sourceRGBBlendFactor = .one
                addDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
                addDesc.colorAttachments[0].destinationRGBBlendFactor = .one
                addDesc.colorAttachments[0].destinationAlphaBlendFactor = .one
                additivePipeline = try? device.makeRenderPipelineState(descriptor: addDesc)

                let s = MTLSamplerDescriptor()
                s.minFilter = .linear
                s.magFilter = .linear
                s.sAddressMode = .clampToEdge
                s.tAddressMode = .clampToEdge
                sampler = device.makeSamplerState(descriptor: s)
            } catch {
                assertionFailure("Diorama shader 编译失败: \(error)")
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let queue, let pipeline, let sampler,
                  view.drawableSize.width > 0, view.drawableSize.height > 0,
                  let drawable = view.currentDrawable,
                  let rpd = view.currentRenderPassDescriptor
            else { return }
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            guard let cmd = queue.makeCommandBuffer(),
                  let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
            enc.setRenderPipelineState(pipeline)
            enc.setFragmentSamplerState(sampler, index: 0)
            enc.setCullMode(.none)

            if !lines.isEmpty, let rasterCache {
                drawLyrics(enc: enc, view: view, cache: rasterCache)
            }
            enc.endEncoding()
            cmd.present(drawable)
            cmd.commit()
        }

        private func drawLyrics(enc: MTLRenderCommandEncoder, view: MTKView, cache: DioramaLineRasterCache) {
            let now = PlayerCenter.shared.lyricClock
            let wall = CACurrentMediaTime()
            let dt = min(max(wall - (lastWall ?? wall), 0.001), 0.1)
            lastWall = wall

            let aspect = Double(view.drawableSize.width / view.drawableSize.height)
            let fovDeg = 55.0

                        if let targets = colorTargets {
                if damped == nil {
                    damped = targets
                }
                let k = Float(1 - exp(-DIORAMA_COLOR_DAMP_RATE * dt))
            damped!.primary = lerp(damped!.primary, targets.primary, k)
            damped!.accent = lerp(damped!.accent, targets.accent, k)
            damped!.secondary = lerp(damped!.secondary, targets.secondary, k)
            damped!.bg = lerp(damped!.bg, targets.bg, k)
            }
            guard let damped else { return }

                        if let i = scheduler?.activeLineIndex(at: now) {
                stickyIndex = i
            } else if stickyIndex >= lines.count {
                stickyIndex = max(lines.count - 1, 0)
            }
            let globalIndex = min(stickyIndex, lines.count - 1)

                                    let frame = getFrame(frames, globalIndex)
            let line: LyricLine? = globalIndex < lines.count ? lines[globalIndex] : nil
            camera.step(
                now: now, delta: dt, frame: frame, line: line, lineIndex: globalIndex,
                seed: sceneKey, motion: .stageDefault, fovDeg: fovDeg, aspect: aspect
            )

                        if let field = particleField, let targets = colorTargets, !frames.isEmpty {
                let audio = PlayerCenter.shared.analysis.snapshot()
                                                let moteColor = simd_mix(
                    dioramaLinearFromSRGB(SIMD3<Float>(damped.secondary.x, damped.secondary.y, damped.secondary.z)),
                    dioramaLinearFromSRGB(SIMD3<Float>(damped.accent.x, damped.accent.y, damped.accent.z)),
                    SIMD3<Float>(repeating: 0.3))
                field.update(
                    delta: dt, wallTime: wall, playbackTime: max(0, now), globalIndex: globalIndex,
                    bass255: audio.bass, lowMid255: audio.lowMid, mid255: audio.mid,
                    treble255: audio.treble, power255: audio.power,
                    frameViewProj: viewProjMatrix(fovDeg: fovDeg, aspect: aspect),
                    camPos: camera.camPos, drawableHeight: Float(view.drawableSize.height),
                    themeTargets: (
                        primary: dioramaLinearFromSRGB(SIMD3<Float>(targets.primary.x, targets.primary.y, targets.primary.z)),
                        accent: dioramaLinearFromSRGB(SIMD3<Float>(targets.accent.x, targets.accent.y, targets.accent.z)),
                        secondary: dioramaLinearFromSRGB(SIMD3<Float>(targets.secondary.x, targets.secondary.y, targets.secondary.z))
                    ),
                    backgroundColor: dioramaLinearFromSRGB(SIMD3<Float>(targets.bg.x, targets.bg.y, targets.bg.z)),
                    moteColor: moteColor
                )
                field.drawMotes(enc)
            }

                        let mounted = dioramaMountedIndices(globalIndex, total: lines.count)
            let visible = buildDioramaVisibleLines(
                frames: frames, lines: lines, mountedIndices: mounted,
                globalIndex: globalIndex, seed: sceneKey, weaveScale: DioramaMotionParams.stageDefault.weaveScale
            )

                                                            if globalIndex >= 1, let prev = visible.first(where: { $0.index == globalIndex - 1 }) {
                cache.ensureSync(prev.index, text: prev.text)
            }
            cache.fillBudget(visible: visible.map { ($0.index, $0.text) })
            cache.prune(keep: Set(mounted))

                                    for entry in visible where entry.index != globalIndex {
                guard let raster = cache.raster(at: entry.index) else { continue }
                let offset = entry.index - globalIndex
                let opacity = resolveNeighborLineOpacity(offset)
                guard opacity > 0 else { continue }
                let fit = resolveFrameFitScale(raster.worldWidth, DIORAMA_HERO_DISTANCE, fovDeg, aspect)
                    * entry.placement.scale
                let life = resolveTextLife(distance(entry.position, SIMD3<Double>(camera.camPos)))
                drawQuad(
                    enc: enc, view: view, texture: raster.texture, pipeline: pipeline,
                    position: entry.position, quaternion: entry.quaternion,
                    halfSize: raster.halfSize, fit: fit, swell: 1,
                    color: offset < 0 ? damped.primary : damped.secondary,
                    opacity: opacity * life, fogColor: damped.bg
                )
            }

                                    particleField?.drawCorridor(enc)

                                                            if let activeEntry = visible.first(where: { $0.index == globalIndex }),
               let device, globalIndex < lines.count {
                let line = lines[globalIndex]
                                if activeUnitsCache?.lineID != line.id {
                    if line.plainText.isEmpty {
                        activeUnitsCache = nil
                    } else {
                        let timeline = DioramaGraphemes.lineTimeline(line)
                        let units = splitDioramaLyricUnits(line, timeline)
                        activeUnitsCache = layoutDioramaActiveUnits(line, units, device: device)
                            .map { (lineID: line.id, units: units, placed: $0.units, lineWidth: $0.lineWidth) }
                    }
                }

                if let unitCache = activeUnitsCache, !unitCache.placed.isEmpty {
                    let fit = resolveFrameFitScale(unitCache.lineWidth, DIORAMA_HERO_DISTANCE, fovDeg, aspect)
                        * activeEntry.placement.scale
                                        camera.activeLineWidth = unitCache.lineWidth * fit
                    let life = resolveTextLife(distance(activeEntry.position, SIMD3<Double>(camera.camPos)))
                                        let breath = 0.9 + 0.1 * sin(wall * 1.9)
                    let power01 = min(1, PlayerCenter.shared.analysis.snapshot().power / 255)
                    let values = unitState.update(
                        units: unitCache.units, lineID: line.id, globalIndex: globalIndex,
                        now: now, delta: dt, life: life, breath: breath, power01: power01,
                        primary: damped.primary, accent: damped.accent
                    )

                                        let quat = activeEntry.quaternion
                    func unitWorld(_ x: Double, _ y: Double, _ z: Double) -> SIMD3<Double> {
                        activeEntry.position + quat.act(SIMD3(x, y, z)) * fit
                    }
                                        for (i, placed) in unitCache.placed.enumerated() where values[i].glowVisible {
                        drawQuad(
                            enc: enc, view: view, texture: placed.raster.glowTexture,
                            pipeline: additivePipeline,
                            position: unitWorld(placed.centerX, 0, -0.01), quaternion: quat,
                            halfSize: (placed.width / 2, placed.height / 2), fit: fit, swell: 1,
                            color: values[i].fill, opacity: values[i].glowOpacity, fogColor: damped.bg
                        )
                    }
                                        for (i, placed) in unitCache.placed.enumerated() where values[i].soulVisible {
                        drawQuad(
                            enc: enc, view: view, texture: placed.raster.baseTexture,
                            pipeline: additivePipeline,
                            position: unitWorld(placed.centerX, values[i].soulLiftY, -0.005), quaternion: quat,
                            halfSize: (placed.width / 2, placed.height / 2), fit: fit, swell: values[i].soulSwell,
                            color: values[i].fill, opacity: values[i].soulOpacity, fogColor: damped.bg
                        )
                    }
                                        for (i, placed) in unitCache.placed.enumerated() {
                        drawQuad(
                            enc: enc, view: view, texture: placed.raster.baseTexture,
                            pipeline: pipeline,
                            position: unitWorld(placed.centerX, 0, 0), quaternion: quat,
                            halfSize: (placed.width / 2, placed.height / 2), fit: fit, swell: 1,
                            color: values[i].fill, opacity: values[i].baseOpacity, fogColor: damped.bg
                        )
                    }
                } else if let raster = cache.raster(at: globalIndex) {
                                        let fit = resolveFrameFitScale(raster.worldWidth, DIORAMA_HERO_DISTANCE, fovDeg, aspect)
                        * activeEntry.placement.scale
                    camera.activeLineWidth = raster.worldWidth * fit
                    let life = resolveTextLife(distance(activeEntry.position, SIMD3<Double>(camera.camPos)))
                    drawQuad(
                        enc: enc, view: view, texture: raster.texture, pipeline: pipeline,
                        position: activeEntry.position, quaternion: activeEntry.quaternion,
                        halfSize: raster.halfSize, fit: fit, swell: 1,
                        color: damped.primary,
                        opacity: DIORAMA_ACTIVE_LINE_OPACITY * life, fogColor: damped.bg
                    )
                } else {
                    camera.activeLineWidth = 0
                }
            } else {
                camera.activeLineWidth = 0
            }
        }

                private func lerp(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ k: Float) -> SIMD4<Float> {
            a + (b - a) * k
        }

                private func projection(fovDeg: Double, aspect: Double) -> simd_float4x4 {
            let fovRad = fovDeg * Double.pi / 180
            let fy: Float = Float(1 / tan(fovRad / 2))
            let ax: Float = Float(aspect)
            let near: Float = 0.1
            let far: Float = 2000
            return simd_float4x4(columns: (
                SIMD4<Float>(fy / ax, 0, 0, 0),
                SIMD4<Float>(0, fy, 0, 0),
                SIMD4<Float>(0, 0, far / (near - far), -1),
                SIMD4<Float>(0, 0, near * far / (near - far), 0)
            ))
        }

                private func viewProjMatrix(fovDeg: Double, aspect: Double) -> simd_float4x4 {
            let camQ = camera.camQuat
            let camQF = simd_quatf(vector: SIMD4<Float>(
                Float(camQ.vector.x), Float(camQ.vector.y),
                Float(camQ.vector.z), Float(camQ.vector.w)
            ))
            var camWorld = simd_float4x4(camQF)
            camWorld.columns.3 = SIMD4<Float>(
                Float(camera.camPos.x), Float(camera.camPos.y), Float(camera.camPos.z), 1
            )
            return projection(fovDeg: fovDeg, aspect: aspect) * camWorld.inverse
        }

        private func drawQuad(enc: MTLRenderCommandEncoder, view: MTKView,
                              texture: MTLTexture?, pipeline: MTLRenderPipelineState?,
                              position: SIMD3<Double>, quaternion: simd_quatd,
                              halfSize: (w: Double, h: Double), fit: Double, swell: Double,
                              color: SIMD4<Float>, opacity: Double, fogColor: SIMD4<Float>) {
            guard let pipeline, let texture else { return }

            let aspect = Double(view.drawableSize.width / view.drawableSize.height)
            let proj = projection(fovDeg: 55, aspect: aspect)

                                                            let camQ = camera.camQuat
            let camQF = simd_quatf(vector: SIMD4<Float>(
                Float(camQ.vector.x), Float(camQ.vector.y),
                Float(camQ.vector.z), Float(camQ.vector.w)
            ))
            var camWorld = simd_float4x4(camQF)
            camWorld.columns.3 = SIMD4<Float>(
                Float(camera.camPos.x), Float(camera.camPos.y), Float(camera.camPos.z), 1
            )
            let viewMat = camWorld.inverse

            let posF = SIMD3<Float>(position)
            var uniforms = DioramaTextUniformsGPU(
                viewProj: proj * viewMat,
                camPos: posF,
                fogNear: Float(DIORAMA_FOG_NEAR),
                fogFar: Float(DIORAMA_FOG_FAR),
                fogColor: fogColor
            )
            var instance = DioramaInstanceGPU(
                position: posF,
                quaternion: SIMD4<Float>(Float(quaternion.vector.x), Float(quaternion.vector.y),
                                        Float(quaternion.vector.z), Float(quaternion.vector.w)),
                halfSize: SIMD2<Float>(Float(halfSize.w * fit * swell), Float(halfSize.h * fit * swell)),
                opacity: Float(opacity),
                color: color
            )
            enc.setRenderPipelineState(pipeline)
            enc.setVertexBytes(&uniforms, length: MemoryLayout<DioramaTextUniformsGPU>.stride, index: 0)
            enc.setVertexBytes(&instance, length: MemoryLayout<DioramaInstanceGPU>.stride, index: 1)
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<DioramaTextUniformsGPU>.stride, index: 0)
            enc.setFragmentTexture(texture, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }
}
