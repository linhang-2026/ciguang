import SwiftUI

struct ThemeColors: Sendable {
    var primary: Color
    var accent: Color
    var secondary: Color
    var background: Color

    static let gold = Color(red: 0.96, green: 0.78, blue: 0.29)
    static let cream = Color(red: 0.98, green: 0.95, blue: 0.88)

    static let fallback = ThemeColors(
        primary: cream,
        accent: gold,
        secondary: Color(red: 0.45, green: 0.78, blue: 0.80),
        background: Color(red: 0.028, green: 0.045, blue: 0.088)
    )

        static func from(dominant: Color) -> ThemeColors {
        let ui = UIColor(dominant)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let hue = Double(h)

                let coverWeight = 0.55 + 0.45 * min(max(Double(s), 0) / 0.7, 1)

        return ThemeColors(
            primary: Color(hue: hue, saturation: 0.18, brightness: 0.93),
            accent: Color(hue: (hue + 40 / 360).truncatingRemainder(dividingBy: 1),
                          saturation: 0.7, brightness: 0.62),
            secondary: Color(hue: (hue + 20 / 360).truncatingRemainder(dividingBy: 1),
                             saturation: 0.3, brightness: 0.7),
            background: Color(hue: hue,
                               saturation: max(0.04, 0.28 * coverWeight),
                               brightness: 0.09)
        )
    }
}
