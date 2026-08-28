import AppKit
import ClaudeBarCore

enum Side {
    case left, right
}

enum NotchShape {
    /// The rail: a tab hanging off the menu bar. Its top edge is flush with the
    /// bar and the two upper corners curve *outward*, so the black reads as one
    /// continuous surface with the bar above it — the same trick the notch uses.
    /// `body` is the visible rectangle; the concave corners occupy `ear` points
    /// on either side of it.
    static func tab(body: CGRect, ear: CGFloat, bottomRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let r = min(ear, body.height / 2)
        let b = min(bottomRadius, min(body.width, body.height) / 2)

        path.move(to: CGPoint(x: body.minX - r, y: body.maxY))
        path.addArc(center: CGPoint(x: body.minX - r, y: body.maxY - r),
                    radius: r, startAngle: .pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + b))
        path.addArc(center: CGPoint(x: body.minX + b, y: body.minY + b),
                    radius: b, startAngle: .pi, endAngle: 1.5 * .pi, clockwise: false)
        path.addLine(to: CGPoint(x: body.maxX - b, y: body.minY))
        path.addArc(center: CGPoint(x: body.maxX - b, y: body.minY + b),
                    radius: b, startAngle: 1.5 * .pi, endAngle: 2 * .pi, clockwise: false)
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        path.addArc(center: CGPoint(x: body.maxX + r, y: body.maxY - r),
                    radius: r, startAngle: .pi, endAngle: .pi / 2, clockwise: true)
        path.closeSubpath()
        return path
    }

    /// The popover: a rounded panel with a beak aimed at the rail. The tip is
    /// blunted with a quad curve so it matches the panel's soft corners instead
    /// of ending in a needle.
    static func popover(body: CGRect, cornerRadius: CGFloat,
                        beakSide: Side, beakCenterY: CGFloat,
                        beakDepth: CGFloat, beakHeight: CGFloat) -> CGPath {
        let r = min(cornerRadius, min(body.width, body.height) / 2)
        let path = CGMutablePath()
        let half = beakHeight / 2
        // Keep the beak inside the straight run of the edge it sits on.
        let centerY = min(max(beakCenterY, body.minY + r + half), body.maxY - r - half)

        func addBeak(onRight: Bool) {
            let edgeX = onRight ? body.maxX : body.minX
            let apex = CGPoint(x: onRight ? edgeX + beakDepth : edgeX - beakDepth, y: centerY)
            // Right-side beak is traversed top-to-bottom, left-side bottom-to-top.
            let near = CGPoint(x: edgeX, y: onRight ? centerY + half : centerY - half)
            let far = CGPoint(x: edgeX, y: onRight ? centerY - half : centerY + half)
            let blunt: CGFloat = 0.78
            func lerp(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
                CGPoint(x: a.x + (b.x - a.x) * blunt, y: a.y + (b.y - a.y) * blunt)
            }
            path.addLine(to: near)
            path.addLine(to: lerp(near, apex))
            path.addQuadCurve(to: lerp(far, apex), control: apex)
            path.addLine(to: far)
        }

        path.move(to: CGPoint(x: body.minX + r, y: body.maxY))
        path.addLine(to: CGPoint(x: body.maxX - r, y: body.maxY))
        path.addArc(center: CGPoint(x: body.maxX - r, y: body.maxY - r),
                    radius: r, startAngle: .pi / 2, endAngle: 0, clockwise: true)
        if beakSide == .right { addBeak(onRight: true) }
        path.addLine(to: CGPoint(x: body.maxX, y: body.minY + r))
        path.addArc(center: CGPoint(x: body.maxX - r, y: body.minY + r),
                    radius: r, startAngle: 0, endAngle: 1.5 * .pi, clockwise: true)
        path.addLine(to: CGPoint(x: body.minX + r, y: body.minY))
        path.addArc(center: CGPoint(x: body.minX + r, y: body.minY + r),
                    radius: r, startAngle: 1.5 * .pi, endAngle: .pi, clockwise: true)
        if beakSide == .left { addBeak(onRight: false) }
        path.addLine(to: CGPoint(x: body.minX, y: body.maxY - r))
        path.addArc(center: CGPoint(x: body.minX + r, y: body.maxY - r),
                    radius: r, startAngle: .pi, endAngle: .pi / 2, clockwise: true)
        path.closeSubpath()
        return path
    }
}

