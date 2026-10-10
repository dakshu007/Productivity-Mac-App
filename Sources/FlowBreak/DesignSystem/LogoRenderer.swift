import AppKit
import SwiftUI

/// Draws the FlowBreak symbol (open "flow" ring + leaf sprouting through its gap).
/// Geometry matches Scripts/generate_icons.py, in a unit square with y pointing down.
enum LogoRenderer {
    private static let ringRadius: CGFloat = 0.34
    private static let ringWidth: CGFloat = 0.105
    private static let gapCenter: CGFloat = -45
    private static let gap: CGFloat = 62
    private static let base = CGPoint(x: 0.35, y: 0.65)
    private static let tip = CGPoint(x: 0.85, y: 0.15)
    private static let leafWidth: CGFloat = 0.25
    private static let midribWidth: CGFloat = 0.032
    private static let midribRange: (CGFloat, CGFloat) = (0.16, 0.60)
    private static let stemLength: CGFloat = 0.05
    private static let stemWidth: CGFloat = 0.055

    /// Draws the symbol filling `rect` in `context` (a normal, y-up AppKit context).
    static func draw(in context: CGContext, rect: CGRect, color: CGColor, midrib: Bool) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: rect.width, y: -rect.height)
        context.setFillColor(color)
        context.setStrokeColor(color)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Ring
        let start = gapCenter + gap / 2
        let sweep = 360 - gap
        var ring: [CGPoint] = []
        let steps = 120
        for i in 0...steps {
            let angle = (start + sweep * CGFloat(i) / CGFloat(steps)) * .pi / 180
            ring.append(CGPoint(x: 0.5 + ringRadius * cos(angle), y: 0.5 + ringRadius * sin(angle)))
        }
        context.setLineWidth(ringWidth)
        context.addLines(between: ring)
        context.strokePath()

        // Leaf axis
        let length = hypot(tip.x - base.x, tip.y - base.y)
        let ux = (tip.x - base.x) / length
        let uy = (tip.y - base.y) / length
        let nx = -uy
        let ny = ux

        // Stem
        context.setLineWidth(stemWidth)
        context.move(to: CGPoint(x: base.x - ux * stemLength, y: base.y - uy * stemLength))
        context.addLine(to: CGPoint(x: base.x + ux * 0.04, y: base.y + uy * 0.04))
        context.strokePath()

        // Leaf
        var sideA: [CGPoint] = []
        var sideB: [CGPoint] = []
        let leafSteps = 64
        for i in 0...leafSteps {
            let t = CGFloat(i) / CGFloat(leafSteps)
            let half = (leafWidth / 2) * pow(sin(.pi * t), 0.9) * (1.12 - 0.24 * t)
            let cx = base.x + ux * length * t
            let cy = base.y + uy * length * t
            sideA.append(CGPoint(x: cx + nx * half, y: cy + ny * half))
            sideB.append(CGPoint(x: cx - nx * half, y: cy - ny * half))
        }
        context.addLines(between: sideA + Array(sideB.reversed()))
        context.closePath()
        context.fillPath()

        // Midrib, cut out of the leaf.
        if midrib {
            context.setBlendMode(.clear)
            context.setLineWidth(midribWidth)
            context.move(to: CGPoint(x: base.x + (tip.x - base.x) * midribRange.0, y: base.y + (tip.y - base.y) * midribRange.0))
            context.addLine(to: CGPoint(x: base.x + (tip.x - base.x) * midribRange.1, y: base.y + (tip.y - base.y) * midribRange.1))
            context.strokePath()
            context.setBlendMode(.normal)
        }
    }

    static func image(size: CGFloat, color: NSColor, midrib: Bool = true, template: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: context, rect: rect, color: color.cgColor, midrib: midrib)
            return true
        }
        image.isTemplate = template
        return image
    }

    /// Monochrome template for the menu bar; macOS tints it for light/dark/highlighted.
    static func menuBarImage() -> NSImage {
        let icon = image(size: 18, color: .black, midrib: false, template: true)
        icon.accessibilityDescription = "FlowBreak"
        return icon
    }
}

/// The brand symbol on an ink tile, as used in the popover and windows.
struct BrandMark: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Palette.ink)
            Image(nsImage: LogoRenderer.image(size: size * 0.8, color: Palette.accentNS, midrib: size >= 28))
                .resizable()
                .frame(width: size * 0.8, height: size * 0.8)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
