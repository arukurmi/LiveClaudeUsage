import AppKit
import ClaudeBarCore

enum DisplayState: Equatable {
    case usage(percent: Double, resetsAt: Date?)
    /// Fetch failing, but we have a last known value — show it dimmed with a warning.
    case stale(percent: Double, resetsAt: Date?)
    case error
}

final class BarView: NSView {
    private let config: BarConfig
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private let timeLayer = CATextLayer()
    private let dotLayer = CALayer()
    private let hideChip = CALayer()
    private let hideGlyph = CATextLayer()
    private let emojiField = NSTextField(labelWithString: "")
    private var state: DisplayState = .usage(percent: 0, resetsAt: nil)
    private var hovering = false
    private var collapsed = false

    /// Fired when the user clicks the hide chip (expanded) or the dot (collapsed).
    var onToggleCollapse: (() -> Void)?

    private static let chipDiameter: CGFloat = 14

    init(config: BarConfig) {
        self.config = config
        super.init(frame: .zero)
        wantsLayer = true
        trackLayer.backgroundColor = NSColor.gray.withAlphaComponent(0.15).cgColor
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(fillLayer)
        // White with a dark halo stays readable on every threshold colour and on
        // the gray track when the fill is shorter than the text.
        timeLayer.alignmentMode = .center
        timeLayer.shadowColor = NSColor.black.cgColor
        timeLayer.shadowOpacity = 0.9
        timeLayer.shadowRadius = 1.5
        timeLayer.shadowOffset = .zero
        timeLayer.transform = CATransform3DMakeRotation(.pi / 2, 0, 0, 1)
        layer?.addSublayer(timeLayer)
        // The whole bar shrinks into this dot when collapsed.
        dotLayer.isHidden = true
        dotLayer.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        dotLayer.borderWidth = 1
        layer?.addSublayer(dotLayer)
        // Hover-revealed hide button at the foot of the bar.
        hideChip.isHidden = true
        hideChip.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        hideGlyph.string = "–"
        hideGlyph.alignmentMode = .center
        hideGlyph.foregroundColor = NSColor.white.cgColor
        hideGlyph.fontSize = 10
        hideChip.addSublayer(hideGlyph)
        layer?.addSublayer(hideChip)
        // Emoji glyphs render ~1.25x their point size wide; size from the bar
        // width so the emoji always fits inside the bar.
        let emojiSize = max(6, min(13, CGFloat(config.widthPx) * 0.75))
        emojiField.font = .systemFont(ofSize: emojiSize)
        emojiField.backgroundColor = .clear
        emojiField.isBezeled = false
        emojiField.alignment = .center
        addSubview(emojiField)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        applyState(animated: false)
    }

    func render(_ state: DisplayState) {
        self.state = state
        applyState(animated: true)
    }

    func setHovering(_ hovering: Bool) {
        guard self.hovering != hovering else { return }
        self.hovering = hovering
        applyState(animated: false)
    }

    func setCollapsed(_ collapsed: Bool) {
        guard self.collapsed != collapsed else { return }
        self.collapsed = collapsed
        applyState(animated: false)
    }

