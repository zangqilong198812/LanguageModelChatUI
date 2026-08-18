//
//  Created by ktiays on 2025/2/28.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import UIKit

final class ToolHintView: MessageListRowView {
    var text: String? {
        didSet { detailLabel.text = text }
    }

    var toolName: String = .init()

    var state: ToolCallState = .running {
        didSet {
            updateContentText()
            updateStateImage()
        }
    }

    /// Whether the chip is showing the full tool parameters below its one
    /// line. The row height is the adapter's business; this only decides
    /// whether the detail area is laid out.
    var isExpanded: Bool = false {
        didSet {
            detailLabel.isHidden = !isExpanded
            invalidateLayout()
        }
    }

    var clickHandler: (() -> Void)?

    /// Height of a hint row, matching the chip's own layout: a one-line body,
    /// plus the parameter detail area when expanded.
    static func height(isExpanded: Bool, detailHeight: CGFloat, bodyLineHeight: CGFloat) -> CGFloat {
        if isExpanded {
            return 8 + bodyLineHeight + 8 + detailHeight + 8
        }
        return bodyLineHeight + 20
    }

    private let backgroundGradientLayer = CAGradientLayer()
    private let label: ShimmerTextLabel = .init().with {
        $0.font = UIFont.preferredFont(forTextStyle: .body)
        $0.textColor = .label
        $0.minimumScaleFactor = 0.5
        $0.adjustsFontForContentSizeCategory = true
        $0.lineBreakMode = .byTruncatingTail
        $0.numberOfLines = 1
        $0.adjustsFontSizeToFitWidth = true
        $0.textAlignment = .left
        $0.animationDuration = 1.6
    }

    private let symbolView: UIImageView = .init().with {
        $0.contentMode = .scaleAspectFit
    }

    private let detailLabel: UILabel = .init().with {
        $0.numberOfLines = 0
        $0.lineBreakMode = .byWordWrapping
        $0.isHidden = true
    }

    private let decoratedView: UIImageView = .init(image: .init(named: "tools"))
    private var isClickable: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        decoratedView.contentMode = .scaleAspectFit
        decoratedView.tintColor = .label

        backgroundGradientLayer.startPoint = .init(x: 0.6, y: 0)
        backgroundGradientLayer.endPoint = .init(x: 0.4, y: 1)

        contentView.backgroundColor = .clear
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
        contentView.layer.insertSublayer(backgroundGradientLayer, at: 0)
        contentView.addSubview(decoratedView)
        contentView.addSubview(symbolView)
        contentView.addSubview(label)
        contentView.addSubview(detailLabel)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        contentView.addGestureRecognizer(tapGesture)

        updateStateImage()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let labelSize = label.intrinsicContentSize
        let symbolSize = labelSize.height // 1:1
        let bodyY = isExpanded ? 8 : max(0, (contentView.bounds.height - symbolSize) / 2)

        symbolView.frame = .init(x: 12, y: bodyY, width: symbolSize, height: symbolSize)
        label.frame = .init(
            x: symbolView.frame.maxX + 8,
            y: bodyY,
            width: labelSize.width,
            height: symbolSize
        )

        if isExpanded {
            let detailWidth = max(0, bounds.width - 24)
            let detailHeight = detailLabel.sizeThatFits(
                .init(width: detailWidth, height: .greatestFiniteMagnitude)
            ).height
            detailLabel.frame = .init(
                x: 12,
                y: symbolView.frame.maxY + 8,
                width: detailWidth,
                height: detailHeight
            )
            contentView.frame.size = .init(
                width: max(label.frame.maxX + 18, detailWidth + 24),
                height: detailLabel.frame.maxY + 8
            )
        } else {
            detailLabel.frame = .zero
            contentView.frame.size.width = label.frame.maxX + 18
        }

        decoratedView.frame = .init(x: contentView.bounds.width - 12, y: -4, width: 16, height: 16)
        backgroundGradientLayer.frame = contentView.bounds
        backgroundGradientLayer.cornerRadius = contentView.layer.cornerRadius
    }

    override func themeDidUpdate() {
        super.themeDidUpdate()
        label.font = theme.fonts.body
        detailLabel.font = theme.fonts.footnote
        detailLabel.textColor = .secondaryLabel
    }

    private func updateStateImage() {
        let configuration = UIImage.SymbolConfiguration(scale: .small)
        switch state {
        case .succeeded:
            backgroundGradientLayer.colors = [
                UIColor.systemGreen.withAlphaComponent(0.08).cgColor,
                UIColor.systemGreen.withAlphaComponent(0.12).cgColor,
            ]
            let image = UIImage(systemName: "checkmark.seal", withConfiguration: configuration)
            symbolView.image = image
            symbolView.tintColor = .systemGreen
            label.stopShimmer()
        case .running:
            backgroundGradientLayer.colors = [
                UIColor.systemBlue.withAlphaComponent(0.08).cgColor,
                UIColor.systemBlue.withAlphaComponent(0.12).cgColor,
            ]
            let image = UIImage(systemName: "hourglass", withConfiguration: configuration)
            symbolView.image = image
            symbolView.tintColor = .systemBlue
            label.startShimmer()
        case .failed:
            backgroundGradientLayer.colors = [
                UIColor.systemRed.withAlphaComponent(0.08).cgColor,
                UIColor.systemRed.withAlphaComponent(0.12).cgColor,
            ]
            let image = UIImage(systemName: "xmark.seal", withConfiguration: configuration)
            symbolView.image = image
            symbolView.tintColor = .systemRed
            label.stopShimmer()
        }
        invalidateLayout()
    }

    private func updateContentText() {
        switch state {
        case .running:
            isClickable = false
            label.text = String.localized("Tool call for \(toolName) running")
        case .succeeded:
            isClickable = true
            label.text = String.localized("Tool call for \(toolName) completed.")
        case .failed:
            isClickable = true
            label.text = String.localized("Tool call for \(toolName) failed.")
        }
        invalidateLayout()
    }

    func invalidateLayout() {
        label.invalidateIntrinsicContentSize()
        label.sizeToFit()
        setNeedsLayout()

        doWithAnimation {
            self.layoutIfNeeded()
        }
    }

    @objc
    private func handleTap(_ sender: UITapGestureRecognizer) {
        if isClickable, sender.state == .ended {
            clickHandler?()
        }
    }
}
