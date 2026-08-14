//
//  ProgressCardView.swift
//  LanguageModelChatUI
//

import MarkdownView
import UIKit

/// The working card's outcome and thinking colours, system by default.
///
/// A host with its own palette sets these once at startup; the theme has no
/// slot for them and the tint is already taken by "running".
@MainActor
public enum ProgressAccents {
    public static var success: UIColor = .systemGreen
    public static var failure: UIColor = .systemRed
    public static var thinking: UIColor = .systemPurple
}

/// A coding agent's working block, drawn as one card.
///
/// Its height is fixed. A turn can run sixteen tools and the message must not
/// grow with them, so the card keeps a window of the newest steps, fades the
/// edge where the rest went — a hard edge reads as the end of a list, and this
/// is the middle of one — and says how many are above.
final class ProgressCardView: MessageListRowView {
    /// How many steps fit before the card starts hiding them.
    static let window = 6
    static let rowHeight: CGFloat = 18
    static let rowSpacing: CGFloat = 7
    private static let headerHeight: CGFloat = 34
    private static let footerHeight: CGFloat = 26
    private static let sweepHeight: CGFloat = 2
    private static let padding: CGFloat = 10
    private static let gutterWidth: CGFloat = 34

    /// The card's height for a block, known without laying anything out: the
    /// window is what makes it a constant rather than a measurement.
    static func height(steps: Int, hasFooter: Bool, isRunning: Bool) -> CGFloat {
        let shown = min(steps, window)
        let rows = CGFloat(shown) * rowHeight + CGFloat(max(0, shown - 1)) * rowSpacing
        return headerHeight + padding * 2 + rows
            + (hasFooter ? footerHeight : 0)
            + (isRunning ? sweepHeight : 0)
    }

    private let header = UIView()
    private let statusDot = UIView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let stepsContainer = UIView()
    private let footer = UIView()
    private let hiddenLabel = UILabel()
    private let expandLabel = UILabel()
    private let sweep = UIView()
    private let sweepTrack = UIView()
    private let gradientMask = CAGradientLayer()
    private let avatar = AgentAvatarView()

    /// The host app's tint. The theme carries text colours only, and a card
    /// that hard-coded a blue would fight whatever the app is set in.
    static var accentColor: UIColor { .tintColor }

    static var successColor: UIColor { ProgressAccents.success }
    static var failureColor: UIColor { ProgressAccents.failure }
    static var thinkingColor: UIColor { ProgressAccents.thinking }

    private var stepViews: [ProgressStepView] = []
    private var block: ProgressBlock?
    private var steps: [ProgressStep] = []

    /// Called when the footer is tapped. The card does not own the expanded
    /// state: whoever holds the transcript decides what a tap means.
    var expandHandler: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layer.cornerRadius = 15
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 1
        contentView.clipsToBounds = true

        statusDot.layer.cornerRadius = 3.5
        countLabel.textColor = .tertiaryLabel
        hiddenLabel.textColor = .secondaryLabel

        header.addSubview(statusDot)
        header.addSubview(titleLabel)
        header.addSubview(countLabel)
        footer.addSubview(hiddenLabel)
        footer.addSubview(expandLabel)
        sweepTrack.addSubview(sweep)

        addSubview(avatar)
        contentView.addSubview(header)
        contentView.addSubview(stepsContainer)
        contentView.addSubview(footer)
        contentView.addSubview(sweepTrack)

        // Older steps run off the top rather than being cut: the fade says
        // there is more above, where a hard edge would say there is not.
        gradientMask.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
        gradientMask.startPoint = .init(x: 0.5, y: 0)
        gradientMask.endPoint = .init(x: 0.5, y: 1)