    // Click-through is disabled only while hovering the bar, so any click we
    // receive is intentional; the window is never key, so accept first clicks.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if collapsed || hideChip.frame.insetBy(dx: -4, dy: -4).contains(point) {
            onToggleCollapse?()
        }
    }

    private var barRect: (x: CGFloat, width: CGFloat) {
        let width = CGFloat(config.widthPx)
        let x = config.side == "left" ? 0 : bounds.width - width
        return (x, width)
    }

    private var currentColor: CGColor {
        switch state {
        case .usage(let percent, _), .stale(let percent, _):
            let clamped = min(max(percent, 0), 100)
            let rgb = HexColor.rgb(config.threshold(forPercent: clamped).color) ?? (r: 1, g: 0, b: 0)
            return CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 0.9)
        case .error:
            return NSColor.systemGray.withAlphaComponent(0.8).cgColor
        }
    }

    private func applyState(animated: Bool) {
        let (barX, barWidth) = barRect
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.6 : 0)

        if collapsed {
            trackLayer.isHidden = true
            fillLayer.isHidden = true
            timeLayer.isHidden = true
            hideChip.isHidden = true
            emojiField.isHidden = true
            dotLayer.isHidden = false
            let dotRect = bounds.insetBy(dx: 2, dy: 2)
            dotLayer.frame = dotRect
            dotLayer.cornerRadius = dotRect.width / 2
            dotLayer.backgroundColor = currentColor
            CATransaction.commit()
            return
        }

        dotLayer.isHidden = true
        trackLayer.isHidden = false
        fillLayer.isHidden = false
        trackLayer.frame = CGRect(x: barX, y: 0, width: barWidth, height: bounds.height)

        switch state {
        case .usage(let percent, let resetsAt), .stale(let percent, let resetsAt):
            let isStale = { if case .stale = state { return true } else { return false } }()
            let clamped = min(max(percent, 0), 100)
            let threshold = config.threshold(forPercent: clamped)
            // Stale data stays fully visible — a minutes-old percentage is still
            // useful; only the emoji signals that updates are paused.
            fillLayer.backgroundColor = currentColor
            let fillHeight = bounds.height * clamped / 100
            fillLayer.frame = CGRect(x: barX, y: 0, width: barWidth, height: fillHeight)
            emojiField.isHidden = !config.showEmoji && !isStale
            if !emojiField.isHidden {
                emojiField.stringValue = isStale ? "⚠️" : threshold.emoji
                positionEmoji(atFillHeight: fillHeight, barX: barX, barWidth: barWidth)
            }
            renderResetTime(resetsAt, fillHeight: fillHeight, barX: barX, barWidth: barWidth)
        case .error:
            fillLayer.backgroundColor = currentColor
            fillLayer.frame = CGRect(x: barX, y: 0, width: barWidth, height: bounds.height)
            emojiField.isHidden = false
            emojiField.stringValue = "⚠️"
            positionEmoji(atFillHeight: bounds.height / 2, barX: barX, barWidth: barWidth)
            timeLayer.isHidden = true
        }

        hideChip.isHidden = !hovering
        if hovering {
            let d = Self.chipDiameter
            hideChip.frame = CGRect(x: barX + (barWidth - d) / 2, y: 6, width: d, height: d)
            hideChip.cornerRadius = d / 2
            hideGlyph.frame = CGRect(x: 0, y: (d - 12) / 2 - 1, width: d, height: 12)
            hideGlyph.contentsScale = window?.backingScaleFactor ?? 2
        }
        CATransaction.commit()
    }

    private func positionEmoji(atFillHeight fillHeight: CGFloat, barX: CGFloat, barWidth: CGFloat) {
        emojiField.sizeToFit()
        let size = emojiField.frame.size
        // Perched on top of the fill line: emoji bottom touches the fill's top edge.
        let y = min(max(fillHeight, 0), bounds.height - size.height)
        let rawX = barX + (barWidth - size.width) / 2
        let x = min(max(rawX, 0), bounds.width - size.width)
        emojiField.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Reset time rotated 90° so it reads bottom-to-top inside the bar,
    /// centered on the midpoint of the filled portion so it rides up as usage grows.
    private func renderResetTime(_ resetsAt: Date?, fillHeight: CGFloat,
                                 barX: CGFloat, barWidth: CGFloat) {
        guard config.showResetTime, let resetsAt else {
            timeLayer.isHidden = true
            return
        }
        timeLayer.isHidden = false
        timeLayer.contentsScale = window?.backingScaleFactor ?? 2
        let fontSize = max(6, min(9, barWidth * 0.75))
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attributed = NSAttributedString(
            string: ResetTimeFormatter.string(from: resetsAt),
            attributes: [.font: font, .foregroundColor: NSColor.white]
        )
        timeLayer.string = attributed
        let size = attributed.size()
        // bounds is the unrotated text box; after the 90° transform its width
        // runs up the screen. Center it at half the fill height, clamped so a
        // near-empty or near-full bar never pushes the text off screen.
        timeLayer.bounds = CGRect(x: 0, y: 0, width: ceil(size.width), height: ceil(size.height))
        let halfLength = ceil(size.width) / 2
        let y = min(max(fillHeight / 2, halfLength + 2), bounds.height - halfLength - 2)
        timeLayer.position = CGPoint(x: barX + barWidth / 2, y: y)
    }
}
