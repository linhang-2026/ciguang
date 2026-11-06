import CoreText
import Metal
import UIKit

let DIORAMA_RASTER_FONT_PX = 128.0
private let DEFAULT_FONT_WEIGHT = 700.0
private let LINE_BAND_EM = 1.4
private let PLAIN_PAD_EM = 0.2
private let GLOW_PAD_EM = 0.7
private let MAX_CANVAS_PX = 4096.0
private let GLOW_BLUR_EM = 0.16

struct DioramaLineRaster {
    let texture: MTLTexture
    let canvasWidthPx: Double
    let canvasHeightPx: Double
        let advancePx: Double
        let fontPx: Double

        var worldPerPx: Double { DIORAMA_LINE_FONT_SIZE / fontPx }
    var worldWidth: Double { advancePx * worldPerPx }
    var halfSize: (w: Double, h: Double) {
        (canvasWidthPx * worldPerPx / 2, canvasHeightPx * worldPerPx / 2)
    }
}

enum DioramaTextRaster {
                    private static func makeFont(fontPx: Double) -> CTFont {
        UIFont.systemFont(ofSize: CGFloat(fontPx), weight: .bold) as CTFont
    }

    private static func makeAttributes(fontPx: Double) -> [NSAttributedString.Key: Any] {
        [
            .font: makeFont(fontPx: fontPx),
            .foregroundColor: UIColor.white,
        ]
    }

