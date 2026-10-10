import AppKit
import SwiftUI

/// Spacing scale used everywhere (4, 8, 12, 16, 20, 24).
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

enum Radius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 10
    static let large: CGFloat = 14
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// A colour that resolves differently in light and dark appearance.
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

/// Semantic colour tokens. Text and surfaces lean on system colours so contrast
/// adapts automatically; brand colours are tuned per appearance.
enum Palette {
    /// Brand amber, used for fills (progress, primary button). Text on it uses `ink`.
    static let accentNS = NSColor(hex: 0xFFBA30)
    /// Amber dark enough to read as text on light backgrounds (≈4.8:1 on white).
    static let accentTextNS = NSColor.dynamic(light: NSColor(hex: 0x8A5A00), dark: NSColor(hex: 0xFFC757))
    static let inkNS = NSColor(hex: 0x191B18)
    static let canvasNS = NSColor.dynamic(light: NSColor(hex: 0xFBFAF3), dark: NSColor(hex: 0x1E201C))
    static let secondaryTextNS = NSColor.dynamic(light: NSColor(hex: 0x6A6A5F), dark: NSColor(hex: 0xA9A99D))
    static let successNS = NSColor.dynamic(light: NSColor(hex: 0x3E7A4C), dark: NSColor(hex: 0x82C392))
    static let warningNS = NSColor.dynamic(light: NSColor(hex: 0x9A5B00), dark: NSColor(hex: 0xFFBA30))
    static let trackNS = NSColor.dynamic(light: NSColor(hex: 0x191B18, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.10))
    static let cardNS = NSColor.dynamic(light: NSColor(white: 1, alpha: 0.75), dark: NSColor(white: 1, alpha: 0.05))

    static let accent = Color(nsColor: accentNS)
    static let accentText = Color(nsColor: accentTextNS)
    static let ink = Color(nsColor: inkNS)
    static let canvas = Color(nsColor: canvasNS)
    static let secondaryText = Color(nsColor: secondaryTextNS)
    static let success = Color(nsColor: successNS)
    static let warning = Color(nsColor: warningNS)
    static let track = Color(nsColor: trackNS)
    static let card = Color(nsColor: cardNS)
    static let separator = Color(nsColor: .separatorColor)
}

enum Typography {
    static let countdown = Font.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit()
    static let largeCountdown = Font.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit()
    static let title = Font.system(size: 15, weight: .semibold)
    static let metricValue = Font.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit()
    static let label = Font.system(size: 13)
    static let caption = Font.system(size: 11)
}
