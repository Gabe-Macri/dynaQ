import SwiftUI

/// Unified Dark Pro Studio Theme for dynaQ.
public enum DynaQTheme {
    public static let bg = Color(red: 0.07, green: 0.08, blue: 0.10)
    public static let surface = Color(red: 0.11, green: 0.12, blue: 0.15)
    public static let surfaceElevated = Color(red: 0.15, green: 0.17, blue: 0.21)
    public static let surfaceBorder = Color(red: 0.22, green: 0.24, blue: 0.28)

    // Accents
    public static let cyan = Color(red: 0.05, green: 0.82, blue: 0.95)
    public static let blue = Color(red: 0.25, green: 0.55, blue: 1.0)
    public static let amber = Color(red: 1.0, green: 0.68, blue: 0.20)
    public static let green = Color(red: 0.22, green: 0.88, blue: 0.45)
    public static let red = Color(red: 0.96, green: 0.22, blue: 0.26)
    public static let purple = Color(red: 0.72, green: 0.35, blue: 0.98)

    // Text
    public static let textPrimary = Color(white: 0.96)
    public static let textSecondary = Color(white: 0.62)
    public static let textMuted = Color(white: 0.38)

    // Grid
    public static let gridLine = Color.white.opacity(0.06)
    public static let gridText = Color.white.opacity(0.35)

    // Band colors for multi-band visual distinction
    public static let bandColors: [Color] = [
        Color(red: 0.95, green: 0.35, blue: 0.35), // Red / Sub
        Color(red: 1.0, green: 0.60, blue: 0.20),  // Orange / Bass
        Color(red: 0.95, green: 0.85, blue: 0.25), // Yellow / Low-Mid
        Color(red: 0.25, green: 0.85, blue: 0.50), // Green / Mid
        Color(red: 0.15, green: 0.80, blue: 0.95), // Cyan / High-Mid
        Color(red: 0.40, green: 0.55, blue: 1.00), // Blue / Presence
        Color(red: 0.75, green: 0.40, blue: 0.95), // Purple / Brilliance
        Color(red: 0.95, green: 0.40, blue: 0.75), // Magenta / Air
    ]
}
