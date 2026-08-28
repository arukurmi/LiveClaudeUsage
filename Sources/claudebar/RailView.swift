import AppKit
import ClaudeBarCore

/// The tab hanging off the menu bar: one ring per limit, each with the mark for
/// what it measures and its percentage beneath.
final class RailView: NSView {
    private struct Ring {
        let kind: String
        let container: CALayer
        let well: CALayer
        let track: CAShapeLayer
        let arc: CAShapeLayer
        let icon: CALayer
        let label: CATextLayer
    }

    private let config: BarConfig
    private let side: Side
    private let background = CAShapeLayer()
    private var rings: [Ring] = []
    private var state: DisplayState = .error

    /// Right-click anywhere on the tab.
    var onContextMenu: ((NSEvent) -> Void)?

    init(config: BarConfig) {
        self.config = config
        self.side = config.side == "left" ? .left : .right
        super.init(frame: .zero)
        wantsLayer = true
        background.fillColor = Palette.surface
        background.strokeColor = Palette.hairline
        background.lineWidth = 1
        layer?.addSublayer(background)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var scale: CGFloat { window?.backingScaleFactor ?? 2 }

    /// The visible tab, inset from the view's bounds by the room the concave
    /// corners need on either side.
    var bodyRect: CGRect {
        bounds.insetBy(dx: RailMetrics.earRadius, dy: 0)
    }

    var limits: [UsageLimit] {
        state.snapshot?.limits ?? []
    }

    func render(_ state: DisplayState) {
        let previousKinds = self.state.snapshot?.limits.map(\.kind) ?? []
        self.state = state
        let kinds = limits.map(\.kind)
        if kinds != previousKinds || rings.count != kinds.count {
            rebuildRings()
        }
        applyState(animated: true)
        updateAccessibility()
    }

    /// The tab is a status readout. Without this VoiceOver reaches it and finds
    /// an unlabelled group of circles, which is worse than it being invisible.
    private func updateAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Claude usage")
        guard !limits.isEmpty else {
            setAccessibilityValue("No usage data yet")
            return
        }
        let now = Date()
        let spoken = limits.map { limit -> String in
            var text = "\(limit.title), \(Int(limit.percent.rounded())) percent used"
            if let resetsAt = limit.resetsAt {
                text += ", \(ResetLabel.string(for: resetsAt, now: now).lowercased())"
            }
            return text
        }
        setAccessibilityValue(spoken.joined(separator: ". "))
    }

    override func layout() {
        super.layout()
        applyState(animated: false)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rebuildRings()
        applyState(animated: false)
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func rebuildRings() {
        rings.forEach { $0.container.removeFromSuperlayer() }
        rings = limits.map { limit in
            let container = CALayer()
            let d = RailMetrics.ringDiameter

            let well = CALayer()
            well.bounds = CGRect(x: 0, y: 0, width: d, height: d)
            well.cornerRadius = d / 2
            well.backgroundColor = Palette.iconWell
            container.addSublayer(well)

            let circle = CGMutablePath()
            let inset = RailMetrics.ringStroke / 2
            circle.addArc(center: CGPoint(x: d / 2, y: d / 2),
                          radius: d / 2 - inset,
                          startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi,
                          clockwise: true)

            let track = CAShapeLayer()
            track.bounds = well.bounds
            track.path = circle
            track.fillColor = nil
            track.strokeColor = Palette.track
            track.lineWidth = RailMetrics.ringStroke
            container.addSublayer(track)

            let arc = CAShapeLayer()
            arc.bounds = well.bounds
            arc.path = circle
            arc.fillColor = nil
            arc.lineWidth = RailMetrics.ringStroke
            arc.lineCap = .round
            arc.strokeEnd = 0
            container.addSublayer(arc)

            let icon = Glyph.layer(forKind: limit.kind, boxSize: d * 0.44, scale: scale)
            container.addSublayer(icon)

            let label = TextLayerFactory.make(scale: scale, alignment: .center)
            container.addSublayer(label)

            layer?.addSublayer(container)
            return Ring(kind: limit.kind, container: container, well: well,
                        track: track, arc: arc, icon: icon, label: label)
        }
    }

    private func applyState(animated: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.55 : 0)
        if !animated { CATransaction.setDisableActions(true) }

        background.frame = bounds
        background.path = NotchShape.tab(body: bodyRect,
                                         ear: RailMetrics.earRadius,
                                         bottomRadius: RailMetrics.railBottomRadius)

        let body = bodyRect
        let d = RailMetrics.ringDiameter
        for (index, limit) in limits.enumerated() {
            guard index < rings.count else { break }
            let ring = rings[index]
            let top = body.maxY - RailMetrics.itemTopOffset(index: index)
            ring.container.frame = CGRect(x: body.midX - d / 2, y: top - RailMetrics.itemHeight,
                                          width: d, height: RailMetrics.itemHeight)

            let ringRect = CGRect(x: 0, y: RailMetrics.itemHeight - d, width: d, height: d)
            ring.well.frame = ringRect
            ring.track.frame = ringRect
            ring.arc.frame = ringRect
            ring.icon.position = CGPoint(x: ringRect.midX, y: ringRect.midY)

            let percent = min(max(limit.percent, 0), 100)
            let dim = state.isStale ? 0.5 : 1.0
            ring.arc.strokeColor = Palette.cg(config.color(forPercent: percent), alpha: dim)
            ring.arc.strokeEnd = percent / 100
            ring.icon.opacity = Float(state.isStale ? 0.5 : 1)

            let text = TextLayerFactory.attributed(
                "\(Int(percent.rounded()))%", size: 12, weight: .semibold,
                color: state.isStale ? Palette.secondaryText : Palette.primaryText)
            ring.label.string = text
            ring.label.frame = CGRect(x: -RailMetrics.railHorizontalPadding, y: 0,
                                      width: body.width,
                                      height: RailMetrics.percentLabelHeight)
        }

        if case .error = state {
            renderErrorGlyph()
        } else {
            errorLayer.isHidden = true
        }
        CATransaction.commit()
    }

    private lazy var errorLayer: CATextLayer = {
        let layer = TextLayerFactory.make(scale: scale, alignment: .center)
        self.layer?.addSublayer(layer)
        return layer
    }()

    /// No data at all: the tab still shows, so the popover stays reachable and
    /// the user can see the app is running rather than crashed.
    private func renderErrorGlyph() {
        errorLayer.isHidden = false
        errorLayer.string = TextLayerFactory.attributed(
            "—", size: 17, weight: .medium, color: Palette.offline)
        let body = bodyRect
        errorLayer.frame = CGRect(x: body.minX, y: body.midY - 12,
                                  width: body.width, height: 24)
    }
}
