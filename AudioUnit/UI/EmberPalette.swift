import SwiftUI

/// Fire colours for the glow and the sparks. They are the same in every panel finish:
/// whatever the paint, an ember glows like an ember.
enum EmberPalette {
    static let spark = Color(red: 1.0, green: 0.86, blue: 0.48)
    static let flame = Color(red: 1.0, green: 0.48, blue: 0.10)
    static let coal = Color(red: 0.84, green: 0.15, blue: 0.12)

    /// Spark -> flame -> coal as `t` goes 0 -> 1 (precomputed so drawing never resolves colours).
    static func emberColor(_ t: Double) -> Color {
        let index = Int((min(max(t, 0), 1) * Double(emberRamp.count - 1)).rounded())
        return emberRamp[index]
    }

    /// The colour of something heated to `heat` (0...1): dull coal red when barely warm,
    /// through orange, to pale yellow when white-hot.
    static func glowColor(_ heat: Double) -> Color {
        emberColor(1 - heat)
    }

    private static let emberRamp: [Color] = (0..<24).map { step in
        let t = Double(step) / 23
        return t < 0.5 ? mix(spark, flame, t * 2) : mix(flame, coal, (t - 0.5) * 2)
    }

    private static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let a = a.resolve(in: EnvironmentValues())
        let b = b.resolve(in: EnvironmentValues())
        let t = Float(t)
        return Color(
            red: Double(a.red + (b.red - a.red) * t),
            green: Double(a.green + (b.green - a.green) * t),
            blue: Double(a.blue + (b.blue - a.blue) * t)
        )
    }
}
