import SwiftUI

/// Ember's fixed dark palette - a plugin editor keeps its own look regardless of system appearance.
enum EmberPalette {
    static let backgroundTop = Color(red: 0.11, green: 0.095, blue: 0.095)
    static let backgroundBottom = Color(red: 0.055, green: 0.05, blue: 0.055)
    static let panel = Color.white.opacity(0.04)
    static let panelStroke = Color.white.opacity(0.07)
    static let track = Color.white.opacity(0.08)

    static let spark = Color(red: 1.0, green: 0.86, blue: 0.48)
    static let flame = Color(red: 1.0, green: 0.48, blue: 0.10)
    static let coal = Color(red: 0.84, green: 0.15, blue: 0.12)

    static let text = Color(red: 0.93, green: 0.90, blue: 0.87)
    static let mutedText = Color(red: 0.55, green: 0.51, blue: 0.48)

    static let heat = LinearGradient(colors: [coal, flame, spark], startPoint: .leading, endPoint: .trailing)

    /// Spark -> flame -> coal as `t` goes 0 -> 1 (precomputed so drawing never resolves colors).
    static func emberColor(_ t: Double) -> Color {
        let index = Int((min(max(t, 0), 1) * Double(emberRamp.count - 1)).rounded())
        return emberRamp[index]
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
