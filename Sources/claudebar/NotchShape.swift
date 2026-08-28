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
}
