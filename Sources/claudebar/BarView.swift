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
        emojiField.font = .systemFont(ofSize: 13)
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
            break // Task 8
        }
        CATransaction.commit()
    }

    private func positionEmoji(atFillHeight fillHeight: CGFloat, barX: CGFloat, barWidth: CGFloat) {
        emojiField.sizeToFit()
        let size = emojiField.frame.size
        let y = min(max(fillHeight - size.height / 2, 0), bounds.height - size.height)
        let x = config.side == "left" ? barX + barWidth : barX - size.width
        emojiField.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
