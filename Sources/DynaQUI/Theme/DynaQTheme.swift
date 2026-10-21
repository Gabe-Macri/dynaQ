import SwiftUI

/// Minimal Brutalist Terminal Studio Theme for dynaQ.
/// Strict professional aesthetic: monospace typography, sharp 1px borders, phosphor accents, zero bubbles or neon glow.
public enum DynaQTheme {
    // Canvas & Chassis
    public static let bg = Color(red: 0.04, green: 0.05, blue: 0.06)             // #0A0D10 Pure console black
    public static let surface = Color(red: 0.08, green: 0.09, blue: 0.11)        // #14171C Terminal card
    public static let surfaceElevated = Color(red: 0.12, green: 0.13, blue: 0.16)// #1F2229 Elevated cell
    public static let surfaceBorder = Color(red: 0.18, green: 0.20, blue: 0.24)  // #2E333D Crisp 1px border
    public static let surfaceBorderActive = Color(red: 0.32, green: 0.36, blue: 0.44) // Active focus border

    // Terminal CRT Phosphors & Indicators
    public static let phosphorGreen = Color(red: 0.22, green: 0.95, blue: 0.45)  // #38F273 CRT Phosphor Green
    public static let phosphorAmber = Color(red: 1.00, green: 0.70, blue: 0.18)  // #FFB32E Amber Warning / Solo
    public static let terminalCyan = Color(red: 0.20, green: 0.82, blue: 0.92)   // #33D1EB Precision Slate Cyan
    public static let terminalRed = Color(red: 1.00, green: 0.23, blue: 0.23)    // #FF3B3B Peak / Clip / Bypass
    public static let terminalBlue = Color(red: 0.29, green: 0.56, blue: 0.98)   // #4A8FFA Hardware Transport

    // Aliases for compatibility
    public static let green = phosphorGreen
    public static let amber = phosphorAmber
    public static let cyan = terminalCyan
    public static let red = terminalRed
    public static let blue = terminalBlue

    // Monospace Text Hierarchy
    public static let textPrimary = Color(white: 0.94)
    public static let textSecondary = Color(white: 0.64)
    public static let textMuted = Color(white: 0.38)

    // Measurement & Grid
    public static let gridLine = Color.white.opacity(0.06)
    public static let gridLineZero = Color.white.opacity(0.18)
    public static let gridText = Color(white: 0.45)

    // Industrial Band Colors (high contrast, distinct, zero neon glow)
    public static let bandColors: [Color] = [
        Color(red: 0.90, green: 0.35, blue: 0.35), // 01 Sub (Muted Crimson)
        Color(red: 0.95, green: 0.55, blue: 0.22), // 02 Bass (Warm Amber)
        Color(red: 0.90, green: 0.76, blue: 0.22), // 03 Low-Mid (Brass Gold)
        Color(red: 0.22, green: 0.85, blue: 0.45), // 04 Mid (CRT Green)
        Color(red: 0.18, green: 0.77, blue: 0.85), // 05 High-Mid (Teal)
        Color(red: 0.29, green: 0.53, blue: 0.97), // 06 Presence (Cobalt)
        Color(red: 0.62, green: 0.41, blue: 0.95), // 07 Brilliance (Violet)
        Color(red: 0.85, green: 0.32, blue: 0.62)  // 08 Air (Magenta)
    ]
}
