import AppKit
import ClaudeBarCore

enum DisplayState: Equatable {
    case usage(percent: Double)
    case error
}

final class BarView: NSView {
    private let config: BarConfig
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private let emojiField = NSTextField(labelWithString: "")
    private var state: DisplayState = .usage(percent: 0)

    init(config: BarConfig) {
        self.config = config
        super.init(frame: .zero)
        wantsLayer = true
        trackLayer.backgroundColor = NSColor.gray.withAlphaComponent(0.15).cgColor
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(fillLayer)
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

    private var barRect: (x: CGFloat, width: CGFloat) {
        let width = CGFloat(config.widthPx)
        let x = config.side == "left" ? 0 : bounds.width - width
        return (x, width)
    }

    private func applyState(animated: Bool) {
        let (barX, barWidth) = barRect
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.6 : 0)
        trackLayer.frame = CGRect(x: barX, y: 0, width: barWidth, height: bounds.height)

        switch state {
        case .usage(let percent):
            let clamped = min(max(percent, 0), 100)
            let threshold = config.threshold(forPercent: clamped)
            let rgb = HexColor.rgb(threshold.color) ?? (r: 1, g: 0, b: 0)
            fillLayer.backgroundColor = CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 0.9)
            let fillHeight = bounds.height * clamped / 100
            fillLayer.frame = CGRect(x: barX, y: 0, width: barWidth, height: fillHeight)
            emojiField.isHidden = !config.showEmoji
            if config.showEmoji {
                emojiField.stringValue = threshold.emoji
                positionEmoji(atFillHeight: fillHeight, barX: barX, barWidth: barWidth)
            }
        case .error:
            fillLayer.backgroundColor = NSColor.gray.withAlphaComponent(0.5).cgColor
            fillLayer.frame = CGRect(x: barX, y: 0, width: barWidth, height: bounds.height)
            emojiField.isHidden = false
            emojiField.stringValue = "⚠️"
            positionEmoji(atFillHeight: bounds.height / 2, barX: barX, barWidth: barWidth)
        }
        CATransaction.commit()
    }

    private func positionEmoji(atFillHeight fillHeight: CGFloat, barX: CGFloat, barWidth: CGFloat) {
        emojiField.sizeToFit()
        let size = emojiField.frame.size
        // Inside the bar, hugging the top line of the fill from below.
        let y = min(max(fillHeight - size.height, 0), bounds.height - size.height)
        let rawX = barX + (barWidth - size.width) / 2
        let x = min(max(rawX, 0), bounds.width - size.width)
        emojiField.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
