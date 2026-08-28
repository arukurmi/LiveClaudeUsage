import AppKit
import ClaudeBarCore

/// The panel the rail opens: every limit spelled out with its name, when it
/// resets, and how much of it is gone.
final class PopoverView: NSView {
    private struct Row {
        let name: CATextLayer
        let reset: CATextLayer
        let track: CALayer
        let fill: CALayer
        let used: CATextLayer
    }

    private let config: BarConfig
    private let side: Side
    private let background = CAShapeLayer()
    private let titleLayer = CATextLayer()
    private var markLayer: CALayer?
    private var rows: [Row] = []
    private var state: DisplayState = .error
    private var beakCenterY: CGFloat = 0

    init(config: BarConfig) {
        self.config = config
        // The beak points back at the rail, so it sits on the edge facing it.
        self.side = config.side == "left" ? .left : .right
        super.init(frame: .zero)
        wantsLayer = true
        background.fillColor = Palette.surface
        background.strokeColor = Palette.hairline
        background.lineWidth = 1
        layer?.addSublayer(background)
        layer?.addSublayer(titleLayer)
        let mark = Glyph.layer(forKind: "session", boxSize: 15, scale: 2)
        layer?.addSublayer(mark)
        markLayer = mark
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var scale: CGFloat { window?.backingScaleFactor ?? 2 }

    /// The panel rectangle, leaving the beak room on the side facing the rail.
    var bodyRect: CGRect {
        let depth = RailMetrics.beakDepth
        return CGRect(x: side == .right ? 0 : depth, y: 0,
                      width: bounds.width - depth, height: bounds.height)
    }

    private var limits: [UsageLimit] { state.snapshot?.limits ?? [] }

    /// Vertical centre for the beak, in view coordinates — aimed at the first ring.
    func setBeakCenterY(_ y: CGFloat) {
        beakCenterY = y
        needsLayout = true
    }

    func render(_ state: DisplayState) {
        let previousKinds = self.state.snapshot?.limits.map(\.kind) ?? []
        self.state = state
        if limits.map(\.kind) != previousKinds || rows.count != limits.count {
            rebuildRows()
        }
        applyState(animated: true)
    }

    override func layout() {
        super.layout()
        applyState(animated: false)
    }

    private func rebuildRows() {
        rows.forEach {
            [$0.name, $0.reset, $0.used].forEach { layer in layer.removeFromSuperlayer() }
            $0.track.removeFromSuperlayer()
        }
        rows = limits.map { _ in
            let name = TextLayerFactory.make(scale: scale)
            let reset = TextLayerFactory.make(scale: scale, alignment: .right)
            let track = CALayer()
            track.backgroundColor = Palette.track
            track.cornerRadius = RailMetrics.popoverTrackHeight / 2
            track.masksToBounds = true
            let fill = CALayer()
            fill.cornerRadius = RailMetrics.popoverTrackHeight / 2
            fill.anchorPoint = CGPoint(x: 0, y: 0.5)
            track.addSublayer(fill)
            let used = TextLayerFactory.make(scale: scale)
            [name, reset, used].forEach { layer?.addSublayer($0) }
            layer?.addSublayer(track)
            return Row(name: name, reset: reset, track: track, fill: fill, used: used)
        }
    }

    private func applyState(animated: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? Motion.duration(0.55) : 0)
        if !animated { CATransaction.setDisableActions(true) }

        let body = bodyRect
        background.frame = bounds
        background.path = NotchShape.popover(
            body: body,
            cornerRadius: RailMetrics.popoverCornerRadius,
            beakSide: side,
            beakCenterY: beakCenterY,
            beakDepth: RailMetrics.beakDepth,
            beakHeight: RailMetrics.beakHeight)

        let pad = RailMetrics.popoverPadding
        let contentX = body.minX + pad
        let contentWidth = body.width - pad * 2

        markLayer?.position = CGPoint(x: contentX + 7.5,
                                      y: body.maxY - pad - RailMetrics.popoverHeaderHeight / 2)
        titleLayer.contentsScale = scale
        titleLayer.string = TextLayerFactory.attributed(
            "Claude Usage", size: 13.5, weight: .semibold, color: Palette.primaryText)
        titleLayer.frame = CGRect(x: contentX + 22,
                                  y: body.maxY - pad - RailMetrics.popoverHeaderHeight,
                                  width: contentWidth - 22,
                                  height: RailMetrics.popoverHeaderHeight)

        let now = Date()
        for (index, limit) in limits.enumerated() {
            guard index < rows.count else { break }
            let row = rows[index]
            let top = body.maxY - RailMetrics.popoverRowTopOffset(index: index)
            let percent = min(max(limit.percent, 0), 100)

            row.name.string = TextLayerFactory.attributed(
                limit.title, size: 11.5, weight: .medium, color: Palette.primaryText)
            row.name.frame = CGRect(x: contentX, y: top - 14, width: contentWidth * 0.5, height: 14)

            let resetText = limit.resetsAt.map { ResetLabel.string(for: $0, now: now) }
                ?? "No reset time"
            row.reset.string = TextLayerFactory.attributed(
                state.isStale ? "Updates paused" : resetText,
                size: 11, weight: .regular, color: Palette.secondaryText)
            row.reset.frame = CGRect(x: contentX + contentWidth * 0.42, y: top - 14,
                                     width: contentWidth * 0.58, height: 14)

            let trackHeight = RailMetrics.popoverTrackHeight
            row.track.frame = CGRect(x: contentX, y: top - 14 - 7 - trackHeight,
                                     width: contentWidth, height: trackHeight)
            row.fill.backgroundColor = Palette.cg(config.color(forPercent: percent),
                                                  alpha: state.isStale ? 0.5 : 1)
            row.fill.position = CGPoint(x: 0, y: trackHeight / 2)
            row.fill.bounds = CGRect(x: 0, y: 0,
                                     width: max(contentWidth * percent / 100, trackHeight),
                                     height: trackHeight)

            row.used.string = TextLayerFactory.attributed(
                "\(Int(percent.rounded()))% Used", size: 11, weight: .regular,
                color: Palette.secondaryText)
            row.used.frame = CGRect(x: contentX, y: top - RailMetrics.popoverRowHeight,
                                    width: contentWidth, height: 14)
        }

        emptyLayer.isHidden = !limits.isEmpty
        if limits.isEmpty {
            emptyLayer.contentsScale = scale
            emptyLayer.string = TextLayerFactory.attributed(
                "No usage data yet. Sign in with the claude CLI, then reopen this.",
                size: 11.5, weight: .regular, color: Palette.secondaryText)
            emptyLayer.isWrapped = true
            emptyLayer.frame = CGRect(x: contentX, y: body.minY + pad,
                                      width: contentWidth,
                                      height: body.height - pad * 2
                                          - RailMetrics.popoverHeaderHeight
                                          - RailMetrics.popoverHeaderGap)
        }
        CATransaction.commit()
    }

    private lazy var emptyLayer: CATextLayer = {
        let layer = TextLayerFactory.make(scale: scale)
        self.layer?.addSublayer(layer)
        return layer
    }()
}