                static func measure(_ text: String, fontPx: Double) -> Double {
        let attr = NSAttributedString(string: text, attributes: makeAttributes(fontPx: fontPx))
        let line = CTLineCreateWithAttributedString(attr)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return 0 }
        var width: Double = 0
        for run in runs {
            width += CTRunGetTypographicBounds(run, CFRangeMake(0, 0), nil, nil, nil)
        }
        return width
    }

                static func rasterLine(_ text: String, device: MTLDevice) -> DioramaLineRaster? {
        guard !text.isEmpty else { return nil }
        var fontPx = DIORAMA_RASTER_FONT_PX
        var advancePx = max(1, ceil(measure(text, fontPx: fontPx)))
        let pad = ceil(fontPx * PLAIN_PAD_EM)

                if advancePx + pad * 2 > MAX_CANVAS_PX {
            let shrink = (MAX_CANVAS_PX - pad * 2) / advancePx
            fontPx = max(24, floor(fontPx * shrink))
            advancePx = max(1, ceil(measure(text, fontPx: fontPx)))
        }
        let canvasWidthPx = advancePx + pad * 2
        let canvasHeightPx = ceil(fontPx * LINE_BAND_EM) + pad * 2

        let w = Int(canvasWidthPx), h = Int(canvasHeightPx)
        guard w > 0, h > 0 else { return nil }

                let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setShouldAntialias(true)
        ctx.setAllowsFontSubpixelQuantization(true)

        let attr = NSAttributedString(string: text, attributes: makeAttributes(fontPx: fontPx))
        let ctLine = CTLineCreateWithAttributedString(attr)

                let ink = CTLineGetImageBounds(ctLine, ctx)
        let drawX: CGFloat = pad
        let drawY: CGFloat
        if ink.width > 0 || ink.height > 0 {
            drawY = CGFloat(h) / 2 - ink.midY
        } else {
            drawY = CGFloat(h) / 2 - fontPx * 0.36
        }
        ctx.textPosition = CGPoint(x: drawX, y: drawY)
        CTLineDraw(ctLine, ctx)

                guard let data = ctx.data else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false
        )
        desc.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }

        let rowBytes = w * 4
        var flipped = [UInt8](repeating: 0, count: rowBytes * h)
        let src = data.assumingMemoryBound(to: UInt8.self)
        flipped.withUnsafeMutableBufferPointer { dst in
            for row in 0..<h {
                memcpy(dst.baseAddress! + row * rowBytes, src + (h - 1 - row) * rowBytes, rowBytes)
            }
        }
        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: flipped, bytesPerRow: rowBytes)

        return DioramaLineRaster(
            texture: texture, canvasWidthPx: canvasWidthPx, canvasHeightPx: canvasHeightPx,
            advancePx: advancePx, fontPx: fontPx
        )
    }

            struct DioramaUnitRaster {
        let baseTexture: MTLTexture
        let glowTexture: MTLTexture
                let canvasWidthPx: Double
        let canvasHeightPx: Double
                let advancePx: Double
    }

        private static func uploadTexture(_ ctx: CGContext, _ device: MTLDevice) -> MTLTexture? {
        guard let data = ctx.data else { return nil }
        let w = ctx.width, h = ctx.height
        guard w > 0, h > 0 else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false
        )
        desc.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        let rowBytes = w * 4
        var flipped = [UInt8](repeating: 0, count: rowBytes * h)
        let src = data.assumingMemoryBound(to: UInt8.self)
        flipped.withUnsafeMutableBufferPointer { dst in
            for row in 0..<h {
                memcpy(dst.baseAddress! + row * rowBytes, src + (h - 1 - row) * rowBytes, rowBytes)
            }
        }
        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: flipped, bytesPerRow: rowBytes)
        return texture
    }

        private static func makeContext(w: Int, h: Int) -> CGContext? {
        let space = CGColorSpaceCreateDeviceRGB()
        return CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

                        private static func drawGlowGlyph(_ ctx: CGContext, _ ctLine: CTLine, drawX: CGFloat, baseline: CGFloat, blur: CGFloat) {
        let OFFSCREEN: CGFloat = 10000
        ctx.setBlendMode(.plusLighter)
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        let haloPass: (CGFloat, CGFloat) -> Void = { passBlur, alpha in
            ctx.setShadow(
                offset: CGSize(width: OFFSCREEN, height: 0),
                blur: passBlur / 2,
                color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha)
            )
            ctx.textPosition = CGPoint(x: drawX - OFFSCREEN, y: baseline)
            CTLineDraw(ctLine, ctx)
        }
        haloPass(blur, 0.95)
        haloPass(blur, 0.85)
        haloPass(blur * 2, 0.55)
        haloPass(blur * 2.9, 0.3)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setBlendMode(.normal)
    }

            static func rasterUnit(_ text: String, device: MTLDevice) -> DioramaUnitRaster? {
        guard !text.isEmpty else { return nil }
        let em = DIORAMA_RASTER_FONT_PX
        let pad = ceil(em * GLOW_PAD_EM)
        let advancePx = max(1.0, ceil(measure(text, fontPx: em)))
        let canvasWidthPx = advancePx + pad * 2
        let canvasHeightPx = ceil(em * LINE_BAND_EM) + pad * 2

        let w = Int(canvasWidthPx), h = Int(canvasHeightPx)
        guard w > 0, h > 0 else { return nil }

        let font = makeFont(fontPx: em)
        let attr = NSAttributedString(string: text, attributes: makeAttributes(fontPx: em))
        let ctLine = CTLineCreateWithAttributedString(attr)
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
                let baseline = CGFloat(h) / 2 - CGFloat(ascent - descent) / 2
        let drawX = CGFloat(pad)

        guard let baseCtx = makeContext(w: w, h: h), let glowCtx = makeContext(w: w, h: h) else { return nil }
        for ctx in [baseCtx, glowCtx] {
            ctx.setShouldAntialias(true)
            ctx.setAllowsFontSubpixelQuantization(true)
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
                baseCtx.textPosition = CGPoint(x: drawX, y: baseline)
        CTLineDraw(ctLine, baseCtx)
                drawGlowGlyph(glowCtx, ctLine, drawX: drawX, baseline: baseline, blur: em * GLOW_BLUR_EM)

        guard let baseTexture = uploadTexture(baseCtx, device),
              let glowTexture = uploadTexture(glowCtx, device) else { return nil }
        return DioramaUnitRaster(
            baseTexture: baseTexture, glowTexture: glowTexture,
            canvasWidthPx: canvasWidthPx, canvasHeightPx: canvasHeightPx, advancePx: advancePx
        )
    }
}

final class DioramaLineRasterCache {
    private var rasters: [Int: DioramaLineRaster] = [:]
    private weak var device: MTLDevice?

    init(device: MTLDevice) {
        self.device = device
    }

    func raster(at index: Int) -> DioramaLineRaster? {
        rasters[index]
    }

        @discardableResult
    func ensureSync(_ index: Int, text: String) -> DioramaLineRaster? {
        if let cached = rasters[index] { return cached }
        guard let device, let raster = DioramaTextRaster.rasterLine(text, device: device) else { return nil }
        rasters[index] = raster
        return raster
    }

        func fillBudget(visible: [(index: Int, text: String)], budget: Int = DIORAMA_NEIGHBOR_RASTER_BUDGET) {
        guard let device else { return }
        var built = 0
        for entry in visible where rasters[entry.index] == nil {
            guard built < budget else { break }
            if let raster = DioramaTextRaster.rasterLine(entry.text, device: device) {
                rasters[entry.index] = raster
                built += 1
            }
        }
    }

        func prune(keep: Set<Int>) {
        for (index, raster) in rasters where !keep.contains(index) {
            _ = raster
            rasters[index] = nil
        }
    }
}
