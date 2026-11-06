import SwiftUI

struct LatticeBackdrop: View {
    let theme: ThemeColors

    var body: some View {
        ZStack {
            Color(white: 0.028)
            RadialGradient(
                colors: [theme.accent.opacity(0.16), .clear],
                center: UnitPoint(x: 0.14, y: 0.12),
                startRadius: 0, endRadius: 360
            )
            RadialGradient(
                colors: [theme.secondary.opacity(0.20), .clear],
                center: UnitPoint(x: 0.86, y: 0.82),
                startRadius: 0, endRadius: 400
            )
            vignette
            GrainOverlay()
        }
        .ignoresSafeArea()
    }

        private var vignette: some View {
        RadialGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.78),
                .init(color: .black.opacity(0.52), location: 1.0),
            ],
            center: .center,
            startRadius: 40,
            endRadius: 950
        )
    }
}

struct GrainOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            var state: UInt64 = 0x9E37_79B9_7F4A_7C15
            func rnd() -> Double {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double((state >> 33) % 1000) / 1000
            }
            let step: CGFloat = 3
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let shade = rnd()
                    let rect = CGRect(x: x, y: y, width: step, height: step)
                                        let color: Color = rnd() > 0.5 ? .white.opacity(shade) : .black.opacity(shade)
                    ctx.fill(Path(rect), with: .color(color))
                    x += step
                }
                y += step
            }
        }
        .opacity(0.13)
        .blendMode(.softLight)
        .allowsHitTesting(false)
    }
}