        footer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleExpand)))
        footer.isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleExpand() { expandHandler?() }

    func configure(block: ProgressBlock, steps: [ProgressStep]) {
        self.block = block
        self.steps = steps

        // Sizes are the card's, family is the app's: the theme carries the
        // typeface and this decides how big each part of the card is in it.
        titleLabel.font = theme.fonts.bold.withSize(13)
        expandLabel.font = theme.fonts.body.withSize(11.5)
        countLabel.font = theme.fonts.codeInline.withSize(10)
        hiddenLabel.font = theme.fonts.codeInline.withSize(10)

        switch block.state {
        case .running:
            titleLabel.text = String.localized("Working")
            titleLabel.textColor = Self.accentColor
            statusDot.backgroundColor = Self.accentColor
            statusDot.isHidden = false
            contentView.layer.borderColor = Self.accentColor.withAlphaComponent(0.22).cgColor
        case .completed:
            titleLabel.text = String.localized("Turn complete")
            titleLabel.textColor = Self.successColor
            statusDot.isHidden = true
            contentView.layer.borderColor = UIColor.separator.cgColor
        case .failed:
            titleLabel.text = String.localized("Turn failed")
            titleLabel.textColor = Self.failureColor
            statusDot.isHidden = true
            contentView.layer.borderColor = Self.failureColor.withAlphaComponent(0.3).cgColor
        }

        contentView.backgroundColor = block.state == .running
            ? Self.accentColor.withAlphaComponent(0.03)
            : .clear
        countLabel.text = String(format: String.localized("%lld steps"), block.stepCount)
        sweepTrack.isHidden = block.state != .running
        if block.state == .running { startSweeping() }

        let shown = Array(steps.suffix(Self.window))
        let hidden = max(0, block.stepCount - shown.count)
        footer.isHidden = hidden == 0
        hiddenLabel.text = "+\(hidden)"
        expandLabel.text = String.localized("Show all")
        expandLabel.textColor = Self.accentColor

        // Reused rather than rebuilt: a block is rewritten many times a second
        // while a turn runs, and rebuilding would restart every animation in it.
        while stepViews.count < shown.count {
            let view = ProgressStepView()
            stepsContainer.addSubview(view)
            stepViews.append(view)
        }
        for (index, view) in stepViews.enumerated() {
            view.isHidden = index >= shown.count
            guard index < shown.count else { continue }
            view.configure(
                shown[index],
                theme: theme,
                showsCaret: block.state == .running && index == shown.count - 1
            )
        }
        setNeedsLayout()
    }

    private func startSweeping() {
        guard sweep.layer.animation(forKey: "sweep") == nil else { return }
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.duration = 1.9
        animation.repeatCount = .infinity
        animation.timingFunction = .init(name: .easeInEaseOut)
        sweep.layer.add(animation, forKey: "sweep")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The card sits in the agent's column, with the mark beside its head.
        avatar.frame = .init(
            x: MessageListView.listRowInsets.left,
            y: 2,
            width: AgentAvatarView.size,
            height: AgentAvatarView.size
        )
        var box = contentView.frame
        box.origin.x = MessageListView.listRowInsets.left + AgentAvatarView.column
        box.size.width = bounds.width - box.origin.x - MessageListView.listRowInsets.right
        contentView.frame = box

        let width = contentView.bounds.width

        header.frame = .init(x: 0, y: 0, width: width, height: Self.headerHeight)
        statusDot.frame = .init(x: 12, y: (Self.headerHeight - 7) / 2, width: 7, height: 7)
        let titleX: CGFloat = statusDot.isHidden ? 12 : 27
        titleLabel.frame = .init(x: titleX, y: 0, width: width - titleX - 84, height: Self.headerHeight)
        countLabel.frame = .init(x: width - 76, y: 0, width: 64, height: Self.headerHeight)
        countLabel.textAlignment = .right

        var y = Self.headerHeight + Self.padding
        let rowsHeight = CGFloat(stepViews.filter { !$0.isHidden }.count) * Self.rowHeight
            + CGFloat(max(0, stepViews.filter { !$0.isHidden }.count - 1)) * Self.rowSpacing
        stepsContainer.frame = .init(x: 12, y: y, width: width - 24, height: rowsHeight)
        var rowY: CGFloat = 0
        for view in stepViews where !view.isHidden {
            view.frame = .init(x: 0, y: rowY, width: stepsContainer.bounds.width, height: Self.rowHeight)
            rowY += Self.rowHeight + Self.rowSpacing
        }

        if footer.isHidden {
            gradientMask.frame = stepsContainer.bounds
            gradientMask.locations = [0, 0]
            stepsContainer.layer.mask = nil
        } else {
            gradientMask.frame = stepsContainer.bounds
            gradientMask.locations = [0, 0.22]
            stepsContainer.layer.mask = gradientMask
        }

        y += rowsHeight + Self.padding
        if !footer.isHidden {
            footer.frame = .init(x: 0, y: y, width: width, height: Self.footerHeight)
            hiddenLabel.frame = .init(x: 12, y: 0, width: 60, height: Self.footerHeight)
            expandLabel.frame = .init(x: width - 92, y: 0, width: 80, height: Self.footerHeight)
            expandLabel.textAlignment = .right
            y += Self.footerHeight
        }
        if !sweepTrack.isHidden {
            sweepTrack.frame = .init(x: 0, y: y, width: width, height: Self.sweepHeight)
            sweepTrack.backgroundColor = Self.accentColor.withAlphaComponent(0.12)
            sweep.frame = .init(x: 0, y: 0, width: width * 0.4, height: Self.sweepHeight)
            sweep.backgroundColor = Self.accentColor
        }
    }
}

/// One step: its kind in a fixed gutter, then one line that truncates.
final class ProgressStepView: UIView {
    private let kindLabel = UILabel()
    private let textLabel = UILabel()
    private let caret = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.numberOfLines = 1
        caret.layer.cornerRadius = 1
        addSubview(kindLabel)
        addSubview(textLabel)
        addSubview(caret)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ step: ProgressStep, theme: MarkdownTheme, showsCaret: Bool) {
        kindLabel.font = theme.fonts.codeInline.withSize(10)
        textLabel.font = theme.fonts.body.withSize(13)
        kindLabel.text = step.kind.label
        kindLabel.textColor = switch step.kind {
        case .thinking: ProgressCardView.thinkingColor
        case .tool: ProgressCardView.accentColor
        case .result: step.failed ? ProgressCardView.failureColor : ProgressCardView.successColor
        case .note: .secondaryLabel
        }
        textLabel.text = step.text
        textLabel.textColor = theme.colors.body
        caret.isHidden = !showsCaret
        caret.backgroundColor = theme.colors.body
        if showsCaret { startBlinking() } else { caret.layer.removeAllAnimations() }
        setNeedsLayout()
    }

    private func startBlinking() {
        guard caret.layer.animation(forKey: "blink") == nil else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0
        animation.duration = 0.55
        animation.autoreverses = true
        animation.repeatCount = .infinity
        caret.layer.add(animation, forKey: "blink")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        kindLabel.frame = .init(x: 0, y: 0, width: 34, height: bounds.height)
        let textWidth = bounds.width - 42 - (caret.isHidden ? 0 : 12)
        textLabel.frame = .init(x: 42, y: 0, width: max(0, textWidth), height: bounds.height)
        caret.frame = .init(x: 42 + textLabel.intrinsicContentSize.width + 4, y: 3, width: 6, height: 12)
    }
}
