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