enum Palette {
    static let surface = NSColor(calibratedWhite: 0.043, alpha: 1).cgColor
    static let hairline = NSColor(calibratedWhite: 1, alpha: 0.09).cgColor
    static let track = NSColor(calibratedWhite: 1, alpha: 0.13).cgColor
    static let iconWell = NSColor(calibratedWhite: 1, alpha: 0.07).cgColor
    static let primaryText = NSColor(calibratedWhite: 1, alpha: 0.96)
    static let secondaryText = NSColor(calibratedWhite: 1, alpha: 0.46)
    static let offline = NSColor(calibratedWhite: 1, alpha: 0.28)

    static func cg(_ rgb: (r: Double, g: Double, b: Double), alpha: Double = 1) -> CGColor {
        CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
    }
}

enum Glyph {
    /// Each limit gets a mark drawn from what it actually measures: the live
    /// session carries the Claude asterisk, the longer windows carry the symbol
    /// for their span or their model.
    static func layer(forKind kind: String, boxSize: CGFloat, scale: CGFloat) -> CALayer {
        if kind == "session" { return asteriskLayer(boxSize: boxSize) }
        // A stroked burst reads at a smaller box than a filled symbol does.
        let symbolBox = boxSize * 0.92
        let symbol: String
        switch kind {
        case "weekly_all": symbol = "calendar"
        case "weekly_opus": symbol = "sparkles"
        case "weekly_sonnet": symbol = "bolt.fill"
        default: symbol = "circle.dashed"
        }
        return symbolLayer(symbol, boxSize: symbolBox, scale: scale)
            ?? asteriskLayer(boxSize: boxSize)
    }

    private static func asteriskLayer(boxSize: CGFloat) -> CALayer {
        let layer = CAShapeLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: boxSize, height: boxSize)
        let center = CGPoint(x: boxSize / 2, y: boxSize / 2)
        let outer = boxSize * 0.46
        let inner = boxSize * 0.07
        let path = CGMutablePath()
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4
            path.move(to: CGPoint(x: center.x + cos(angle) * inner,
                                  y: center.y + sin(angle) * inner))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * outer,
                                     y: center.y + sin(angle) * outer))
        }
        layer.path = path
        layer.strokeColor = Palette.primaryText.cgColor
        layer.fillColor = nil
        layer.lineWidth = boxSize * 0.11
        layer.lineCap = .round
        return layer
    }

    private static func symbolLayer(_ name: String, boxSize: CGFloat, scale: CGFloat) -> CALayer? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil),
              let configured = symbol.withSymbolConfiguration(
                .init(pointSize: boxSize, weight: .semibold))
        else { return nil }
        // Symbols arrive as black templates. Draw one, then flood the glyph's
        // own coverage with the text colour — masking a tint layer instead
        // leaves the alpha unpremultiplied and the mark comes out muddy.
        let size = configured.size
        let tinted = NSImage(size: size, flipped: false) { rect in
            configured.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            Palette.primaryText.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        var rect = CGRect(origin: .zero, size: size)
        guard let cgImage = tinted.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        else { return nil }
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        layer.contents = cgImage
        layer.contentsGravity = .resizeAspect
        layer.contentsScale = scale
        return layer
    }
}

enum TextLayerFactory {
    static func make(scale: CGFloat, alignment: CATextLayerAlignmentMode = .left) -> CATextLayer {
        let layer = CATextLayer()
        layer.contentsScale = scale
        layer.alignmentMode = alignment
        layer.truncationMode = .end
        layer.isWrapped = false
        return layer
    }

    static func attributed(_ string: String, size: CGFloat,
                           weight: NSFont.Weight, color: NSColor,
                           tracking: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .kern: tracking,
        ])
    }
}
